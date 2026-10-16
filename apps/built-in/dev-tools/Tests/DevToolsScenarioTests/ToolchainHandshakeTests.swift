// @frontmatter:start
// Exercises the Build/Run acquisition helper with controlled readiness, scheduling and exact-owned local child identity.
// @frontmatter:end
import Darwin
import Foundation
import Scenario
import Testing

@Suite @MainActor struct ToolchainHandshakeTests {
	private func fixture() throws -> URL {
		let root = try ProjectTemporaryDirectory.appending("toolchain-handshake-\(UUID().uuidString)")
		try FileManager.default.createDirectory(
			at: root, withIntermediateDirectories: false, attributes: [.posixPermissions: 0o700])
		return root
	}

	@Test func acquisitionPrecedesQueuedMainActorWork() async throws {
		let root = try fixture()
		defer { try? FileManager.default.removeItem(at: root) }
		let lifecycle = DevToolsScenarioLifecycle()
		let binary = root.appendingPathComponent("exact-binary")
		let identity = OwnedProcessIdentity(pid: 123, start: 456, path: binary.path)
		var now: TimeInterval = 0
		var events: [String] = []
		var competitor: Task<Void, Never>?
		var operations = ToolchainScenarioHandshake.Operations()
		operations.now = { now }
		var polls = 0
		operations.ready = { marker in
			#expect(marker == root.appendingPathComponent("run-pid"))
			polls += 1
			return polls == 2
		}
		operations.wait = { interval in
			#expect(interval == 0.02)
			now += interval
			try "123".write(to: root.appendingPathComponent("run-pid"), atomically: true, encoding: .utf8)
			competitor = Task { @MainActor in
				events.append("competing-actor-work")
				now += 61  // Independent child lease expires while unrelated actor work runs.
			}
		}
		// The queued actor job cannot run until this synchronous acquisition returns.
		operations.capture = { executable in
			#expect(executable == binary)
			guard
				now < 60
			else { throw ScenarioFailure.message("controlled child lease expired") }
			events.append("capture")
			return identity
		}
		operations.release = { release in
			#expect(lifecycle.child?.pid == identity.pid)
			#expect(lifecycle.child?.start == identity.start)
			#expect(lifecycle.child?.path == binary.path)
			#expect(release == root.appendingPathComponent("run-release"))
			events.append("release-after-cache-and-corroboration")
		}
		let child = try ToolchainScenarioHandshake.acquire(
			binary: binary, root: root, lifecycle: lifecycle, using: operations)
		#expect(child.pid == identity.pid)
		await competitor?.value
		#expect(events == ["capture", "release-after-cache-and-corroboration", "competing-actor-work"])
	}

	@Test func readinessHasOriginalTenSecondBound() throws {
		let root = try fixture()
		defer { try? FileManager.default.removeItem(at: root) }
		let lifecycle = DevToolsScenarioLifecycle()
		var now: TimeInterval = 0
		var waits = 0
		var discovered = false
		var released = false
		var operations = ToolchainScenarioHandshake.Operations()
		operations.now = { now }
		operations.ready = { _ in false }
		operations.wait = { interval in
			now += interval; waits += 1
		}
		operations.capture = { _ in
			discovered = true
			throw ScenarioFailure.message("unexpected discovery")
		}
		operations.release = { _ in released = true }
		do {
			_ = try ToolchainScenarioHandshake.acquire(
				binary: root, root: root, lifecycle: lifecycle, using: operations)
			Issue.record("missing marker accepted")
		} catch {}
		#expect(now >= 10 && now < 10.021)
		#expect(waits >= 500 && waits <= 501)
		#expect(!discovered && !released && lifecycle.child == nil)
	}

	@Test func linkedOversizeAndMalformedMarkersNeverDiscoverOrRelease() throws {
		for kind in ["linked", "oversize", "malformed"] {
			let root = try fixture()
			defer { try? FileManager.default.removeItem(at: root) }
			let marker = root.appendingPathComponent("run-pid")
			if kind == "linked" {
				let target = root.appendingPathComponent("target")
				try "123".write(to: target, atomically: true, encoding: .utf8)
				try FileManager.default.createSymbolicLink(at: marker, withDestinationURL: target)
			} else {
				try (kind == "oversize" ? String(repeating: "1", count: 65) : "not-a-pid")
					.write(to: marker, atomically: true, encoding: .utf8)
			}
			let lifecycle = DevToolsScenarioLifecycle()
			var discovered = false
			var released = false
			var operations = ToolchainScenarioHandshake.Operations()
			operations.capture = { _ in
				discovered = true
				throw ScenarioFailure.message("unexpected discovery")
			}
			operations.release = { _ in released = true }
			do {
				_ = try ToolchainScenarioHandshake.acquire(
					binary: root, root: root, lifecycle: lifecycle, using: operations)
				Issue.record("invalid marker accepted: \(kind)")
			} catch {}
			#expect(!discovered && !released && lifecycle.child == nil)
		}
	}

