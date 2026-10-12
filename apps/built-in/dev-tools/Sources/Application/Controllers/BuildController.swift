// @frontmatter:start
// Routes scoped builds and owns bounded SwiftPM compilation of generated app products.
// @frontmatter:end
import Foundation

struct SourceBuildResult: Sendable {
	let target: String
	let buildDirectory: URL
	let output: String
}

enum SourceBuildError: Error, Sendable, Equatable {
	case unavailableTool, invalidRequest, outputExceeded
	case failed(Int32, String)
}

/// Builds without staging, signing, registering, or launching an app.
final class BuildController: OpenXPCBuildController, @unchecked Sendable {
	private let projects: ProjectResolver
	private let gate: DevToolsOperationGate
	private let xcrunURL: URL
	private let outputLimitBytes: Int
	private let environment: [String: String]

	init(
		projects: ProjectResolver, gate: DevToolsOperationGate,
		xcrunURL: URL = URL(fileURLWithPath: "/usr/bin/xcrun"),
		outputLimitBytes: Int = 65_536,
		environment: [String: String] = ProcessInfo.processInfo.environment
	) {
		self.projects = projects
		self.gate = gate
		self.xcrunURL = xcrunURL
		self.outputLimitBytes = outputLimitBytes
		self.environment = environment
	}

	func handle(_ projectID: UUID, _ sessionID: UUID, _ request: BuildRequest) async throws
		-> BuildResult
	{
		let project = try await projects.lookup(
			projectRoot: request.projectRoot,
			projectID: projectID.uuidString.lowercased(), sessionID: sessionID.uuidString)
		return try await gate.run {
			let result = try await self.build(
				project: project, requestID: UUID().uuidString.lowercased())
			return try BuildResult(
				summary: "Built \(result.target) for development.", target: result.target)
		}
	}

	func build(project: ResolvedProject, requestID: String) async throws -> SourceBuildResult {
		try await build(
			project: project, requestID: requestID, target: project.manifest.executableTarget)
	}

	func buildPreview(project: ResolvedProject, requestID: String) async throws -> SourceBuildResult {
		try await build(project: project, requestID: requestID, target: project.manifest.previewTarget)
	}

	private func build(project: ResolvedProject, requestID: String, target: String) async throws
		-> SourceBuildResult
	{
		guard
			requestID.utf8.count == 36,
			UUID(uuidString: requestID) != nil,
			outputLimitBytes > 0,
			FileManager.default.isExecutableFile(atPath: xcrunURL.path)
		else { throw SourceBuildError.unavailableTool }

		let buildDirectory = try project.scope.resolve(".mac-apper/Build/\(requestID)")
		try FileManager.default.createDirectory(
			at: buildDirectory, withIntermediateDirectories: true,
			attributes: [.posixPermissions: 0o700])
		_ = try project.scope.resolve(".mac-apper/Build/\(requestID)")

		let output = try await run(
			executable: xcrunURL,
			arguments: [
				"swift", "build", "--product", target, "--configuration",
				"debug", "--scratch-path", buildDirectory.path,
			], directory: project.scope.root)
		return SourceBuildResult(target: target, buildDirectory: buildDirectory, output: output)
	}

	private func run(executable: URL, arguments: [String], directory: URL) async throws -> String {
		try Task.checkCancellation()
		let command = try SwiftToolchain.command(
			executable: executable, arguments: arguments, environment: environment)
		let process: OwnedProcess
		do {
			process = try OwnedProcess(
				executable: command.executable, arguments: command.arguments,
				directory: directory, environment: command.environment, outputLimit: outputLimitBytes,
				gracefulSignal: SIGINT, gracePeriod: .seconds(2))
		} catch { throw SourceBuildError.unavailableTool }
		do {
			let status = try await process.wait(timeout: .seconds(90))
			guard
				status == 0
			else { throw SourceBuildError.failed(status, process.output) }
			return process.output
		} catch OwnedProcess.Failure.outputExceeded {
			throw SourceBuildError.outputExceeded
		}
	}
}
