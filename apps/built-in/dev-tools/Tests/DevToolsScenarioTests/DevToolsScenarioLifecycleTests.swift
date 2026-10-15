// @frontmatter:start
// Exercises private fixture ownership and fail-closed cleanup ordering without starting XPC services.
// @frontmatter:end
import Foundation
import Scenario
import Testing

@Suite @MainActor struct DevToolsScenarioLifecycleTests {
	@Test func failedStopPoisonsRequestsAndAllRetries() throws {
		for stage in ["attribution", "signaling", "requireReaped"] {
			let state = DevToolsScenarioLifecycle.RequestState()
			try state.perform(capture: {}) {}
			#expect(throws: (any Error).self) {
				try state.stop { throw ScenarioFailure.message(stage) }
			}
			#expect(!state.serviceStopped && !state.requestConfirmed)
			var called = false
			#expect(throws: (any Error).self) {
				try state.perform(capture: {}) { called = true }
			}
			#expect(throws: (any Error).self) { try state.stop { called = true } }
			#expect(!called && !state.serviceStopped)
		}
	}

	@Test func failedLifecycleStopBlocksSelectiveRemovalAfterRetry() throws {
		let lifecycle = DevToolsScenarioLifecycle()
		#expect(throws: (any Error).self) {
			try lifecycle.setup(beforeHost: { throw ScenarioFailure.message("partial setup") })
		}
		let home = try #require(lifecycle.home)
		let projects = try #require(lifecycle.projects)
		let fixture = try projects.create()
		lifecycle.childAttempted = true
		#expect(throws: (any Error).self) { try lifecycle.stopServiceRetainingFixtures() }
		lifecycle.childAttempted = false
		#expect(throws: (any Error).self) { try lifecycle.stopServiceRetainingFixtures() }
		#expect(throws: (any Error).self) { try lifecycle.removeProjectAfterServiceStop(fixture.url) }
		#expect(!lifecycle.serviceStopped)
		#expect(FileManager.default.fileExists(atPath: fixture.url.path))
		// No host or child was started. Remove only these test-owned never-started fixtures.
		try projects.remove()
		try home.remove(cleanupConfirmed: true)
	}

	@Test func firstStopRejectsCachedExitWithReplacementGeneration() throws {
		let cached = OwnedProcessIdentity(pid: 100, start: 200, path: "/owned/DevToolsApplication")
		let replacements = [
			OwnedProcessIdentity(pid: 101, start: 201, path: cached.path),
			OwnedProcessIdentity(pid: 101, start: cached.start, path: cached.path),
			OwnedProcessIdentity(pid: cached.pid, start: 201, path: cached.path),
			OwnedProcessIdentity(
				pid: cached.pid, start: cached.start, path: "/other/DevToolsApplication"),
		]
		for replacement in replacements {
			let state = DevToolsScenarioLifecycle.RequestState()
			try state.perform(capture: {}) {}
			var events: [String] = []
			#expect(throws: (any Error).self) {
				try state.stop {
					_ = try DevToolsScenarioLifecycle.reattributeService(
						cached,
						capture: {
							events.append("attribute-current-exact-host")
							return replacement
						})
					// Cached ESRCH cannot substitute for the current generation attribution.
					events.append("signal-or-cached-ESRCH")
				}
			}
			#expect(events == ["attribute-current-exact-host"])
			#expect(!state.serviceStopped)
		}
	}

	@Test func absentPreStopAttributionPoisonsWithoutSignaling() throws {
		let cached = OwnedProcessIdentity(pid: 100, start: 200, path: "/owned/DevToolsApplication")
		let state = DevToolsScenarioLifecycle.RequestState()
		try state.perform(capture: {}) {}
		var signaled = false
		#expect(throws: (any Error).self) {
			try state.stop {
				_ = try DevToolsScenarioLifecycle.reattributeService(
					cached,
					capture: {
						throw ScenarioFailure.message("current host generation absent")
					})
				signaled = true
			}
		}
		#expect(!signaled && !state.serviceStopped)
		#expect(throws: (any Error).self) { try state.stop { signaled = true } }
		#expect(!signaled)
	}

	@Test func confirmedFirstStopAttributesBeforeReapingAndNeverRediscovers() throws {
		let cached = OwnedProcessIdentity(pid: 100, start: 200, path: "/owned/DevToolsApplication")
		let state = DevToolsScenarioLifecycle.RequestState()
		try state.perform(capture: {}) {}
		var events: [String] = []
		try state.stop {
			_ = try DevToolsScenarioLifecycle.reattributeService(
				cached,
				capture: {
					events.append("attribute")
					return cached
				})
			events.append("reap")
			events.append("requireReaped")
		}
		try state.stop { throw ScenarioFailure.message("must not rediscover or signal") }
		#expect(state.serviceStopped && events == ["attribute", "reap", "requireReaped"])
	}

	@Test func reapingFailuresAfterAttributionPoisonStop() throws {
		let cached = OwnedProcessIdentity(pid: 100, start: 200, path: "/owned/DevToolsApplication")
		for failure in ["signal", "requireReaped"] {
			let state = DevToolsScenarioLifecycle.RequestState()
			try state.perform(capture: {}) {}
			var events: [String] = []
			#expect(throws: (any Error).self) {
				try state.stop {
					_ = try DevToolsScenarioLifecycle.reattributeService(
						cached,
						capture: {
							events.append("attribute")
							return cached
						})
					for stage in ["signal", "requireReaped"] {
						events.append(stage)
						if stage == failure { throw ScenarioFailure.message(stage) }
					}
				}
			}
			#expect(
				events
					== (failure == "signal"
						? ["attribute", "signal"] : ["attribute", "signal", "requireReaped"]))
			#expect(state.stopFailed && !state.serviceStopped)
			#expect(throws: (any Error).self) { try state.stop { events.append("retry") } }
			#expect(!events.contains("retry"))
		}
	}

	@Test func laterReapedConfirmationFailurePoisonsCachedStop() throws {
		let state = DevToolsScenarioLifecycle.RequestState()
		try state.stop {}
		state.poisonStop()
		#expect(!state.serviceStopped && state.stopFailed)
		#expect(throws: (any Error).self) { try state.requireRequestAllowed() }
		#expect(throws: (any Error).self) { try state.stop {} }
	}

	@Test func completionClassificationPrecedesConfirmation() throws {
		let state = DevToolsScenarioLifecycle.RequestState()
		var captured = false
		#expect(throws: (any Error).self) {
			try state.perform(
				classifyCompletion: { (_: Int) in
					throw ScenarioFailure.message("unknown completion")
				}, capture: { captured = true }
			) { 1 }
		}
		#expect(!state.requestConfirmed && !captured)
		#expect(throws: (any Error).self) { try state.stop {} }
		#expect(throws: (any Error).self) { try state.perform(capture: {}) { 2 } }
	}

	@Test func stoppedStateCachesConfirmationAndRefusesRequests() throws {
		let state = DevToolsScenarioLifecycle.RequestState()
		var captures = 0, stops = 0
		let value = try state.perform(capture: { captures += 1 }) { 42 }
		#expect(value == 42 && state.requestConfirmed)
		try state.stop { stops += 1 }
		try state.stop { stops += 1 }
		#expect(state.serviceStopped && stops == 1 && captures == 1)
		#expect(throws: (any Error).self) {
			try state.perform(capture: { captures += 1 }) { 0 }
		}
		#expect(captures == 1)
	}

	@Test func failedStopNeverBecomesStopped() throws {
		let state = DevToolsScenarioLifecycle.RequestState()
		#expect(throws: (any Error).self) {
			try state.stop { throw ScenarioFailure.message("reap failed") }
		}
		#expect(!state.serviceStopped)
	}

	@Test func stoppedFixturesRemainUntilFinalTeardown() throws {
		let lifecycle = DevToolsScenarioLifecycle()
		#expect(throws: (any Error).self) {
			try lifecycle.setup(
				includePreviewResources: true,
				beforeHost: {
					throw ScenarioFailure.message("partial setup")
				})
		}
		let home = try #require(lifecycle.home)
		let projects = try #require(lifecycle.projects)
		let first = try projects.create(), second = try projects.create()
		#expect(throws: (any Error).self) {
			try lifecycle.removeProjectAfterServiceStop(first.url)
		}
		try lifecycle.stopServiceRetainingFixtures()
		try lifecycle.stopServiceRetainingFixtures()
		try lifecycle.removeProjectAfterServiceStop(first.url)
		try lifecycle.removeProjectAfterServiceStop(first.url)
		#expect(FileManager.default.fileExists(atPath: second.url.path))
		#expect(FileManager.default.fileExists(atPath: home.directory.path))
		#expect(throws: (any Error).self) { try lifecycle.perform { _ in 1 } }
		lifecycle.passed = true
		try lifecycle.teardown()
		try lifecycle.teardown()
		#expect(!FileManager.default.fileExists(atPath: home.directory.path))
	}

	@Test func privatePermissionsAndSelectiveMembership() throws {
		let home = try IsolatedScenarioHome()
		let projects = DevToolsScenarioProjects(root: try home.privateDirectory(".mac-apper"))
		let first = try projects.create(), second = try projects.create()
		let attributes = try FileManager.default.attributesOfItem(atPath: first.url.path)
		#expect((attributes[.posixPermissions] as? NSNumber)?.intValue == 0o700)
		#expect(throws: (any Error).self) { try projects.remove(home.directory) }
		try projects.remove(first.url)
		try projects.remove(first.url)
		#expect(FileManager.default.fileExists(atPath: second.url.path))
		try projects.remove()
		try home.remove(cleanupConfirmed: true)
	}

	@Test func disappearedOwnedProjectFailsClosed() throws {
		let home = try IsolatedScenarioHome()
		let projects = DevToolsScenarioProjects(root: try home.privateDirectory(".mac-apper"))
		let fixture = try projects.create()
		try FileManager.default.removeItem(at: fixture.url)
		#expect(throws: (any Error).self) { try projects.remove(fixture.url) }
		#expect(throws: (any Error).self) { try projects.remove() }
		// Restore the exact owned directory so test-only cleanup can complete.
		try FileManager.default.createDirectory(at: fixture.url, withIntermediateDirectories: false)
		try projects.remove()
		try home.remove(cleanupConfirmed: true)
	}

	@Test func explicitPrivateRoot() throws {
		let home = try IsolatedScenarioHome()
		let root = try home.privateDirectory(".mac-apper")
		let projects = DevToolsScenarioProjects(root: root)
		let fixture = try projects.create()
		#expect(fixture.url.deletingLastPathComponent().path == root.path)
		try projects.remove()
		try home.remove(cleanupConfirmed: true)
	}

	@Test func partialProjectWriteRemainsRegistered() throws {
		let home = try IsolatedScenarioHome()
		let root = try home.privateDirectory(".mac-apper")
		let projects = DevToolsScenarioProjects(root: root)
		#expect(throws: (any Error).self) {
			_ = try projects.create(afterDirectory: { _ in
				throw ScenarioFailure.message("partial write")
			})
		}
		#expect(try FileManager.default.contentsOfDirectory(atPath: root.path).count == 1)
		try projects.remove()
		#expect(try FileManager.default.contentsOfDirectory(atPath: root.path).isEmpty)
		try home.remove(cleanupConfirmed: true)
	}

	@Test func partialSetupStillOwnsHome() throws {
		let lifecycle = DevToolsScenarioLifecycle()
		#expect(throws: (any Error).self) {
			try lifecycle.setup(beforeHost: { throw ScenarioFailure.message("setup failed") })
		}
		let directory = try #require(lifecycle.home?.directory)
		#expect(FileManager.default.fileExists(atPath: directory.path))
		try lifecycle.teardown()
		#expect(FileManager.default.fileExists(atPath: directory.path))
		try lifecycle.home?.remove(cleanupConfirmed: true)
	}

	@Test func childServiceRemovalOrder() throws {
		var events: [String] = []
		try DevToolsScenarioLifecycle.finish(
			requestConfirmed: true, childAttempted: true, childKnown: true, passed: true,
			child: { events.append("child") }, service: { events.append("service") },
			remove: { events.append("host-project-home") })
		#expect(events == ["child", "service", "host-project-home"])
	}

	@Test func unknownRequestAndMissingChildRetain() {
		for (request, known) in [(false, true), (true, false)] {
			var events: [String] = []
			#expect(throws: (any Error).self) {
				try DevToolsScenarioLifecycle.finish(
					requestConfirmed: request, childAttempted: true, childKnown: known, passed: true,
					child: { events.append("child") }, service: { events.append("service") },
					remove: { events.append("remove") })
			}
			#expect(events.isEmpty)
		}
	}

	@Test func failedReapingAndRemovalPropagate() {
		for stage in ["child", "service", "remove"] {
			var events: [String] = []
			func event(_ value: String) throws {
				events.append(value)
				if stage == value { throw ScenarioFailure.message(value) }
			}
			#expect(throws: (any Error).self) {
				try DevToolsScenarioLifecycle.finish(
					requestConfirmed: true, childAttempted: true, childKnown: true, passed: true,
					child: { try event("child") }, service: { try event("service") },
					remove: { try event("remove") })
			}
			#expect(events.last == stage)
		}
	}

	@Test func failedAssertionStopsButRetains() throws {
		var events: [String] = []
		try DevToolsScenarioLifecycle.finish(
			requestConfirmed: true, childAttempted: true, childKnown: true, passed: false,
			child: { events.append("child") }, service: { events.append("service") },
			remove: { events.append("remove") })
		#expect(events == ["child", "service"])
	}

	@Test func missingServiceIdentityRetains() {
		var removed = false
		#expect(throws: (any Error).self) {
			try DevToolsScenarioLifecycle.finish(
				requestConfirmed: true, childAttempted: false, childKnown: false, passed: true,
				child: {}, service: { throw ScenarioFailure.message("missing service identity") },
				remove: { removed = true })
		}
		#expect(!removed)
	}

	@Test func bodyAndCleanupErrorsAggregate() {
		let result = DevToolsScenarioLifecycle.combined(
			ScenarioFailure.message("body"), ScenarioFailure.message("cleanup"))
		#expect(String(describing: result).contains("body"))
		#expect(String(describing: result).contains("cleanup"))
	}

	@Test func cancelledBodyStillTearsDown() async throws {
		let task = Task { @MainActor in
			withUnsafeCurrentTask { $0?.cancel() }
			var stopped = false
			try DevToolsScenarioLifecycle.finish(
				requestConfirmed: true, childAttempted: false, childKnown: false, passed: false,
				child: {}, service: { stopped = true }, remove: {})
			return stopped
		}
		#expect(try await task.value)
	}
}
