// @frontmatter:start
// Builds and runs independent counter assertions with bounded compiler commands and private scratch.
// @frontmatter:end
import Darwin
import Foundation
import Scenario

func counterBehaviorSource(_ count: String) -> String {
	"""
	import Testing
	import AppModel
	@Test @MainActor func scenarioCounterBehavior() {
	    let model = ApplicationModel()
	    #expect(\(count) == 0)
	    model.increment(); model.increment(); #expect(\(count) == 2)
	    model.decrement(); #expect(\(count) == 1)
	    model.reset(); #expect(\(count) == 0)
	    model.decrement(); #expect(\(count) == -1)
	    model.reset(); #expect(\(count) == 0)
	}
	"""
}

func counterCountExpression(project: URL, scratch: URL, compiler: SDKCompiler? = nil) throws
	-> String
{
	let compiler = try compiler ?? SDKCompiler.resolve()
	let swift = try SwiftToolchain.executable("swift")
	let arguments = [
		"build", "--package-path", project.path, "--scratch-path", scratch.path, "-j", "2",
	]
	let build = try counterCommand(swift, arguments + ["--target", "AppModel"])
	guard
		build.status == 0
	else {
		throw ScenarioFailure.message(
			"Independent counter AppModel build failed; see CREATE_COUNTER_COMMAND log")
	}
	let location = try counterCommand(swift, arguments + ["--show-bin-path"], timeout: 15)
	guard
		location.status == 0,
		let path = location.output.split(separator: "\n").last,
		path.hasPrefix("/"),
		FileManager.default.fileExists(atPath: String(path))
	else { throw ScenarioFailure.message("Independent counter module location unavailable") }
	try compiler.requireImport(
		module: "AppModel", searchPath: URL(fileURLWithPath: String(path)), scratch: scratch)
	// Ask the compiler about the actual exported model API, never scan comments/strings or rewrite app source.
	// Exactly one signed-integer presentation layout is supported; dual APIs are ambiguous, not guessed.
	let probe = scratch.appendingPathComponent("CounterPresentationProbe.swift")
	defer { try? FileManager.default.removeItem(at: probe) }
	var supported: [String] = []
	for expression in ["model.count", "model.state.count"] {
		try """
		import AppModel
		@MainActor func counterPresentationProbe(_ model: ApplicationModel) {
		    func signedCount<T: SignedInteger>(_ value: T) {}
		    signedCount(\(expression))
		}
		""".write(to: probe, atomically: true, encoding: .utf8)
		let result = try compiler.run(["-typecheck", "-I", String(path), probe.path], scratch: scratch)
		if result.status == 0 {
			supported.append(expression)
		} else if !result.output.contains("has no member")
			&& !(result.output.contains("requires that") && result.output.contains("SignedInteger"))
		{
			throw ScenarioFailure.message(
				"Counter compiler probe failed, not an unsupported API: \(result.output.suffix(4096))")
		}
	}
	guard
		supported.count == 1,
		let expression = supported.first
	else {
		throw ScenarioFailure.message(
			"Unsupported or ambiguous counter presentation API: require exactly one signed-integer model.count or model.state.count; supported=\(supported)"
		)
	}
	print("CREATE_COUNTER_PRESENTATION: \(expression) (compiler-checked)")
	return expression
}

func verifyIndependentCounter(project: URL, compiler: SDKCompiler) throws {
	let manager = FileManager.default
	let scratch = try ProjectTemporaryDirectory.appending(
		"mac-apper-counter-build-\(UUID().uuidString)")
	try manager.createDirectory(
		at: scratch, withIntermediateDirectories: false, attributes: [.posixPermissions: 0o700])
	defer { try? manager.removeItem(at: scratch) }
	let expression = try counterCountExpression(
		project: project, scratch: scratch, compiler: compiler)
	let check = project.appendingPathComponent("Tests/AppModelTests/ScenarioCounterTests.swift")
	guard
		!manager.fileExists(atPath: check.path)
	else {
		throw ScenarioFailure.message(
			"Independent counter test path already exists; refusing overwrite")
	}
	try counterBehaviorSource(expression).write(to: check, atomically: true, encoding: .utf8)
	defer { try? manager.removeItem(at: check) }
	let result = try counterCommand(
		try SwiftToolchain.executable("swift"),
		[
			"test", "--package-path", project.path, "--scratch-path", scratch.path, "-j", "2",
		])
	guard
		result.status == 0 && result.output.contains("Test scenarioCounterBehavior() passed")
	else {
		throw ScenarioFailure.message(
			"Independent counter assertions did not compile, execute and pass; see CREATE_COUNTER_COMMAND log"
		)
	}
}

struct CounterCommandResult {
	let status: Int32
	let output: String
}

func counterCommand(_ executable: URL, _ arguments: [String], timeout: Int = 180) throws
	-> CounterCommandResult
{
	let log = try ProjectTemporaryDirectory.appending(
		"mac-apper-counter-command-\(UUID().uuidString).log")
	try Data().write(to: log, options: .withoutOverwriting)
	let handle = try FileHandle(forWritingTo: log)
	defer { try? handle.close() }
	let process = Process()
	process.executableURL = executable
	process.arguments = arguments
	var environment = ProcessInfo.processInfo.environment
	if executable.lastPathComponent == "swift" {
		environment["SWIFT_EXEC"] =
			executable.deletingLastPathComponent().appendingPathComponent("swiftc").path
	}
	process.environment = environment
	process.standardInput = FileHandle.nullDevice
	process.standardOutput = handle
	process.standardError = handle
	try process.run()
	defer {
		if process.isRunning {
			process.terminate()
			let deadline = Date().addingTimeInterval(2)
			while process.isRunning && Date() < deadline { Thread.sleep(forTimeInterval: 0.01) }
			if process.isRunning { _ = kill(process.processIdentifier, SIGKILL) }
		}
		process.waitUntilExit()
	}
	let deadline = Date().addingTimeInterval(Double(timeout))
	while process.isRunning {
		try Task.checkCancellation()
		let size = try log.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? Int.max
		guard
			Date() < deadline && size <= 4_194_304
		else {
			throw ScenarioFailure.message("Counter command time/output bound exceeded; log \(log.path)")
		}
		Thread.sleep(forTimeInterval: 0.05)
	}
	process.waitUntilExit()
	guard
		(try log.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? Int.max) <= 4_194_304
	else { throw ScenarioFailure.message("Oversized counter command output; log \(log.path)") }
	let output = try String(contentsOf: log, encoding: .utf8)
	print(
		"CREATE_COUNTER_COMMAND: exit=\(process.terminationStatus) log=\(log.path)\n\(output.suffix(4096))"
	)
	return CounterCommandResult(status: process.terminationStatus, output: output)
}
