// @frontmatter:start
// Injects completed and uncertain Preview child failures to check propagation and request-file retention without starting children.
// @frontmatter:end
import Foundation
import Testing
@testable import DevToolsApplication

private enum PreviewFailureStage: Int, CaseIterable, Sendable {
	case compiler, binPath, sdk, previewAST, productionAST, snapshotBuild, snapshot
	var phase: String {
		[
			"appViewsBuild", "binPath", "sdkDiscovery", "previewAST", "productionAST", "snapshotBuild",
			"snapshotExecution",
		][rawValue]
	}
	var outputLimit: Int { [65_536, 4096, 65_536, 4_194_304, 4_194_304, 65_536, 65_536][rawValue] }
	var timeout: Duration { .seconds([120, 10, 10, 30, 30, 120, 15][rawValue]) }
}

private final class PreviewCallCounter: @unchecked Sendable {
	private let lock = NSLock()
	private var count = 0
	func next() -> Int {
		lock.withLock {
			defer { count += 1 }; return count
		}
	}
	var value: Int { lock.withLock { count } }
}

private func injectedPreviewRunner(
	_ failure: any Error & Sendable, stage: PreviewFailureStage,
	counter: PreviewCallCounter = PreviewCallCounter()
) -> PreviewRendering.ProcessRunner {
	return { executable, arguments, workspace, timeout, outputLimit in
		let manager = FileManager.default
		let current = PreviewFailureStage(rawValue: counter.next())!
		#expect(timeout == current.timeout)
		#expect(outputLimit == current.outputLimit)
		if current == stage && stage != .snapshot { throw failure }
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
		for stage in PreviewFailureStage.allCases {
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
			if stage != .snapshot {
				#expect(
					!FileManager.default.fileExists(
						atPath: fixture.project.appendingPathComponent(".mac-apper/Artifacts").path))
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
		PreviewRendering.Failure.processFailed(
			"private-source /private/path SECRET=hidden\u{001B}[31m"),
		OwnedProcess.Failure.timedOut, OwnedProcess.Failure.outputExceeded, OwnedProcess.Failure.launch,
		SwiftToolchain.Failure.missingExecutable(URL(fileURLWithPath: "/private/SECRET/swift")),
		NSError(domain: "SECRET", code: 1, userInfo: [NSLocalizedDescriptionKey: "private-source"]),
	]
	for failure in failures {
		for stage in PreviewFailureStage.allCases {
			let fixture = try PreviewFixture(source: "// frozen-source")
			defer { try? fixture.remove() }
			let original = try Data(contentsOf: fixture.project.appendingPathComponent("Package.swift"))
			let counter = PreviewCallCounter()
			let controller = PreviewController(
				projects: ProjectResolver(projectsRoot: fixture.root), gate: DevToolsOperationGate(),
				processRunner: injectedPreviewRunner(failure, stage: stage, counter: counter))
			let result = try await controller.handle(
				fixture.id, UUID(),
				PreviewRequest(
					projectRoot: fixture.project.path, viewPath: "Sources/AppViews/Example.swift",
					screenSize: nil))
			#expect(result.status == "error")
			#expect(result.summary.contains("phase=\(stage.phase)"))
			#expect(result.summary.contains("outputLimitBytes=\(stage.outputLimit)"))
			let code =
				(failure as? OwnedProcess.Failure).map { String(describing: $0) }
				?? (failure is SwiftToolchain.Failure
					? "toolchainUnavailable"
					: failure is PreviewRendering.Failure ? "processFailed" : "processError")
			#expect(result.summary.hasPrefix(code + ":"))
			#expect(
				result.summary.contains("outputTruncated=\(code == "outputExceeded" ? "true" : "unknown")"))
			#expect(result.summary.contains("output=omitted"))
			#expect(!result.summary.contains("private-source") && !result.summary.contains("SECRET"))
			#expect(result.summary.utf8.count <= 4096)
			#expect(counter.value == stage.rawValue + 1)
			#expect(
				try Data(contentsOf: fixture.project.appendingPathComponent("Package.swift")) == original)
			#expect(
				try String(
					contentsOf: fixture.project.appendingPathComponent("Sources/AppViews/Example.swift"),
					encoding: .utf8) == "// frozen-source")
			#expect(result.artifact == nil && result.width == nil && result.height == nil)
			if stage != .snapshot {
				#expect(
					!FileManager.default.fileExists(
						atPath: fixture.project.appendingPathComponent(".mac-apper/Artifacts").path))
			}
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

@Test func previewCancellationRemainsThrownAfterCompletedCleanup() async throws {
	for stage in PreviewFailureStage.allCases {
		let fixture = try PreviewFixture(source: "// frozen-source")
		defer { try? fixture.remove() }  // No actual child is started by this seam.
		let counter = PreviewCallCounter()
		let controller = PreviewController(
			projects: ProjectResolver(projectsRoot: fixture.root), gate: DevToolsOperationGate(),
			processRunner: injectedPreviewRunner(CancellationError(), stage: stage, counter: counter))
		await #expect(throws: CancellationError.self) {
			_ = try await controller.handle(
				fixture.id, UUID(),
				PreviewRequest(
					projectRoot: fixture.project.path, viewPath: "Sources/AppViews/Example.swift",
					screenSize: nil))
		}
		#expect(counter.value == stage.rawValue + 1)
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
