// @frontmatter:start
// Injects completed and uncertain Preview child failures to check propagation and request-file retention without starting children.
// @frontmatter:end
import Foundation
import Testing
@testable import DevToolsApplication

private enum PreviewFailureStage: Sendable { case compiler, snapshot }

private func injectedPreviewRunner(
	_ failure: any Error & Sendable, stage: PreviewFailureStage
) -> PreviewRendering.ProcessRunner {
	return { executable, arguments, workspace, _, _ in
		let manager = FileManager.default
		if stage == .compiler { throw failure }
		let products = workspace.appendingPathComponent("Build/products")
		if arguments.contains("--show-bin-path") {
			try manager.createDirectory(at: products, withIntermediateDirectories: true)
			let worker = products.appendingPathComponent("ApperSnapshot")
			try Data("nonexecuted-worker".utf8).write(to: worker)
			try manager.setAttributes([.posixPermissions: 0o700], ofItemAtPath: worker.path)
			return products.path
		}
		if arguments == ["--show-sdk-path"] { return "/unused-sdk" }
		if arguments.contains("-dump-ast") {
			if !arguments.contains("MAC_APPER_PREVIEW") { return #"{"_kind":"source_file","items":[]}"# }
			return
				#"{"_kind":"source_file","items":[{"_kind":"func_decl","name":{"base_name":{"name":"apperPreview_Fixture"}},"access":"public","thrown_type":"","params":{},"attrs":[{"_kind":"custom_attr","type":"$sScMD"}],"opaque_result_decl":{"reqs":[{"protocol":"s:7SwiftUI4ViewP"}]}}]}"#
		}
		if executable.lastPathComponent == "ApperSnapshot" {
			try #require(arguments.count == 3)
			try Data("incomplete-png".utf8).write(to: URL(fileURLWithPath: arguments[2]))
			throw failure
		}
		return ""
	}
}

@Test func previewCleanupFailuresPropagateAndRetainRequestFiles() async throws {
	for failure in [OwnedProcess.Failure.cleanupFailed, .reapFailed] {
		for stage in [PreviewFailureStage.compiler, .snapshot] {
			let fixture = try PreviewFixture(source: "// frozen-source")
			defer { try? fixture.remove() }  // All injected failures occur without any real child.
			let original = try Data(contentsOf: fixture.project.appendingPathComponent("Package.swift"))
			let controller = PreviewController(
				projects: ProjectResolver(projectsRoot: fixture.root), gate: DevToolsOperationGate(),
				processRunner: injectedPreviewRunner(failure, stage: stage))
			await #expect(throws: failure) {
				_ = try await controller.handle(
					fixture.id, UUID(),
					PreviewRequest(
						projectRoot: fixture.project.path, viewPath: "Sources/AppViews/Example.swift",
						screenSize: nil))
			}
			let workspaces = try FileManager.default.contentsOfDirectory(
				at: fixture.project.appendingPathComponent(".mac-apper/PreviewBuild"),
				includingPropertiesForKeys: nil)
			#expect(workspaces.count == 1)
			if let workspace = workspaces.first {
				#expect(
					try String(
						contentsOf: workspace.appendingPathComponent("Sources/AppViews/Example.swift"),
						encoding: .utf8) == "// frozen-source")
			}
			if stage == .snapshot {
				let artifacts = try FileManager.default.contentsOfDirectory(
					at: fixture.project.appendingPathComponent(".mac-apper/Artifacts"),
					includingPropertiesForKeys: nil)
				#expect(artifacts.count == 1)
				if let artifact = artifacts.first {
					#expect(
						try Data(contentsOf: artifact.appendingPathComponent("render.png"))
							== Data("incomplete-png".utf8))
				}
			}
			#expect(
				try Data(contentsOf: fixture.project.appendingPathComponent("Package.swift")) == original)
		}
	}
}

@Test func previewCompletedChildFailuresKeepTypedDiagnosticsAndRemoveScratch() async throws {
	let failures: [any Error & Sendable] = [
		PreviewRendering.Failure.processFailed("compiler-or-worker-diagnostic"),
		OwnedProcess.Failure.timedOut, OwnedProcess.Failure.outputExceeded,
	]
	for failure in failures {
		for stage in [PreviewFailureStage.compiler, .snapshot] {
			let fixture = try PreviewFixture(source: "// frozen-source")
			defer { try? fixture.remove() }
			let controller = PreviewController(
				projects: ProjectResolver(projectsRoot: fixture.root), gate: DevToolsOperationGate(),
				processRunner: injectedPreviewRunner(failure, stage: stage))
			let result = try await controller.handle(
				fixture.id, UUID(),
				PreviewRequest(
					projectRoot: fixture.project.path, viewPath: "Sources/AppViews/Example.swift",
					screenSize: nil))
			#expect(result.status == "error")
			#expect(result.summary == String(describing: failure))
			#expect(result.artifact == nil && result.width == nil && result.height == nil)
			#expect(
				try FileManager.default.contentsOfDirectory(
					atPath: fixture.project.appendingPathComponent(".mac-apper/PreviewBuild").path
				).isEmpty)
			if stage == .snapshot {
				#expect(
					try FileManager.default.contentsOfDirectory(
						atPath: fixture.project.appendingPathComponent(".mac-apper/Artifacts").path
					).isEmpty)
			}
		}
	}
}
