// @frontmatter:start
// Audits passing DevTools Test results and agent-authored Swift Testing counter assertions using bounded compiler parse output.
// @frontmatter:end
import Darwin
import Foundation
import Scenario
import Testing

func verifyCounterTesting(session: URL, project: URL) async throws {
	let evidence = try ScenarioToolEvidence(session: session)
	let candidates = try evidence.testedSourcePaths(project: project)
	try #require(
		!candidates.isEmpty,
		"Missing latest agent-authored test source revision followed by matched status passed / exitCode 0"
	)
	var fields: Set<String> = []
	var verifiedFiles: [String] = []
	for relative in candidates {
		var file = project
		for component in relative.split(separator: "/") {
			file.appendPathComponent(String(component))
			try #require(try file.resourceValues(forKeys: [.isSymbolicLinkKey]).isSymbolicLink != true)
		}
		_ = try boundedCounterEvidence(file, maximum: 65_536)
		let parsed = try await counterTestParse(file)
		let lines = parsed.components(separatedBy: "\n")
		guard
			lines.contains(where: {
				$0.trimmingCharacters(in: .whitespaces).hasPrefix("(import_decl")
					&& $0.contains("module=\"Testing\"")
			})
		else { continue }
		var fileFields: Set<String> = []
		for (index, line) in lines.enumerated()
		where line.trimmingCharacters(in: .whitespaces).hasPrefix("(func_decl") {
			let indent = line.prefix(while: { $0 == " " }).count
			let body = lines.dropFirst(index + 1).prefix {
				$0.isEmpty || $0.prefix(while: { $0 == " " }).count > indent
			}.map { $0.trimmingCharacters(in: .whitespaces) }
			guard
				body.contains(where: { $0.hasPrefix("(type_unqualified_ident id=\"Test\"") }),
				body.contains(where: {
					$0.hasPrefix("(macro_expansion_expr") && $0.contains("name=\"expect\"")
				})
			else { continue }
			for field in ["count", "increment", "decrement", "reset"] {
				if body.contains(where: {
					$0.hasPrefix("(unresolved_dot_expr") && $0.contains("field=\"\(field)\"")
				}) {
					fileFields.insert(field)
				}
			}
		}
		if !fileFields.isEmpty {
			fields.formUnion(fileFields)
			verifiedFiles.append(relative)
		}
	}
	try #require(
		fields.isSuperset(of: ["count", "increment", "decrement", "reset"]),
		"Agent-authored @Test functions with #expect must exercise count, increment, decrement, and reset"
	)
	print(
		"CREATE_SWIFT_TESTING: passing test tool; authored counter checks in \(verifiedFiles.joined(separator: ", "))"
	)
	// This is structural authorship evidence, not proof of exhaustive coverage. Independent assertions run separately.
}

private func boundedCounterEvidence(_ file: URL, maximum: Int) throws -> Data {
	let values = try file.resourceValues(forKeys: [
		.isRegularFileKey, .isSymbolicLinkKey, .fileSizeKey,
	])
	try #require(values.isRegularFile == true && values.isSymbolicLink != true)
	try #require((values.fileSize ?? Int.max) <= maximum)
	let handle = try FileHandle(forReadingFrom: file)
	defer { try? handle.close() }
	let data = try handle.read(upToCount: maximum + 1) ?? Data()
	try #require(data.count <= maximum)
	return data
}

private func counterTestParse(_ source: URL) async throws -> String {
	let directory = try ProjectTemporaryDirectory.root().appendingPathComponent(
		"mac-apper-counter-parse-\(UUID().uuidString)")
	try FileManager.default.createDirectory(
		at: directory, withIntermediateDirectories: false, attributes: [.posixPermissions: 0o700])
	defer { try? FileManager.default.removeItem(at: directory) }
	let output = directory.appendingPathComponent("parse")
	try Data().write(to: output, options: .withoutOverwriting)
	let handle = try FileHandle(forWritingTo: output)
	defer { try? handle.close() }
	let process = Process()
	process.executableURL = try SwiftToolchain.executable("swiftc")
	process.arguments = ["-frontend", "-dump-parse", source.path]
	process.standardInput = FileHandle.nullDevice
	process.standardOutput = handle
	process.standardError = handle
	try process.run()
	defer { stopCounterParser(process) }
	let deadline = ContinuousClock.now.advanced(by: .seconds(15))
	while process.isRunning {
		try Task.checkCancellation()
		try #require(ContinuousClock.now < deadline, "Counter test parsing timed out")
		let values = try output.resourceValues(forKeys: [.fileSizeKey])
		try #require(
			(values.fileSize ?? Int.max) <= 1_048_576, "Counter parse output exceeded its bound")
		try await Task.sleep(for: .milliseconds(10))
	}
	try #require(process.terminationStatus == 0, "Counter test source could not be parsed")
	return String(decoding: try boundedCounterEvidence(output, maximum: 1_048_576), as: UTF8.self)
}

private func stopCounterParser(_ process: Process) {
	if process.isRunning {
		process.terminate()
		let deadline = Date().addingTimeInterval(2)
		while process.isRunning && Date() < deadline { Thread.sleep(forTimeInterval: 0.01) }
		if process.isRunning { kill(process.processIdentifier, SIGKILL) }
	}
	process.waitUntilExit()
}