	@Test func mismatchCachesExactIdentityAndCaptureFailureNeverReleases() throws {
		for captureFails in [false, true] {
			let root = try fixture()
			defer { try? FileManager.default.removeItem(at: root) }
			try "999".write(to: root.appendingPathComponent("run-pid"), atomically: true, encoding: .utf8)
			let lifecycle = DevToolsScenarioLifecycle()
			let binary = root.appendingPathComponent("exact-binary")
			let identity = OwnedProcessIdentity(pid: 123, start: 456, path: binary.path)
			var released = false
			var operations = ToolchainScenarioHandshake.Operations()
			operations.capture = { executable in
				#expect(executable == binary)
				if captureFails { throw ScenarioFailure.message("controlled capture failure") }
				return identity
			}
			operations.release = { _ in released = true }
			do {
				_ = try ToolchainScenarioHandshake.acquire(
					binary: binary, root: root, lifecycle: lifecycle, using: operations)
				Issue.record("mismatched or unavailable identity accepted")
			} catch {}
			#expect(!released)
			if captureFails {
				#expect(lifecycle.child == nil)
			} else {
				#expect(lifecycle.child?.pid == identity.pid)
				#expect(lifecycle.child?.start == identity.start)
				#expect(lifecycle.child?.path == identity.path)
			}
		}
	}

	@Test func releaseFailureStillLeavesCachedIdentity() throws {
		let root = try fixture()
		defer { try? FileManager.default.removeItem(at: root) }
		try "123".write(to: root.appendingPathComponent("run-pid"), atomically: true, encoding: .utf8)
		let lifecycle = DevToolsScenarioLifecycle()
		let identity = OwnedProcessIdentity(pid: 123, start: 456, path: root.path)
		var operations = ToolchainScenarioHandshake.Operations()
		operations.capture = { _ in identity }
		operations.release = { _ in throw ScenarioFailure.message("controlled release failure") }
		#expect(throws: (any Error).self) {
			try ToolchainScenarioHandshake.acquire(
				binary: root, root: root, lifecycle: lifecycle, using: operations)
		}
		#expect(lifecycle.child?.pid == identity.pid)
		#expect(lifecycle.child?.start == identity.start)
		#expect(lifecycle.child?.path == identity.path)
	}

	private func requireExit(_ finished: DispatchSemaphore) throws {
		try #require(finished.wait(timeout: .now() + 5) == .success)
	}

	@Test func realLocalExactExecutableIdentityAndESRCH() throws {
		let root = try fixture()
		let binary = root.appendingPathComponent("owned-sleep")
		try FileManager.default.copyItem(at: URL(fileURLWithPath: "/bin/sleep"), to: binary)
		let process = Process()
		process.executableURL = binary
		process.arguments = ["2"]
		process.environment = try ProjectTemporaryDirectory.environment()
		process.standardOutput = FileHandle.nullDevice
		process.standardError = FileHandle.nullDevice
		let finished = DispatchSemaphore(value: 0)
		process.terminationHandler = { _ in finished.signal() }
		try process.run()
		// The selected XPC case verifies child-written markers. Here the direct Process owns the PID.
		try String(process.processIdentifier).write(
			to: root.appendingPathComponent("run-pid"), atomically: true, encoding: .utf8)
		let lifecycle = DevToolsScenarioLifecycle()
		let child = try ToolchainScenarioHandshake.acquire(
			binary: binary, root: root, lifecycle: lifecycle)
		let corroborated = try OwnedProcessIdentity.capture(process.processIdentifier)
		#expect(child.pid == corroborated.pid && child.start == corroborated.start)
		#expect(child.path == corroborated.path && child.path == binary.path)
		#expect(lifecycle.child?.start == child.start)
		#expect(
			try String(contentsOf: root.appendingPathComponent("run-release"), encoding: .utf8)
				== "release")
		try requireExit(finished)
		try child.requireReaped()
		print("TOOLCHAIN_LOCAL_CHILD_ESRCH pid=\(child.pid) start=\(child.start) path=\(child.path)")
		try FileManager.default.removeItem(at: root)
	}
}
