// @frontmatter:start
// Checks DevTools OpenXPC target ownership and bundle metadata.
// @frontmatter:end
import Foundation
import Testing

private let packageRoot = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
	.deletingLastPathComponent().deletingLastPathComponent()

@Test func devToolsPackageUsesGeneratedClientInsteadOfNativeClient() throws {
	let manifest = try String(
		contentsOf: packageRoot.appendingPathComponent("Package.swift"), encoding: .utf8)
	#expect(!manifest.contains("DevToolsMacosClient"))
	#expect(!manifest.contains("name: \"DevToolsXPC\""))
	#expect(
		!FileManager.default.fileExists(
			atPath: packageRoot.appendingPathComponent("Sources/DevToolsXPC").path))
	for required in ["DevToolsApplication", "DevToolsTerminalClient"] {
		#expect(manifest.contains("name: \"\(required)\""))
	}
	#expect(
		manifest.contains("name: \"DevToolsTerminalClient\",\n\t\t\tpath: \"Sources/AgentClient\""))
	#expect(
		FileManager.default.isReadableFile(
			atPath: packageRoot.appendingPathComponent(
				"Sources/AgentClient/ClientTarget.swift"
			).path))
	#expect(
		!FileManager.default.fileExists(
			atPath: packageRoot.appendingPathComponent(
				"Sources/DevToolsTerminalClient"
			).path))
}

@Test func devToolsApplicationSourcesFollowDomainResponsibilities() throws {
	for path in [
		"Controllers/BuildController.swift", "Controllers/TestController.swift",
		"Controllers/RunController.swift",
		"Controllers/PreviewController.swift", "Controllers/PlanController.swift",
		"PlanStore.swift",
		"ProjectManifest.swift", "ProjectScope.swift", "ProjectResolver.swift",
		"Controllers/ControllerFactory.swift", "main.swift", "OwnedProcess.swift",
	] {
		#expect(
			FileManager.default.isReadableFile(
				atPath: packageRoot.appendingPathComponent(
					"Sources/Application/\(path)"
				).path), "Missing \(path)")
	}
	for name in [
		"Build", "Run", "Preview", "Plan", "Project", "Process", "Service",
		"GeneratedAppManifest.swift", "OpenXPCDevToolsService.swift", "ProjectRegistry.swift",
		"SourceBuildRunner.swift", "DevelopmentLauncher.swift", "DevToolsControllers.swift",
		"DevToolsServiceMain.swift", "DevToolsControllerFactory.swift",
	] {
		#expect(
			!FileManager.default.fileExists(
				atPath: packageRoot.appendingPathComponent(
					"Sources/Application/\(name)"
				).path))
	}
	let assembly = try String(
		contentsOf: packageRoot.appendingPathComponent(
			"Sources/Application/Controllers/ControllerFactory.swift"), encoding: .utf8)
	#expect(assembly.contains("struct ControllerFactory:"))
	#expect(assembly.contains("func controllers() -> OpenXPCGeneratedService.Controllers"))
	for controller in [
		"BuildController", "TestController", "RunController", "PreviewController", "PlanController",
	] {
		#expect(assembly.contains(controller))
	}
	#expect(
		!FileManager.default.fileExists(
			atPath: packageRoot.appendingPathComponent(
				"Sources/Application/DevToolsToolHandlers.swift"
			).path))
}

@Test func retiredSwiftToolSpecAndBuildPluginAreAbsent() {
	for path in [
		"Sources/Application/XPCSpec.swift",
		"Sources/DevToolsBuildToolCore/AppBuildGenerator.swift",
		"Plugins/DevToolsBuildPlugin/DevToolsBuildPlugin.swift",
		"Sources/DevToolsMacosClient",
	] {
		#expect(!FileManager.default.fileExists(atPath: packageRoot.appendingPathComponent(path).path))
	}
}

@Test func authoredExtensionsDoNotLiveInGeneratedPiExtensionDirectory() throws {
	#expect(
		!FileManager.default.fileExists(
			atPath: packageRoot.appendingPathComponent("AppManifest.yaml").path))
	#expect(
		!FileManager.default.fileExists(
			atPath: packageRoot.appendingPathComponent("PiExtension").path))
	#expect(
		!FileManager.default.fileExists(
			atPath: packageRoot.appendingPathComponent("Extensions").path))
}

@Test func devToolsBundleUsesTheGeneratedAgentClientExecutable() throws {
	let plist = packageRoot.appendingPathComponent("Resources/Info.plist")
	let values =
		try PropertyListSerialization.propertyList(
			from: Data(contentsOf: plist), format: nil) as? [String: Any]
	#expect(values?["CFBundleExecutable"] as? String == "DevToolsTerminalClient")
	let generation = try String(
		contentsOf: packageRoot.appendingPathComponent("OpenXPCGen.yaml"), encoding: .utf8)
	#expect(generation.contains("target: DevToolsTerminalClient"))
	#expect(generation.contains("target: DevToolsApplication"))
}
