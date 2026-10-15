// @frontmatter:start
// Owns selected DevTools private fixtures and gates removal on request, child, and exact-service cleanup.
// @frontmatter:end
import Foundation
import Scenario

@MainActor final class DevToolsScenarioLifecycle {
	private(set) var home: IsolatedScenarioHome?
	private(set) var host: PackagedXPCHost?
	private(set) var projects: DevToolsScenarioProjects?
	private var service: OwnedProcessIdentity?
	private let requests = RequestState()
	private var teardownComplete = false
	var serviceStopped: Bool { requests.serviceStopped }
	var childAttempted = false
	var child: OwnedProcessIdentity?
	var passed = false

	func setup(
		includePreviewResources: Bool = false, beforeHost: () throws -> Void = {}
	) throws {
		guard
			self.home == nil, !requests.serviceStopped, !requests.stopFailed
		else { throw ScenarioFailure.message("DevTools lifecycle already allocated or stopped") }
		let home = try IsolatedScenarioHome()
		self.home = home
		print("DEVTOOLS_PRIVATE_HOME \(home.directory.path)")
		projects = DevToolsScenarioProjects(root: try home.privateDirectory(".mac-apper"))
		try home.linkInstalledToolchain()
		try beforeHost()
		host = try DevToolsScenarioInputs.host(
			includePreviewResources: includePreviewResources,
			serviceEnvironment: home.environment, clientEnvironment: home.environment)
		try host?.prepare()
		print("DEVTOOLS_PRIVATE_CLIENT_SERVICE_HOME configured-before-startup")
	}

	private func serviceExecutable() throws -> URL {
		guard
			let app = host?.app
		else { throw ScenarioFailure.message("service host unavailable; retain fixtures") }
		return app.appendingPathComponent(
			"Contents/XPCServices/DevToolsApplication.xpc/Contents/MacOS/DevToolsApplication")
	}

	private func captureService() throws -> OwnedProcessIdentity {
		let current = try OwnedExecutableProcess.capture(executable: serviceExecutable())
		if let service {
			_ = try Self.reattributeService(service, capture: { current })
		} else {
			service = current
			print(
				"DEVTOOLS_SERVICE_CAPTURED pid=\(current.pid) start=\(current.start) path=\(current.path)")
		}
		return current
	}

	// Defaults preserve identified native Test/Build/Run completion behavior.
	// Tool callers must classify their observed result before confirmation.
	func perform<T>(
		classifyCompletion: (T) throws -> Void = { _ in },
		_ operation: (PackagedXPCHost) throws -> T
	) throws -> T {
		try requests.requireRequestAllowed()
		guard
			let host
		else { throw ScenarioFailure.message("DevTools host unavailable") }
		if service != nil { _ = try captureService() }
		let result = try requests.perform(
			classifyCompletion: classifyCompletion,
			capture: { _ = try self.captureService() },
			{ try operation(host) })
		print("DEVTOOLS_REQUEST_QUIESCENT")
		return result
	}

	func stopServiceRetainingFixtures() throws {
		try requests.stop {
			// First stop must attribute the current host generation before any child/service signal.
			// ESRCH for a stale cached PID alone cannot exclude a live replacement service.
			let attributedService: OwnedProcessIdentity?
			if self.requests.launchAttempted {
				guard
					let cached = self.service
				else { throw ScenarioFailure.message("service identity missing; retain fixtures") }
				attributedService = try Self.reattributeService(
					cached,
					capture: {
						try OwnedExecutableProcess.capture(executable: self.serviceExecutable())
					})
			} else {
				attributedService = nil
			}
			try Self.finish(
				requestConfirmed: self.requests.requestConfirmed,
				childAttempted: self.childAttempted, childKnown: self.child != nil, passed: false,
				child: {
					guard
						let child = self.child
					else { return }
					try child.reap()
					try child.requireReaped()
					print("DEVTOOLS_CHILD_REAPED pid=\(child.pid) start=\(child.start)")
				},
				service: {
					guard
						let service = attributedService
					else { return }
					try service.reap()
					try service.requireReaped()
					print("DEVTOOLS_SERVICE_REAPED pid=\(service.pid) start=\(service.start)")
				}, remove: {})
		}
	}

