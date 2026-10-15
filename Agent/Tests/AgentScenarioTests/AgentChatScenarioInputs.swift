// @frontmatter:start
// Supplies production Agent, authored MCP/codemode resources, and optional DevTools/VisionCLI inputs to a signed test host.
// @frontmatter:end
import Foundation
import Scenario

private final class ChatTestBundleAnchor: NSObject {}

@MainActor enum AgentChatScenarioInputs {
	static func prepareHost(
		includeDevTools: Bool = false, includeVision: Bool = false,
		isolatedHome: IsolatedScenarioHome? = nil
	) throws
		-> PackagedTestHost
	{
		let package = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
			.deletingLastPathComponent().deletingLastPathComponent()
		let root = package.deletingLastPathComponent()
		let environment = ProcessInfo.processInfo.environment
		let products =
			environment["AGENT_SCENARIO_PRODUCTS"].map { URL(fileURLWithPath: $0) }
			?? package.appendingPathComponent(".build/debug")
		guard
			let tests = Bundle(for: ChatTestBundleAnchor.self).executableURL
		else { throw ScenarioFailure.message("Swift test bundle unavailable") }
		return try PackagedTestHost.withInputDirectory { inputs in
			try PackagedTestHost.runPreparation(
				URL(fileURLWithPath: "/usr/bin/xcrun"),
				arguments: [
					"swift", root.appendingPathComponent("Scripts/generate-integration.swift").path,
					inputs.path,
				])
			let agent = TestHostService(
				bundleName: "AgentXPCService.xpc",
				executable: products.appendingPathComponent("AgentApplication"),
				infoPlist: package.appendingPathComponent("Resources/AgentXPCService-Info.plist"),
				resources: [
					TestHostResource(
						source: products.appendingPathComponent("Agent_AgentApplication.bundle"),
						relativePath: "Agent_AgentApplication.bundle")
				],
				environment: isolatedHome.map {
					$0.environment.merging([
						"PI_CODING_AGENT_DIR": $0.directory.appendingPathComponent(".pi/agent").path,
						"PATH": environment["PATH"] ?? "/usr/bin:/bin",
					]) { _, value in value }
				} ?? [:])
			var applications: [TestHostApplication] = []
			var resources = [
				TestHostResource(
					source: inputs.appendingPathComponent("IntegrationCatalog.json"),
					relativePath: "IntegrationCatalog.json"),
				TestHostResource(
					source: products.appendingPathComponent("Agent_AgentApplication.bundle"),
					relativePath: "Agent_AgentApplication.bundle"),
				TestHostResource(
					source: package.appendingPathComponent("Extensions"), relativePath: "AgentExtensions"),
			]
			if let vision = try AgentVisionPreparation.resource(
				includeVision: includeVision, root: root, environment: environment,
				envFile: counterVisionEnvFile,
				run: { try PackagedTestHost.runPreparation($0, arguments: $1) })
			{
				resources.append(vision)
			}
			if includeDevTools {
				let devPackage = root.appendingPathComponent("apps/built-in/dev-tools")
				let devProducts =
					environment["DEV_TOOLS_SCENARIO_PRODUCTS"].map { URL(fileURLWithPath: $0) }
					?? devPackage.appendingPathComponent(".build/debug")
				if environment["DEV_TOOLS_SCENARIO_PRODUCTS"] == nil {
					try PackagedTestHost.runPreparation(
						URL(fileURLWithPath: "/usr/bin/xcrun"),
						arguments: ["swift", "build", "--package-path", devPackage.path])
				}
				guard
					let devExtension = Bundle(
						url: devProducts.appendingPathComponent(
							"DevTools_DevToolsTerminalClient.bundle"))?.url(
							forResource: "Extension", withExtension: "ts")
				else { throw ScenarioFailure.message("generated DevTools extension missing") }
				applications.append(
					TestHostApplication(
						bundleName: "DevTools.app",
						executable: devProducts.appendingPathComponent("DevToolsTerminalClient"),
						infoPlist: devPackage.appendingPathComponent("Resources/Info.plist"),
						services: [
							TestHostService(
								bundleName: "DevToolsApplication.xpc",
								executable: devProducts.appendingPathComponent("DevToolsApplication"),
								infoPlist: devPackage.appendingPathComponent(
									"Resources/DevToolsXPCService-Info.plist"),
								resources: [
									TestHostResource(
										source: devProducts.appendingPathComponent(
											"DevTools_DevToolsApplication.bundle"),
										relativePath: "DevTools_DevToolsApplication.bundle")
								], environment: isolatedHome?.environment ?? [:])
						],
						resources: [
							TestHostResource(
								source: devExtension,
								relativePath: "PiExtension/Extension.ts")
						]))
			}
			let host = PackagedTestHost(
				testBundleExecutable: tests, loader: try PackagedTestHost.swiftPMTestLoader(),
				services: [agent], applications: applications, resources: resources)
			try host.prepare()
			return host
		}
	}
}
