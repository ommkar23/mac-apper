// @frontmatter:start
// Orders Chat teardown, retains failed hosts, and reaps only captured kernel-path/PID/start identities before file removal.
// @frontmatter:end
import Darwin
import Foundation
import Scenario

@MainActor enum ChatScenarioCleanup {
	enum Failure: Error { case retainedHost, identityMismatch, notReaped }
	static let confirmation = "CHAT_SESSION_CLEANUP: all owned Pi reaped before file cleanup"

	static func removeSession(
		stop: () async throws -> Void, reap: () throws -> Void, remove: () throws -> Void
	) async throws {
		try await stop()
		try reap()
		try remove()
	}

	static func finishHost(
		cleanupConfirmed: Bool, passed: Bool, stop: () throws -> Void, remove: () throws -> Void
	) throws {
		guard
			cleanupConfirmed
		else { throw Failure.retainedHost }
		try stop()
		guard
			passed
		else { throw Failure.retainedHost }
		try remove()
	}
}

struct ChatOwnedPiIdentity {
	let pid: Int32
	let start: UInt64
	let path: String

	static func capture(_ pid: Int32) throws -> Self {
		guard
			let path = scaffoldProcessPath(pid),
			let start = scaffoldProcessStart(pid)
		else { throw ChatScenarioCleanup.Failure.identityMismatch }
		let identity = Self(pid: pid, start: start, path: path)
		try identity.validate()
		print("CHAT_PI_IDENTITY: pid=\(pid) start=\(start) path=\(path)")
		return identity
	}

	private func validate() throws {
		guard
			scaffoldProcessPath(pid) == path,
			scaffoldProcessStart(pid) == start
		else { throw ChatScenarioCleanup.Failure.identityMismatch }
	}

	func requireReaped() throws {
		guard
			kill(pid, 0) != 0 && errno == ESRCH
		else { throw ChatScenarioCleanup.Failure.notReaped }
	}

	func reap() throws {
		if kill(pid, 0) != 0 {
			try requireReaped()
			print("CHAT_PI_CLEANUP: pid=\(pid) start=\(start) path=\(path) already reaped")
			return
		}
		try validate()
		guard
			kill(pid, SIGTERM) == 0
		else { throw ChatScenarioCleanup.Failure.notReaped }
		let graceful = Date().addingTimeInterval(2)
		while kill(pid, 0) == 0 && Date() < graceful { Thread.sleep(forTimeInterval: 0.05) }
		if kill(pid, 0) == 0 {
			try validate()
			guard
				kill(pid, SIGKILL) == 0
			else { throw ChatScenarioCleanup.Failure.notReaped }
			print("CHAT_PI_ESCALATION: pid=\(pid) start=\(start) SIGKILL after TERM")
		}
		let deadline = Date().addingTimeInterval(10)
		while kill(pid, 0) == 0 && Date() < deadline { Thread.sleep(forTimeInterval: 0.05) }
		try requireReaped()
		print("CHAT_PI_CLEANUP: pid=\(pid) start=\(start) path=\(path) reaped")
	}
}