	func removeProjectAfterServiceStop(_ url: URL) throws {
		guard
			requests.serviceStopped, !requests.stopFailed, let projects
		else { throw ScenarioFailure.message("service stop unconfirmed; retain projects") }
		try projects.remove(url)
	}

	func teardown() throws {
		if teardownComplete { return }
		do {
			try stopServiceRetainingFixtures()
			if passed {
				if let home {
					try home.finishHost(
						cleanupConfirmed: true, removeFixtures: true,
						stopServices: {
							do { try self.service?.requireReaped() } catch {
								self.requests.poisonStop()
								throw error
							}
						},
						removeHost: {
							// Fail-closed project removal must precede irreversible host/home removal.
							try self.projects?.remove()
							try self.host?.remove()
						})
					print("DEVTOOLS_FIXTURES_REMOVED \(home.directory.path)")
				}
				teardownComplete = true
			}
			if !passed {
				print("DEVTOOLS_FIXTURES_RETAINED safely-stopped \(home?.directory.path ?? "unallocated")")
			}
		} catch {
			print(
				"DEVTOOLS_FIXTURES_RETAINED cleanup-unconfirmed \(home?.directory.path ?? "unallocated")")
			throw error
		}
	}

	// Discovery-free comparison seam. Production capture still requires the exact host executable.
	static func reattributeService(
		_ cached: OwnedProcessIdentity, capture: () throws -> OwnedProcessIdentity
	) throws -> OwnedProcessIdentity {
		let current = try capture()
		guard
			current.pid == cached.pid, current.path == cached.path, current.start == cached.start
		else { throw ScenarioFailure.message("unexpected service generation; retain fixtures") }
		return current
	}

	// Pure state seam used by offline tests and the real host path above.
	final class RequestState {
		private(set) var launchAttempted = false
		private(set) var requestConfirmed = true
		private(set) var serviceStopped = false
		private(set) var stopFailed = false

		func requireRequestAllowed() throws {
			guard
				!stopFailed, !serviceStopped, requestConfirmed
			else { throw ScenarioFailure.message("service stopped or request unknown; refuse request") }
		}

		func perform<T>(
			classifyCompletion: (T) throws -> Void = { _ in }, capture: () throws -> Void,
			_ operation: () throws -> T
		) throws -> T {
			try requireRequestAllowed()
			launchAttempted = true
			requestConfirmed = false
			let result = try operation()
			try classifyCompletion(result)
			try capture()
			requestConfirmed = true
			return result
		}

		func poisonStop() {
			stopFailed = true
			requestConfirmed = false
			serviceStopped = false
		}

		func stop(_ stop: () throws -> Void) throws {
			guard
				!stopFailed
			else { throw ScenarioFailure.message("prior stop failed; retain fixtures") }
			if serviceStopped { return }
			do {
				guard
					requestConfirmed
				else { throw ScenarioFailure.message("request quiescence unknown; retain fixtures") }
				try stop()
				serviceStopped = true
			} catch {
				poisonStop()
				throw error
			}
		}
	}

	// Synchronous teardown has no cancellation-sensitive sleeps or inherited task checks.
	static func finish(
		requestConfirmed: Bool, childAttempted: Bool, childKnown: Bool, passed: Bool,
		child: () throws -> Void, service: () throws -> Void, remove: () throws -> Void
	) throws {
		guard
			requestConfirmed
		else { throw ScenarioFailure.message("request quiescence unknown; retain fixtures") }
		guard
			!childAttempted || childKnown
		else { throw ScenarioFailure.message("development identity missing; retain fixtures") }
		if childAttempted { try child() }
		try service()
		if passed { try remove() }
	}

	static func combined(_ body: any Error, _ cleanup: any Error) -> ScenarioFailure {
		.message("body: \(body); teardown: \(cleanup)")
	}
}
