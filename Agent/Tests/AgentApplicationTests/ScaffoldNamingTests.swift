// @frontmatter:start
// Checks protected scaffold title source wiring and preserves navigation-title overrides.
// @frontmatter:end
import Foundation
import Testing

@testable import AgentApplication

@Test func scaffoldNamingUsesLiteralBundleTitleAndPreservesNavigationOverrides() throws {
	let source = try #require(
		BaseAppTemplate.protectedFiles(appID: UUID().uuidString.lowercased())[
			"Sources/ProductionApp/ProductionApp.swift"])
	#expect(BaseAppTemplate.version == "9")
	#expect(source.contains("WindowGroup(Text(verbatim: ProductionWindowTitle.resolve()))"))
	#expect(source.contains("bundle.object(forInfoDictionaryKey: key) as? String"))
	#expect(!source.contains(".navigationTitle("))
	#expect(!source.contains("NSWindow"))
	#expect(source.contains("ApplicationRoot(model: runtime.model)"))
	#expect(source.contains("ApplicationModel.production(appID:"))
}
