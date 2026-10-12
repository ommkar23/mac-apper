// @frontmatter:start
// Runs scoped SwiftPM tests with bounded diagnostics and owned processes, removing only newly created request scratch.
// @frontmatter:end
import Foundation

private enum SourceTestError: Error { case invalidRequest, scratchExists }

final class TestController: OpenXPCTestController, @unchecked Sendable {
	private let projects: ProjectResolver
	private let gate: DevToolsOperationGate
	private let xcrunURL: URL
	private let toolchainBin: URL
	private let outputLimitBytes: Int
	private let environment: [String: String]
	private let timeout: Duration

	init(
		projects: ProjectResolver, gate: DevToolsOperationGate,
		xcrunURL: URL = URL(fileURLWithPath: "/usr/bin/xcrun"),
		outputLimitBytes: Int = 65_536,
		environment: [String: String] = ProcessInfo.processInfo.environment,
		timeout: Duration = .seconds(180),
		toolchainBin: URL = SwiftToolchain.bin
	) {
		self.projects = projects
		self.gate = gate
		self.xcrunURL = xcrunURL
		self.toolchainBin = toolchainBin
		self.outputLimitBytes = outputLimitBytes
		self.environment = environment
		self.timeout = timeout
	}

	func handle(_ projectID: UUID, _ sessionID: UUID, _ request: TestRequest) async throws
		-> TestResult
	{
		let project = try await projects.lookup(
			projectRoot: request.projectRoot,
			projectID: projectID.uuidString.lowercased(), sessionID: sessionID.uuidString)
		return try await gate.run {
			try await self.runTests(project: project, requestID: UUID().uuidString.lowercased())
		}
	}

	func runTests(project: ResolvedProject, requestID: String) async throws -> TestResult {
		try Task.checkCancellation()
		guard
			requestID.utf8.count == 36,
			UUID(uuidString: requestID) != nil,
			(1...65_536).contains(outputLimitBytes),
			timeout > .zero && timeout <= .seconds(180)
		else { throw SourceTestError.invalidRequest }
		let relative = ".mac-apper/TestBuild/\(requestID)"
		let scratch = try project.scope.resolve(relative)
		guard
			!FileManager.default.fileExists(atPath: scratch.path)
		else { throw SourceTestError.scratchExists }
		try FileManager.default.createDirectory(
			at: scratch.deletingLastPathComponent(), withIntermediateDirectories: true,
			attributes: [.posixPermissions: 0o700])
		_ = try project.scope.resolve(relative)
		// Do not reuse or remove another operation's existing directory.
		try FileManager.default.createDirectory(
			at: scratch, withIntermediateDirectories: false, attributes: [.posixPermissions: 0o700])
		let result: TestResult
		do {
			_ = try project.scope.resolve(relative)
			result = try await execute(project: project, scratch: scratch)
		} catch {
			try FileManager.default.removeItem(at: project.scope.resolve(relative))
			throw error
		}
		try FileManager.default.removeItem(at: project.scope.resolve(relative))
		return result
	}

	private func execute(project: ResolvedProject, scratch: URL) async throws -> TestResult {
		let process: OwnedProcess
		do {
			let command = try SwiftToolchain.command(
				executable: xcrunURL,
				arguments: ["swift", "test", "--configuration", "debug", "--scratch-path", scratch.path],
				environment: environment, bin: toolchainBin)
			process = try OwnedProcess(
				executable: command.executable, arguments: command.arguments,
				directory: project.scope.root, environment: command.environment,
				outputLimit: outputLimitBytes,
				gracefulSignal: SIGINT, gracePeriod: .seconds(2))
		} catch let error as SwiftToolchain.Failure {
			return try result(status: "error", summary: error.description)
		} catch {
			return try result(
				status: "error", summary: "Could not start swift test. Check the selected Apple toolchain.")
		}
		do {
			let status = try await process.wait(timeout: timeout)
			return try result(
				status: status == 0 ? "passed" : "failed",
				summary: status == 0
					? "swift test passed."
					: "swift test failed (exit \(status)). Fix the diagnostics and rerun.",
				exitCode: Int(status), output: process.output)
		} catch OwnedProcess.Failure.timedOut {
			return try result(
				status: "error",
				summary: "swift test exceeded its execution deadline (180 seconds maximum).",
				output: process.output)
		} catch OwnedProcess.Failure.outputExceeded {
			return try result(
				status: "error",
				summary: "swift test exceeded its output limit; no passing result is claimed.",
				output: process.output, overflow: true)
		}
	}

	private func result(
		status: String, summary: String, exitCode: Int? = nil, output: String = "",
		overflow: Bool = false
	) throws -> TestResult {
		let compact = SwiftToolchain.compactDiagnostics(output)
		let bytes = Data(compact.utf8)
		let tail = bytes.suffix(4_096)
		var start = tail.startIndex
		while start < tail.endIndex && tail[start] & 0xC0 == 0x80 { start += 1 }
		return try TestResult(
			status: status, summary: summary, exitCode: exitCode,
			diagnostics: String(decoding: tail[start...], as: UTF8.self),
			outputTruncated: overflow || compact != output || bytes.count > 4_096)
	}
}
