// @frontmatter:start
// Tests actionable Preview discovery diagnostics with source context, repair guidance, and a guarded SwiftUI factory example.
// @frontmatter:end
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
