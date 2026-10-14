// @frontmatter:start
// Tests bounded child output, timeouts, cleanup, and process ownership.
// @frontmatter:end
import Darwin
import Foundation
import Scenario
import Testing

@testable import DevToolsApplication

private func owned(_ script: String, limit: Int = 4096) throws -> OwnedProcess {
	try OwnedProcess(
		executable: URL(fileURLWithPath: "/bin/sh"), arguments: ["-c", script],
		directory: try ProjectTemporaryDirectory.root(), environment: [:], outputLimit: limit)
}

@Test func processOutputIsBoundedAndOverflowIsNotSuccess() async throws {
	let process = try owned(
		"while :; do printf '1234567890123456789012345678901234567890'; done", limit: 128)
	await #expect(throws: OwnedProcess.Failure.outputExceeded) {
		try await process.wait(timeout: .seconds(5))
	}
	#expect(process.output.utf8.count == 128)
	#expect(kill(process.processID, 0) == -1)
	try await process.stop()
}

@Test func processTimeoutEscalatesAndStopIsIdempotent() async throws {
	let process = try owned("trap '' TERM; while :; do :; done")
	await #expect(throws: OwnedProcess.Failure.timedOut) {
		try await process.wait(timeout: .milliseconds(100))
	}
	#expect(kill(process.processID, 0) == -1)
	try await process.stop()
	try await process.stop()
}

@Test func normalLeaderExitStillCleansResistantDescendants() async throws {
	let process = try owned(
		"/bin/sh -c 'trap \"\" TERM; while :; do /bin/sleep 1; done' & printf '%s' \"$!\"; exit 0")
	#expect(try await process.wait(timeout: .seconds(5)) == 0)
	let child = try #require(Int32(process.output))
	#expect(kill(child, 0) == -1)
}

@Test func shortProcessesKeepExitStatusAndFinalOutput() async throws {
	for _ in 0..<12 {
		let process = try owned("printf final-output; exit 7")
		#expect(try await process.wait(timeout: .seconds(5)) == 7)
		#expect(process.output == "final-output")
	}
}

@Test func ownedCleanupDoesNotSignalUnrelatedProcess() async throws {
	let unrelated = try owned("while :; do /bin/sleep 1; done")
	let target = try owned("while :; do /bin/sleep 1; done")
	try await target.stop()
	let survived = try unrelated.isAlive()
	try await unrelated.stop()
	#expect(survived)
}
