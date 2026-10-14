// @frontmatter:start
// Runs bounded foreground compiler and persistence helper commands with private retained logs for the offline scaffold scenario.
// @frontmatter:end
import Foundation
import Scenario
import Testing

func scaffoldCommand(
	_ executable: URL, _ arguments: [String], environment: [String: String] = [:],
	timeout: Int, logOutput: Bool = true
) throws -> String {
	let log = try ProjectTemporaryDirectory.appending(
		"mac-apper-coredata-task5-command-\(UUID().uuidString).log")
	try Data().write(to: log, options: .withoutOverwriting)
	let handle = try FileHandle(forWritingTo: log)
	defer { try? handle.close() }
	let process = Process()
	process.executableURL = executable
	process.arguments = arguments
	process.environment = try ProjectTemporaryDirectory.environment(
		ProcessInfo.processInfo.environment.merging(environment) { _, value in value })
	process.standardInput = FileHandle.nullDevice
	process.standardOutput = handle
	process.standardError = handle
	let finished = DispatchSemaphore(value: 0)
	process.terminationHandler = { _ in finished.signal() }
	try process.run()
	let deadline = Date().addingTimeInterval(Double(timeout))
	while finished.wait(timeout: .now() + 0.1) == .timedOut {
		let bytes = try log.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0
		if Date() >= deadline || bytes > 4194304 {
			process.terminate()
			_ = finished.wait(timeout: .now() + 5)
			throw ScenarioFailure.message(
				"Scaffold command time/output limit; retain owned home and log \(log.path)")
		}
	}
	try #require((try log.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? Int.max) <= 4194304)
	let output = try String(contentsOf: log, encoding: .utf8)
	if logOutput {
		print(
			"CORE_DATA_HELPER_COMMAND: \(executable.path) \(arguments.joined(separator: " ")) exit=\(process.terminationStatus) log=\(log.path)\n\(output.suffix(8192))"
		)
	}
	try #require(
		process.terminationStatus == 0,
		"Scaffold command failed; log \(log.path)\n\(output.suffix(8192))")
	return output
}
