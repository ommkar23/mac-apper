// @frontmatter:start
// Tests cancellation during reaping and cleanup of escaped child process groups.
// @frontmatter:end
import Darwin
import Foundation
import Testing

@testable import DevToolsApplication

@Test func cancellationDuringReapingDoesNotBecomeSuccess() async throws {
	let process = try OwnedProcess(
		executable: URL(fileURLWithPath: "/usr/bin/true"), arguments: [],
		directory: FileManager.default.temporaryDirectory, environment: [:], outputLimit: 4096,
		gracePeriod: .milliseconds(500))
	while try process.isAlive() { try await Task.sleep(for: .milliseconds(5)) }
	let task = Task { try await process.wait(timeout: .seconds(3)) }
	try await Task.sleep(for: .milliseconds(100))
	task.cancel()
	await #expect(throws: CancellationError.self) { try await task.value }
}

@Test func cleanupOwnsChildrenThatCreateSeparateProcessGroups() async throws {
	let process = try OwnedProcess(
		executable: URL(fileURLWithPath: "/usr/bin/python3"),
		arguments: [
			"-c",
			"""
			import os, signal, time
			child = os.fork()
			if child == 0:
			    os.setpgid(0, 0)
			    signal.signal(signal.SIGTERM, signal.SIG_IGN)
			    signal.signal(signal.SIGINT, signal.SIG_IGN)
			    print(os.getpid(), flush=True)
			while True:
			    time.sleep(1)
			""",
		], directory: FileManager.default.temporaryDirectory, environment: [:], outputLimit: 4096)
	let deadline = ContinuousClock.now.advanced(by: .seconds(5))
	while !process.output.contains("\n"), ContinuousClock.now < deadline {
		_ = try process.isAlive()
		try await Task.sleep(for: .milliseconds(10))
	}
	let child = Int32(process.output.trimmingCharacters(in: .whitespacesAndNewlines))
	try await process.stop()
	let pid = try #require(child)
	defer { if kill(pid, 0) == 0 { kill(pid, SIGKILL) } }
	#expect(kill(pid, 0) == -1)
	#expect(kill(process.processID, 0) == -1)
}
