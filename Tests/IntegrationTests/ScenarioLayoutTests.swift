// @frontmatter:start
// Checks retirement of root scenario executables and bundles while preserving package-local tests.
// @frontmatter:end
import Foundation
import Testing

@Test func rootScenariosAreRetired() throws {
	let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
		.deletingLastPathComponent().deletingLastPathComponent()
	let manifest = try String(
		contentsOf: root.appendingPathComponent("Package.swift"), encoding: .utf8)
	for name in [
		"ScenarioRunner", "ProviderScenarioClient", "WebScenarioClient", "DirectAgentXPCScenario",
	] {
		#expect(!manifest.contains("name: \"\(name)\""))
	}
	for path in [
		"Scenarios", "Bundles/scenarios", "Scripts/bundle-scenario.swift",
		"Scripts/bundle-chat-scenario.swift",
		"Scripts/test-agent-xpc-scenario.sh",
	] {
		#expect(!FileManager.default.fileExists(atPath: root.appendingPathComponent(path).path))
	}
	for path in [
		"apps/built-in/dev-tools/Tests/DevToolsScenarioTests"
	] {
		#expect(FileManager.default.fileExists(atPath: root.appendingPathComponent(path).path))
	}
	let bundler = try String(
		contentsOf: root.appendingPathComponent("Plugins/BundlePlugin/plugin.swift"), encoding: .utf8)
	#expect(!bundler.contains("bundle-scenario.swift"))
	let cleanup = try String(
		contentsOf: root.appendingPathComponent("Plugins/UnbundlePlugin/plugin.swift"), encoding: .utf8)
	#expect(!cleanup.contains("Bundles/scenarios/"))
	#expect(!cleanup.contains("case [\"scenario\""))
}
