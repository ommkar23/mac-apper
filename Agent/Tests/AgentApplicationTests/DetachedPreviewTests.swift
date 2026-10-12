// @frontmatter:start
// Checks that protected preview files do not depend on fixtures or preview configuration.
// @frontmatter:end
import Testing

@testable import AgentApplication

@Test func detachedPreviewHasNoFixtureOrConfigurationDependency() throws {
	let files = try BaseAppTemplate.protectedFiles(appID: "f43b9b04-45ca-4bcc-ab27-e8d607df3535")
	#expect(files.keys.allSatisfy { !$0.contains("Fixture") })
	#expect(files.values.allSatisfy { !$0.contains("PreviewConfiguration") })
	#expect(files.values.allSatisfy { !$0.contains("configRelativePath") })
}
