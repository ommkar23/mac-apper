// @frontmatter:start
// Tests Preview repair guidance, private byte-bounded diagnostics, and output-overflow cleanup before returning errors.
// @frontmatter:end
import Darwin
import Foundation
import Testing
@testable import DevToolsApplication

@Test func previewProductionDiagnosticExplainsCodeVisibilityAndShowsRepair() {
	let message = PreviewDiscovery.Failure.preview_in_production.diagnostic(
		sourcePath: "Sources/AppViews/Counter.swift")
	#expect(message.hasPrefix("preview_in_production:"))
	#expect(message.contains("Sources/AppViews/Counter.swift"))
	#expect(message.contains("not whether Preview is being used during development"))
	#expect(message.contains("Wrap only the preview factory"))
	#expect(message.contains("Keep the normal view outside"))
	#expect(message.contains("Retry preview"))
	for code in [
		"#if MAC_APPER_PREVIEW", "@MainActor", "public func apperPreview_Example() -> some View",
		"#endif",
	] {
		#expect(message.contains(code))
	}
	#expect(message.utf8.count < 4096)
}

@Test func previewDiscoveryDiagnosticsExplainOtherFactoryFailures() {
	for (failure, explanation) in [
		(PreviewDiscovery.Failure.missing_preview, "No preview factory"),
		(.ambiguous_preview, "More than one preview factory"),
		(.invalid_preview_factory, "public, @MainActor, synchronous, nonthrowing, and zero-argument"),
	] {
		let message = failure.diagnostic(sourcePath: "Sources/AppViews/Counter.swift")
		#expect(message.hasPrefix(failure.rawValue + ":"))
		#expect(message.contains(explanation))
		#expect(message.contains("#if MAC_APPER_PREVIEW"))
	}
}

@Test func previewDiagnosticPayloadOmissionIsByteBoundedAndControlSafe() async throws {
	let privateOutput = String(
		repeating: "🔒e\u{0301}\u{001B}[31m\n/private/source SECRET=hidden\u{0000}", count: 2000)
	let fixture = try PreviewFixture(source: "// frozen-source")
	defer { try? fixture.remove() }
	let controller = PreviewController(
		projects: ProjectResolver(projectsRoot: fixture.root), gate: DevToolsOperationGate(),
		processRunner: { _, _, _, _, _ in throw PreviewRendering.Failure.processFailed(privateOutput) })
	let result = try await controller.handle(
		fixture.id, UUID(),
		PreviewRequest(
			projectRoot: fixture.project.path, viewPath: "Sources/AppViews/Example.swift", screenSize: nil
		))
	#expect(result.summary.utf8.count <= 4096)
	#expect(result.summary.contains("output=omitted"))
	#expect(!result.summary.contains("SECRET") && !result.summary.contains("/private"))
	#expect(result.summary.unicodeScalars.allSatisfy { !CharacterSet.controlCharacters.contains($0) })
}

@Test func previewDiagnosticFormattingBoundsUTF8WithoutPartialScalarsOrControls() {
	let formatted = PreviewDiagnostic.bounded(
		String(repeating: "🧪e\u{0301}\u{001B}\n\u{0000}", count: 2000))
	#expect(formatted.utf8.count <= 4096)
	#expect(formatted.hasSuffix(" [summary truncated]"))
	#expect(!formatted.contains("\u{FFFD}"))
	#expect(
		formatted.unicodeScalars.allSatisfy {
			$0 == "\n" || !CharacterSet.controlCharacters.contains($0)
		})
	#expect(PreviewDiagnostic.bounded("🧪\tvalue\n") == "🧪 value\n")
	let discovery = PreviewDiagnostic.summary(
		PreviewDiscovery.Failure.missing_preview, sourcePath: "Sources/AppViews/Example.swift")
	#expect(discovery.contains("#if MAC_APPER_PREVIEW\n"))
}

@Test func previewRealOutputOverflowReturnsDiagnosticAfterOwnedChildReaping() async throws {
	let fixture = try PreviewFixture(source: "// frozen-source")
	var childReaped = false
	defer { if childReaped { try? fixture.remove() } }
	let executable = fixture.root.appendingPathComponent("fixture-xcrun")
	let pidFile = fixture.root.appendingPathComponent("child.pid")
	try """
	#!/bin/sh
	printf '%s' "$$" > "$PID_FILE"
	while :; do printf 'fixture-output-not-a-secret.............................................'; done
	""".write(to: executable, atomically: true, encoding: .utf8)
	try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: executable.path)
	let controller = PreviewController(
		projects: ProjectResolver(projectsRoot: fixture.root), gate: DevToolsOperationGate(),
		xcrunURL: executable, environment: ["PID_FILE": pidFile.path])
	let result = try await controller.handle(
		fixture.id, UUID(),
		PreviewRequest(
			projectRoot: fixture.project.path, viewPath: "Sources/AppViews/Example.swift", screenSize: nil
		))
	#expect(result.status == "error")
	#expect(
		result.summary.hasPrefix(
			"outputExceeded: phase=appViewsBuild; outputLimitBytes=65536; outputTruncated=true;"))
	#expect(!result.summary.contains("fixture-output"))
	let pid = try #require(Int32(String(contentsOf: pidFile, encoding: .utf8)))
	try #require(kill(pid, 0) == -1 && errno == ESRCH)
	childReaped = true
	#expect(
		try FileManager.default.contentsOfDirectory(
			atPath: fixture.project.appendingPathComponent(".mac-apper/PreviewBuild").path
		).isEmpty)
}
