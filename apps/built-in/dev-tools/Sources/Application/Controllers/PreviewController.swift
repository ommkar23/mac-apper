// @frontmatter:start
// Validates scoped preview requests and returns rendered artifacts or explicit rendering diagnostics.
// @frontmatter:end
import Foundation

struct PreviewController: OpenXPCPreviewController {
	enum Failure: Error { case invalidPath }
	private let projects: ProjectResolver
	private let gate: DevToolsOperationGate
	private let rendering: PreviewRendering

	init(
		projects: ProjectResolver, gate: DevToolsOperationGate,
		xcrunURL: URL = URL(fileURLWithPath: "/usr/bin/xcrun"),
		environment: [String: String] = ProcessInfo.processInfo.environment,
		processRunner: PreviewRendering.ProcessRunner? = nil
	) {
		self.projects = projects
		self.gate = gate
		self.rendering = PreviewRendering(
			xcrunURL: xcrunURL, environment: environment, processRunner: processRunner)
	}

	func handle(_ projectID: UUID, _ sessionID: UUID, _ request: PreviewRequest) async throws
		-> PreviewResult
	{
		let project = try await projects.lookup(
			projectRoot: request.projectRoot,
			projectID: projectID.uuidString.lowercased(), sessionID: sessionID.uuidString)
		return try await gate.run {
			try validate(request, project: project)
			do {
				return try await rendering.render(
					project: project, sessionID: sessionID, sourcePath: request.viewPath,
					size: request.screenSize)
			} catch let error as OwnedProcess.Failure
				where error == .cleanupFailed || error == .reapFailed
			{
				throw error
			} catch is CancellationError { throw CancellationError() } catch {
				let diagnostic =
					(error as? PreviewDiscovery.Failure)?.diagnostic(sourcePath: request.viewPath)
					?? String(describing: error)
				return try PreviewResult(
					status: "error", summary: String(diagnostic.prefix(4000)), width: nil,
					height: nil, artifact: nil)
			}
		}
	}

	private func validate(_ request: PreviewRequest, project: ResolvedProject) throws {
		guard
			request.viewPath.hasPrefix("Sources/AppViews/"),
			request.viewPath.hasSuffix(".swift")
		else { throw Failure.invalidPath }
		let view = try project.scope.resolve(request.viewPath)
		let properties = try view.resourceValues(forKeys: [
			.isRegularFileKey, .isSymbolicLinkKey, .fileSizeKey,
		])
		guard
			properties.isRegularFile == true,
			properties.isSymbolicLink != true,
			(properties.fileSize ?? Int.max) <= 1_048_576
		else { throw Failure.invalidPath }

	}
}
