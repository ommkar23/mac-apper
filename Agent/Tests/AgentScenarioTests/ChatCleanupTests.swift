// @frontmatter:start
// Tests Chat cleanup ordering, failed-host retention, exact Pi reaping, and unrelated-process preservation without live calls.
// @frontmatter:end
import Darwin
import Foundation
import Testing

private enum ChatCleanupTestError: Error { case expected }

@Test @MainActor func chatCleanupOrderingOffline() async throws {
	var events: [String] = []
	try await ChatScenarioCleanup.removeSession(
		stop: { events.append("stop") }, reap: { events.append("reap") },
		remove: { events.append("remove") })
	#expect(events == ["stop", "reap", "remove"])
	for failing in ["stop", "reap"] {
		events = []
		do {
			try await ChatScenarioCleanup.removeSession(
				stop: {
					events.append("stop")
					if failing == "stop" { throw ChatCleanupTestError.expected }
				},
				reap: {
					events.append("reap"); throw ChatCleanupTestError.expected
				},
				remove: { events.append("remove") })
			Issue.record("Cleanup failure was swallowed")
		} catch ChatCleanupTestError.expected {}
		#expect(events == (failing == "stop" ? ["stop"] : ["stop", "reap"]))
	}
}

@Test @MainActor func chatCleanupRetainsFailedHostOffline() throws {
	var events: [String] = []
	try ChatScenarioCleanup.finishHost(
		cleanupConfirmed: true, passed: true,
		stop: { events.append("stop") }, remove: { events.append("remove") })
	#expect(events == ["stop", "remove"])
	for confirmed in [false, true] {
		events = []
		do {
			try ChatScenarioCleanup.finishHost(
				cleanupConfirmed: confirmed, passed: false,
				stop: { events.append("stop") }, remove: { events.append("remove") })
			Issue.record("Failed host was accepted")
		} catch is ChatScenarioCleanup.Failure {}
		#expect(events == (confirmed ? ["stop"] : []))
	}
	events = []
	do {
		try ChatScenarioCleanup.finishHost(
			cleanupConfirmed: true, passed: true,
			stop: {
				events.append("stop"); throw ChatCleanupTestError.expected
			},
			remove: { events.append("remove") })
		Issue.record("Service cleanup failure was swallowed")
	} catch ChatCleanupTestError.expected {}
	#expect(events == ["stop"])
}

@Test @MainActor func chatCleanupReapsOnlyExactOwnedPiOffline() throws {
	func child() throws -> Process {
		let process = Process()
		process.executableURL = URL(fileURLWithPath: "/bin/sleep")
		process.arguments = ["60"]
		try process.run()
		return process
	}
	let owned = try child(), unrelated = try child()
	defer {
		for process in [owned, unrelated] where process.isRunning {
			process.terminate(); process.waitUntilExit()
		}
	}
	let identity = try ChatOwnedPiIdentity.capture(owned.processIdentifier)
	let wrong = ChatOwnedPiIdentity(
		pid: identity.pid, start: identity.start + 1, path: identity.path)
	do {
		try wrong.reap()
		Issue.record("Mismatched identity was signalled")
	} catch is ChatScenarioCleanup.Failure {}
	#expect(owned.isRunning && unrelated.isRunning)
	try identity.reap()
	owned.waitUntilExit()
	#expect(kill(identity.pid, 0) != 0 && errno == ESRCH)
	#expect(unrelated.isRunning)
	try identity.reap()
	print("CHAT_CLEANUP_OFFLINE: exact owned identity reaped; unrelated same-binary child preserved")
}
