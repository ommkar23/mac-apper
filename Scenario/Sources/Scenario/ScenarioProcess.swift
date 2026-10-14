// @frontmatter:start
// Executes bounded signing and verification commands for disposable scenario hosts.
// @frontmatter:end
import Foundation

enum ScenarioProcess {
	static func run(_ path: String, _ arguments: [String]) throws {
		let process = Process()
		process.executableURL = URL(fileURLWithPath: path)
		process.arguments = arguments
		process.environment = try ProjectTemporaryDirectory.environment()
		process.standardOutput = FileHandle.nullDevice
		process.standardError = FileHandle.nullDevice
		let finished = DispatchSemaphore(value: 0)
		process.terminationHandler = { _ in finished.signal() }
		try process.run()
		if finished.wait(timeout: .now() + 30) == .timedOut {
			process.terminate()
			_ = finished.wait(timeout: .now() + 5)
			throw ScenarioFailure.message("scenario host signing timed out")
		}
		guard
			process.terminationStatus == 0
		else { throw ScenarioFailure.message("scenario host signing or verification failed") }
	}
}
