// @frontmatter:start
// Supplies DevTools executables, bundle plists, and optional Preview rendering/extension resources to the signed XPC host.
// @frontmatter:end
import Foundation
import Scenario

enum DevToolsScenarioInputs {
	private static let package = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
		.deletingLastPathComponent().deletingLastPathComponent()

	@MainActor static func host(
		includePreviewResources: Bool = false, serviceEnvironment: [String: String] = [:],
		clientEnvironment: [String: String] = [:]
	) throws -> PackagedXPCHost {
		let products =
			ProcessInfo.processInfo.environment["DEV_TOOLS_SCENARIO_PRODUCTS"].map {
				URL(fileURLWithPath: $0)
			} ?? package.appendingPathComponent(".build/debug")
		var appResources: [TestHostResource] = []
		var serviceResources: [TestHostResource] = []
		if includePreviewResources {
			guard
				let harness = Bundle.module.url(forResource: "PreviewToolHarness", withExtension: "ts"),
				let extensionFile = Bundle(
					url: products.appendingPathComponent(
						"DevTools_DevToolsTerminalClient.bundle"))?.url(
						forResource: "Extension", withExtension: "ts")
			else { throw ScenarioFailure.message("preview tool registration harness missing") }
			appResources = [
				TestHostResource(
					source: extensionFile,
					relativePath: "PiExtension/Extension.ts"),
				TestHostResource(source: harness, relativePath: "PreviewToolHarness.ts"),
			]
			serviceResources = [
				TestHostResource(
					source: products.appendingPathComponent("DevTools_DevToolsApplication.bundle"),
					relativePath: "DevTools_DevToolsApplication.bundle")
			]
		}
		return PackagedXPCHost(
			try XPCHostDefinition(
				appName: "DevToolsScenario",
				clientExecutable: products.appendingPathComponent("DevToolsTerminalClient"),
				serviceExecutable: products.appendingPathComponent("DevToolsApplication"),
				appPlist: package.appendingPathComponent("Resources/Info.plist"),
				servicePlist: package.appendingPathComponent("Resources/DevToolsXPCService-Info.plist"),
				appResources: appResources, serviceResources: serviceResources,
				serviceEnvironment: serviceEnvironment, clientEnvironment: clientEnvironment))
	}
}
