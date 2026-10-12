// @frontmatter:start
// Tests app bundle command discovery and generated DevTools integration metadata.
// @frontmatter:end
import Foundation
import Testing

private let root = URL(fileURLWithPath: #filePath)
	.deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()

@Test(arguments: ["Bundle", "Unbundle"]) func bundleHelpIsHandledBeforeWork(_ verb: String) throws {
	let source = try String(
		contentsOf: root.appendingPathComponent("Plugins/\(verb)Plugin/plugin.swift"), encoding: .utf8)
	#expect(source.contains("arguments == [\"--help\"]"))
	#expect(source.contains("print(Self.usage); return"))
	#expect(source.contains("Usage: swift package \(verb.lowercased()) app | --help"))
	#expect(!source.contains("scenario <collection-name>"))
}

@Test func devToolsIntegrationDoesNotRequireAnAppManifest() throws {
	let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
	defer { try? FileManager.default.removeItem(at: directory) }
	let process = Process()
	let output = Pipe()
	process.executableURL = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(
		"Library/Developer/Toolchains/swift-6.4.0-RELEASE.xctoolchain/usr/bin/swift")
	process.arguments = [
		root.appendingPathComponent("Scripts/generate-integration.swift").path,
		directory.path,
	]
	process.standardOutput = output
	process.standardError = output
	try process.run()
	let diagnostics = String(
		decoding: output.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
	process.waitUntilExit()
	#expect(process.terminationStatus == 0, "\(diagnostics)")
	let data = try Data(contentsOf: directory.appendingPathComponent("IntegrationCatalog.json"))
	let catalog = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
	let apps = try #require(catalog["apps"] as? [[String: Any]])
	#expect(!apps.contains { $0["id"] as? String == "web" })
	let devTools = try #require(apps.first { $0["id"] as? String == "dev-tools" })
	let application = try #require(devTools["application"] as? [String: Any])
	#expect(application["executableProduct"] as? String == "DevToolsTerminalClient")
	#expect(application["serviceProduct"] as? String == "DevToolsApplication")
	let entries = try #require(devTools["piExtensions"] as? [[String: Any]])
	#expect(entries.first?["tools"] as? [String] == ["build", "test", "run", "preview", "plan"])
	#expect(Set(entries.compactMap { $0["path"] as? String }) == ["PiExtension/Extension.ts"])
	#expect(
		!FileManager.default.fileExists(
			atPath: root.appendingPathComponent(
				"apps/built-in/dev-tools/AppManifest.yaml"
			).path))
}

@Test func packagingUsesStandaloneSwiftWithoutCLTFallback() throws {
	for path in [
		"Plugins/BundlePlugin/plugin.swift", "Scripts/package-providers.swift",
		"Plugins/CleanTestPlugin/plugin.swift",
	] {
		let source = try String(contentsOf: root.appendingPathComponent(path), encoding: .utf8)
		#expect(source.contains("swift-6.4.0-RELEASE.xctoolchain/usr/bin"))
		#expect(!source.contains("\"/usr/bin/xcrun\""))
		#expect(source.contains("\"SWIFT_EXEC\""))
	}
}

@Test func appBundleStagesAgentResourcesInsideItsXPCService() throws {
	let plugin = try String(
		contentsOf: root.appendingPathComponent("Plugins/BundlePlugin/plugin.swift"), encoding: .utf8)
	#expect(plugin.contains("service.appendingPathComponent(\"Contents/Resources\")"))
	#expect(
		plugin.contains("serviceResources.appendingPathComponent(\"Agent_AgentApplication.bundle\")"))
}

@Test func appBundleStagesAgentOwnedCreateExtensions() throws {
	let plugin = try String(
		contentsOf: root.appendingPathComponent(
			"Plugins/BundlePlugin/plugin.swift"), encoding: .utf8)
	#expect(plugin.contains("root.appendingPathComponent(\"Agent/Extensions\")"))
	#expect(plugin.contains("resources.appendingPathComponent(\"AgentExtensions\")"))
	#expect(
		!FileManager.default.fileExists(
			atPath: root.appendingPathComponent(
				"apps/built-in/dev-tools/Extensions"
			).path))
}
