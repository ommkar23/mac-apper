// @frontmatter:start
// Tests integration catalog resolution and Pi extension and provider process configuration.
// @frontmatter:end
import Foundation
import Testing

@testable import AgentApplication

private struct FixtureIntegration {
	let catalog: AgentIntegrationCatalog
	let root: URL
	let devToolsControl: URL
	let webControl: URL
	let devToolsClient: URL
	let webClient: URL
	let devToolsExtension: URL
	let nameExtension: URL
	let createExtension: URL
	let instructionsExtension: URL
	let webExtension: URL
	let parallelExtension: URL
}

private func makeFixtureIntegration(at root: URL) throws -> FixtureIntegration {
	let devContents = root.appendingPathComponent("Applications/DevTools.app/Contents")
	let webContents = root.appendingPathComponent("Applications/Web.app/Contents")
	let devResources = devContents.appendingPathComponent("Resources/PiExtension")
	let webResources = webContents.appendingPathComponent("Resources/PiExtension")
	try FileManager.default.createDirectory(at: devResources, withIntermediateDirectories: true)
	try FileManager.default.createDirectory(at: webResources, withIntermediateDirectories: true)
	let devToolsExtension = devResources.appendingPathComponent("Extension.ts")
	let agentExtensions = root.appendingPathComponent("Agent/Extensions")
	try FileManager.default.createDirectory(at: agentExtensions, withIntermediateDirectories: true)
	let nameExtension = agentExtensions.appendingPathComponent("name-and-rename.ts")
	let createExtension = agentExtensions.appendingPathComponent("create-app.ts")
	let instructionsExtension = agentExtensions.appendingPathComponent("create-instructions.ts")
	let webExtension = webResources.appendingPathComponent("Extension.ts")
	let parallelExtension = agentExtensions.appendingPathComponent("parallel-codemode.ts")
	for file in [
		devToolsExtension, nameExtension, createExtension, instructionsExtension, webExtension,
		parallelExtension,
	] {
		try Data().write(to: file)
	}
	let devToolsControl = devContents.appendingPathComponent("MacOS/DevToolsMacosClient")
	let webControl = webContents.appendingPathComponent("MacOS/AbsentWebControl")
	let devToolsClient = devContents.appendingPathComponent("MacOS/DevToolsTerminalClient")
	let webClient = webContents.appendingPathComponent("MacOS/WebAgentClient")
	let devToolsService = devContents.appendingPathComponent(
		"XPCServices/DevToolsApplication.xpc/Contents/MacOS/DevToolsApplication")
	let webService = webContents.appendingPathComponent(
		"XPCServices/WebApplication.xpc/Contents/MacOS/WebApplication")
	for service in [devToolsService, webService] {
		try FileManager.default.createDirectory(
			at: service.deletingLastPathComponent(), withIntermediateDirectories: true)
		try Data().write(to: service)
		try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: service.path)
	}
	try FileManager.default.createDirectory(
		at: devToolsControl.deletingLastPathComponent(), withIntermediateDirectories: true)
	try FileManager.default.createDirectory(
		at: webControl.deletingLastPathComponent(), withIntermediateDirectories: true)
	for file in [devToolsClient, webClient] { try Data().write(to: file) }
	let app: (String, String, String, Bool, [[String: Any]]) -> [String: Any] = {
		id, bundle, executable, registers, extensions in
		[
			"id": id, "packagePath": "missing/\(id)",
			"application": [
				"bundleName": bundle, "executableProduct": executable,
				"serviceProduct": id == "dev-tools" ? "DevToolsApplication" : "WebApplication",
				"serviceIdentifier": "test.\(id)",
				"xpcServicePlist": "Resources/service.plist", "infoPlist": "Resources/Info.plist",
				"registersProjects": registers,
			],
			"piExtensions": extensions,
		]
	}
	let catalogObject: [String: Any] = [
		"schemaVersion": 1,
		"apps": [
			app(
				"dev-tools", "DevTools.app", "DevToolsMacosClient", true,
				[
					[
						"path": "PiExtension/Extension.ts", "agents": ["create"], "tools": ["build", "test"],
						"firstRequestOnly": false,
					]
				]),
			app(
				"web", "Web.app", "WebAgentClient", false,
				[
					[
						"path": "PiExtension/Extension.ts", "agents": ["chat", "create"],
						"tools": ["search", "extract"], "firstRequestOnly": false,
					]
				]),
		],
		"agents": [
			["id": "chat", "apps": ["web"], "baseTools": [], "systemPrompt": "Chat fixture"],
			[
				"id": "create", "apps": ["dev-tools", "web"], "baseTools": ["read"],
				"systemPrompt": "Create fixture",
			],
		],
	]
	let catalogURL = root.appendingPathComponent("IntegrationCatalog.json")
	try JSONSerialization.data(withJSONObject: catalogObject).write(to: catalogURL)
	return try .init(
		catalog: AgentIntegrationCatalog.load(from: catalogURL), root: root,
		devToolsControl: devToolsControl, webControl: webControl,
		devToolsClient: devToolsClient, webClient: webClient,
		devToolsExtension: devToolsExtension, nameExtension: nameExtension,
		createExtension: createExtension, instructionsExtension: instructionsExtension,
		webExtension: webExtension, parallelExtension: parallelExtension)
}

@MainActor @Test func createAppRuntimePassesProviderTerminalClientsAndBoundIDsToItsAgent()
	async throws
{
	let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
	defer { try? FileManager.default.removeItem(at: root) }
	let projectID = UUID().uuidString.lowercased()
	let sessionID = UUID().uuidString.lowercased()
	let project = root.appendingPathComponent(projectID)
	try FileManager.default.createDirectory(at: project, withIntermediateDirectories: true)
	let executable = root.appendingPathComponent("fixture-pi")
	let integration = try makeFixtureIntegration(at: root.appendingPathComponent("integration"))
	try "#!/bin/sh\nprintf '%s\\n' \"$*\" >> devtools-calls.txt\nprintf '%s\\n' '{}'\n"
		.write(to: integration.devToolsControl, atomically: true, encoding: .utf8)
	try
		"#!/bin/sh\nprintf '%s\\n' \"$@\" > pi-arguments.txt\nprintf '%s\\n%s\\n%s\\n%s\\n%s\\n%s\\n' \"$MAC_APPER_DEV_TOOLS_TERMINAL_CLIENT_PATH\" \"$OPENXPC_WEBAGENTCLIENT_CLIENT_PATH\" \"$OPENXPC_DEVTOOLSTERMINALCLIENT_CLIENT_PATH\" \"$OPENXPC_PROJECT_ID\" \"$OPENXPC_SESSION_ID\" \"$OPENXPC_PROJECT_ROOT\" > xpc-client-environment.txt\nwhile IFS= read -r line; do printf '%s\\n' '{\"type\":\"agent_end\"}'; done\n"
		.write(to: executable, atomically: true, encoding: .utf8)
	try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: executable.path)
	try FileManager.default.setAttributes(
		[.posixPermissions: 0o700], ofItemAtPath: integration.devToolsControl.path)
	#expect(!FileManager.default.fileExists(atPath: integration.webControl.path))
	for client in [integration.devToolsClient, integration.webClient] {
		try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: client.path)
	}
	let runtime = PiRPCProcess(
		executable: executable,
		integrationCatalog: integration.catalog, integrationRootURL: integration.root)
	let session = project.appendingPathComponent(".pi/sessions/\(sessionID).jsonl")
	_ = try await runtime.start(
		agentID: "create", in: project, sessionFile: session, title: "XPC clients",
		firstRequest: true)
	let captured = project.appendingPathComponent("xpc-client-environment.txt")
	for _ in 0..<100 where !FileManager.default.fileExists(atPath: captured.path) {
		try await Task.sleep(for: .milliseconds(10))
	}
	let values = try String(contentsOf: captured, encoding: .utf8).split(separator: "\n").map(
		String.init)
	#expect(
		values == [
			integration.devToolsClient.path,
			integration.devToolsClient.path, projectID, sessionID, project.path,
		])
	let calls = try String(
		contentsOf: project.appendingPathComponent("devtools-calls.txt"), encoding: .utf8)
	#expect(!calls.contains("--start-service"))
	#expect(calls.contains("--register-project \(projectID) \(sessionID)"))
	#expect(
		!FileManager.default.fileExists(
			atPath: project.appendingPathComponent("web-calls.txt").path))
	let firstArguments = try String(
		contentsOf: project.appendingPathComponent("pi-arguments.txt"), encoding: .utf8)
	#expect(firstArguments.contains(integration.instructionsExtension.path))
	#expect(firstArguments.contains(integration.nameExtension.path))
	#expect(firstArguments.contains(integration.devToolsExtension.path))
	#expect(firstArguments.contains(integration.createExtension.path))
	#expect(!firstArguments.contains(integration.webExtension.path))
	#expect(firstArguments.contains(integration.parallelExtension.path))
	#expect(firstArguments.contains("codemode"))
	#expect(await runtime.stop())

	let nextSession = project.appendingPathComponent(
		".pi/sessions/\(UUID().uuidString.lowercased()).jsonl")
	_ = try await runtime.start(
		agentID: "create", in: project, sessionFile: nextSession, title: "Follow up",
		firstRequest: false)
	for _ in 0..<100 {
		let arguments = try? String(
			contentsOf: project.appendingPathComponent("pi-arguments.txt"), encoding: .utf8)
		if arguments?.contains(nextSession.path) == true { break }
		try await Task.sleep(for: .milliseconds(10))
	}
	let subsequentArguments = try String(
		contentsOf: project.appendingPathComponent("pi-arguments.txt"), encoding: .utf8)
	#expect(subsequentArguments.contains(integration.instructionsExtension.path))
	#expect(subsequentArguments.contains(integration.devToolsExtension.path))
	#expect(!subsequentArguments.contains(integration.createExtension.path))
	#expect(!subsequentArguments.contains(integration.webExtension.path))
	#expect(subsequentArguments.contains(integration.parallelExtension.path))
	#expect(await runtime.stop())
}

@MainActor @Test func chatDoesNotStartBundledWebService() async throws {
	let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
	defer { try? FileManager.default.removeItem(at: root) }
	try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
	let executable = root.appendingPathComponent("fixture-pi")
	try "#!/bin/sh\nwhile IFS= read -r line; do printf '%s\\n' '{\"type\":\"agent_end\"}'; done\n"
		.write(to: executable, atomically: true, encoding: .utf8)
	let integration = try makeFixtureIntegration(at: root.appendingPathComponent("integration"))
	for file in [executable, integration.webClient] {
		try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: file.path)
	}
	let runtime = PiRPCProcess(
		executable: executable,
		integrationCatalog: integration.catalog, integrationRootURL: integration.root)
	_ = try await runtime.start(
		agentID: "chat", in: root,
		sessionFile: root.appendingPathComponent(".pi/sessions/\(UUID().uuidString).jsonl"),
		title: "Chat", firstRequest: false)
	#expect(
		!FileManager.default.fileExists(
			atPath: root.appendingPathComponent("web-calls.txt").path))
	#expect(await runtime.stop())
}

@MainActor @Test(arguments: [true, false])
func chatRuntimeSelectsCodemodeWithoutProviderOrBuiltinTools(firstRequest: Bool) async throws {
	let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
	defer { try? FileManager.default.removeItem(at: root) }
	try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
	let executable = root.appendingPathComponent("fixture-pi")
	try
		"#!/bin/sh\nprintf '%s\\n' \"$@\" > arguments.txt\nwhile IFS= read -r line; do printf '%s\\n' '{\"type\":\"agent_end\"}'; done\n"
		.write(to: executable, atomically: true, encoding: .utf8)
	try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: executable.path)
	let integration = try makeFixtureIntegration(at: root.appendingPathComponent("integration"))
	try FileManager.default.setAttributes(
		[.posixPermissions: 0o700], ofItemAtPath: integration.webClient.path)
	let runtime = PiRPCProcess(
		executable: executable,
		integrationCatalog: integration.catalog, integrationRootURL: integration.root)
	_ = try await runtime.start(
		agentID: "chat", in: root,
		sessionFile: root.appendingPathComponent(".pi/sessions/test.jsonl"), title: "Just chat",
		firstRequest: firstRequest)
	let captured = root.appendingPathComponent("arguments.txt")
	for _ in 0..<100 where !FileManager.default.fileExists(atPath: captured.path) {
		try await Task.sleep(for: .milliseconds(10))
	}
	let arguments = try String(contentsOf: captured, encoding: .utf8).split(separator: "\n").map(
		String.init)
	#expect(arguments.contains("--no-extensions"))
	#expect(arguments.contains("--no-context-files"))
	#expect(arguments.contains("--extension"))
	#expect(arguments.prefix(2) == ["--mode", "rpc"])
	#expect(arguments.contains("--no-skills"))
	#expect(arguments.contains("--no-prompt-templates"))
	#expect(arguments.contains(integration.parallelExtension.path))
	#expect(!arguments.contains(integration.webExtension.path))
	#expect(!arguments.contains(integration.nameExtension.path))
	#expect(!arguments.contains("--no-tools"))
	let toolsIndex = try #require(arguments.firstIndex(of: "--tools"))
	#expect(arguments[toolsIndex + 1] == "codemode")
	#expect(arguments.contains("--system-prompt"))
	#expect(await runtime.stop())
}

@MainActor @Test func isolatedRuntimeHonorsConfiguredResourceBoundaries() async throws {
	let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
	defer { try? FileManager.default.removeItem(at: root) }
	let project = root.appendingPathComponent("project")
	let sessions = root.appendingPathComponent("sessions")
	let output = root.appendingPathComponent("output")
	try FileManager.default.createDirectory(at: project, withIntermediateDirectories: true)
	let executable = root.appendingPathComponent("fixture-pi")
	try
		"#!/bin/sh\nprintf '%s\\n' \"$@\" > arguments.txt\nprintf '%s\\n%s\\n' \"$RESOURCE_TOKEN\" \"$MAC_APPER_OUTPUT_ROOT\" > environment.txt\nwhile IFS= read -r line; do printf '%s\\n' '{\"type\":\"message_update\",\"assistantMessageEvent\":{\"type\":\"text_delta\",\"delta\":\"fixture\"}}' '{\"type\":\"agent_end\",\"messages\":[],\"willRetry\":false}' '{\"type\":\"agent_settled\",\"aborted\":false}'; done\n"
		.write(to: executable, atomically: true, encoding: .utf8)
	try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: executable.path)
	let runtime = PiRPCProcess(
		configuration: .init(
			executable: executable,
			sessionDirectory: sessions,
			outputRoot: output,
			environment: ["RESOURCE_TOKEN": "isolated"],
			inheritsParentEnvironment: false,
			provider: "fixture-provider",
			model: "fixture-model",
			thinking: "minimal",
			tools: [],
			extensions: [],
			systemPrompt: "Scenario only",
			loadsSkills: false,
			loadsPromptTemplates: false,
			loadsThemes: false,
			loadsContextFiles: false,
			approvesProjectFiles: false,
			offline: true,
			telemetryEnabled: false,
			usesIntegrationCatalog: false,
			startsProviderServices: false,
			eventBufferLimit: 8,
			standardErrorByteLimit: 1_024,
			abortGraceMilliseconds: 1,
			terminationPollMilliseconds: 1,
			terminationPollCount: 10))
	let session = sessions.appendingPathComponent("scenario.jsonl")
	let events = try await runtime.start(
		agentID: "chat", in: project, sessionFile: session, title: "Scenario", firstRequest: false)
	try await runtime.prompt("hello")
	var received: [PiRPCEvent] = []
	for try await event in events {
		received.append(event)
		if case .settled = event { break }
	}
	#expect(
		received == [
			.response(id: nil, command: "prompt", success: true, error: nil), .textDelta("fixture"),
			.settled,
		]
			|| received == [.textDelta("fixture"), .settled])
	let arguments = try String(
		contentsOf: project.appendingPathComponent("arguments.txt"), encoding: .utf8)
	#expect(arguments.contains("--session-dir\n\(sessions.path)"))
	#expect(arguments.contains("--provider\nfixture-provider"))
	#expect(arguments.contains("--model\nfixture-model"))
	#expect(arguments.contains("--thinking\nminimal"))
	#expect(arguments.contains("--no-tools"))
	#expect(arguments.contains("--no-extensions"))
	#expect(arguments.contains("--no-skills"))
	#expect(arguments.contains("--no-prompt-templates"))
	#expect(arguments.contains("--no-themes"))
	#expect(arguments.contains("--no-context-files"))
	#expect(arguments.contains("--no-approve"))
	#expect(arguments.contains("--offline"))
	#expect(arguments.contains("--system-prompt\nScenario only"))
	let environment = try String(
		contentsOf: project.appendingPathComponent("environment.txt"), encoding: .utf8)
	#expect(environment == "isolated\n\(output.path)\n")
	#expect(FileManager.default.fileExists(atPath: sessions.path))
	#expect(await runtime.stop())
}

@MainActor @Test func ephemeralRuntimeUsesNoSessionAndCreatesNoSessionStorage() async throws {
	let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
	defer { try? FileManager.default.removeItem(at: root) }
	let project = root.appendingPathComponent("project")
	let sessions = root.appendingPathComponent("sessions")
	try FileManager.default.createDirectory(at: project, withIntermediateDirectories: true)
	let executable = root.appendingPathComponent("fixture-pi")
	try
		"#!/bin/sh\nprintf '%s\\n' \"$@\" > arguments.txt\nwhile IFS= read -r line; do printf '%s\\n' '{\"type\":\"response\",\"command\":\"prompt\",\"success\":true}' '{\"type\":\"agent_end\"}' '{\"type\":\"agent_settled\",\"aborted\":false}'; done\n"
		.write(to: executable, atomically: true, encoding: .utf8)
	try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: executable.path)
	let runtime = PiRPCProcess(
		configuration: .init(
			executable: executable, sessionDirectory: sessions, persistsSessions: false, tools: [],
			extensions: [], usesIntegrationCatalog: false, startsProviderServices: false))
	let events = try await runtime.start(in: project)
	try await runtime.prompt("hello")
	for try await event in events where event == .settled { break }

	let arguments = try String(
		contentsOf: project.appendingPathComponent("arguments.txt"), encoding: .utf8)
	#expect(arguments.contains("--no-session"))
	#expect(!arguments.contains("--session-dir"))
	#expect(!arguments.contains("--session\n"))
	#expect(!FileManager.default.fileExists(atPath: sessions.path))
	#expect(await runtime.stop())
}

@Test(arguments: ["Agent/Extensions", "Resources/AgentExtensions"])
func chatAuthoredExtensionResolvesWithoutWebOnFirstAndLaterRequests(directory: String) throws {
	let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
	defer { try? FileManager.default.removeItem(at: root) }
	let extensions = root.appendingPathComponent(directory)
	try FileManager.default.createDirectory(at: extensions, withIntermediateDirectories: true)
	let parallel = extensions.appendingPathComponent("parallel-codemode.ts")
	try Data().write(to: parallel)
	let file = root.appendingPathComponent("catalog.json")
	try Data("{\"schemaVersion\":1,\"apps\":[]}".utf8).write(to: file)
	let catalog = try AgentIntegrationCatalog.load(from: file)
	for first in [true, false] {
		let chat = try catalog.configuration(agentID: "chat", firstRequest: first, root: root)
		#expect(chat.extensionURLs == [parallel])
		#expect(chat.tools == ["codemode"])
		#expect(chat.applications.isEmpty)
	}
	try FileManager.default.removeItem(at: parallel)
	#expect(throws: AgentIntegrationCatalog.CatalogError.missingExtension) {
		try catalog.configuration(agentID: "chat", firstRequest: false, root: root)
	}
}

@Test func createInstructionsLoadOnFirstAndLaterRequestsButNeverChat() throws {
	let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
	defer { try? FileManager.default.removeItem(at: root) }
	let integration = try makeFixtureIntegration(at: root)
	try Data().write(to: root.appendingPathComponent("Agent/Extensions/create-instructions.ts"))
	for first in [true, false] {
		let configuration = try integration.catalog.configuration(
			agentID: "create", firstRequest: first, root: root)
		#expect(configuration.extensionURLs.map(\.lastPathComponent).contains("create-instructions.ts"))
	}
	let chat = try integration.catalog.configuration(agentID: "chat", firstRequest: false, root: root)
	#expect(!chat.extensionURLs.map(\.lastPathComponent).contains("create-instructions.ts"))
}

@Test func createNameHooksBelongToAgentRatherThanDevTools() throws {
	let package = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
		.deletingLastPathComponent().deletingLastPathComponent()
	#expect(
		FileManager.default.isReadableFile(
			atPath: package.appendingPathComponent("Extensions/name-and-rename.ts").path))
	#expect(
		FileManager.default.isReadableFile(
			atPath: package.appendingPathComponent("Extensions/create-app.ts").path))
	let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
	defer { try? FileManager.default.removeItem(at: root) }
	let catalog = try makeFixtureIntegration(at: root).catalog
	let create = try catalog.configuration(agentID: "create", firstRequest: true, root: root)
	#expect(create.extensionURLs.map(\.lastPathComponent).contains("name-and-rename.ts"))
	let later = try catalog.configuration(agentID: "create", firstRequest: false, root: root)
	#expect(!later.extensionURLs.map(\.lastPathComponent).contains("create-app.ts"))
}

@Test func catalogUsesBundledProviderExtensionsAndNeverAGeneratedSourceFallback() throws {
	let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
	defer { try? FileManager.default.removeItem(at: root) }
	let integration = try makeFixtureIntegration(at: root)
	let chat = try integration.catalog.configuration(
		agentID: "chat", firstRequest: false, root: root)
	let create = try integration.catalog.configuration(
		agentID: "create", firstRequest: true, root: root)
	#expect(chat.extensionURLs == [integration.parallelExtension])
	#expect(
		create.extensionURLs == [
			integration.parallelExtension, integration.instructionsExtension, integration.nameExtension,
			integration.createExtension, integration.devToolsExtension,
		])
	#expect(create.extensionURLs.prefix(4).allSatisfy { $0.path.contains("/Agent/Extensions/") })
	try FileManager.default.removeItem(at: integration.devToolsExtension)
	#expect(throws: AgentIntegrationCatalog.CatalogError.self) {
		try integration.catalog.configuration(agentID: "create", firstRequest: false, root: root)
	}
	#expect(
		try integration.catalog.configuration(agentID: "chat", firstRequest: false, root: root)
			.extensionURLs == [integration.parallelExtension])
}

@Test func catalogComposesChatAndCreateWithoutCoreProviderLists() throws {
	let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
	defer { try? FileManager.default.removeItem(at: root) }
	let catalog = try makeFixtureIntegration(at: root).catalog
	let chat = try catalog.configuration(agentID: "chat", firstRequest: false, root: root)
	#expect(chat.extensionURLs.map(\.lastPathComponent) == ["parallel-codemode.ts"])
	#expect(chat.tools == ["codemode"])
	#expect(chat.applications.isEmpty)

	let firstCreate = try catalog.configuration(agentID: "create", firstRequest: true, root: root)
	#expect(
		firstCreate.extensionURLs.map(\.lastPathComponent) == [
			"parallel-codemode.ts", "create-instructions.ts", "name-and-rename.ts", "create-app.ts",
			"Extension.ts",
		])
	#expect(firstCreate.tools.contains("build"))
	#expect(firstCreate.tools.contains("test"))
	#expect(firstCreate.tools.contains("set_app_name"))
	#expect(!firstCreate.tools.contains("search"))
	#expect(firstCreate.tools.contains("codemode"))
	#expect(firstCreate.extensionURLs.map(\.lastPathComponent).contains("parallel-codemode.ts"))

	let laterCreate = try catalog.configuration(agentID: "create", firstRequest: false, root: root)
	#expect(!laterCreate.extensionURLs.map(\.lastPathComponent).contains("create-app.ts"))
}

@Test func agentConfigurationsAreDeclaredInApplicationWithoutSpecGeneration() {
	#expect(PiRPCProcess.availableAgents.map(\.id) == ["chat", "create"])
	#expect(PiRPCProcess.availableAgents[0].appIDs.isEmpty)
	#expect(PiRPCProcess.availableAgents[0].baseTools.isEmpty)
	#expect(PiRPCProcess.availableAgents[1].appIDs == ["dev-tools"])
	#expect(
		PiRPCProcess.availableAgents[1].baseTools == ["read", "edit", "write", "grep", "find", "ls"])
	let manifest = try? String(
		contentsOf: URL(fileURLWithPath: #filePath)
			.deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
			.appendingPathComponent("Package.swift"), encoding: .utf8)
	#expect(manifest?.contains("AgentBuildPlugin") == false)
	#expect(manifest?.contains("AgentBuildTool") == false)
	let definition = try? String(
		contentsOf: URL(fileURLWithPath: #filePath)
			.deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
			.appendingPathComponent("Sources/Application/AgentPresetDescriptor.swift"), encoding: .utf8)
	#expect(definition?.contains("protocol AgentPresetSpec") == false)
}

@Test func fixedAgentConfigurationsAreAvailableForHostListing() {
	#expect(PiRPCProcess.availableAgents.map(\.id) == ["chat", "create"])
	#expect(PiRPCProcess.availableAgents.map(\.displayName) == ["Chat", "Create"])
	#expect(AgentCatalog.descriptors.map(\.id) == ["chat", "create"])
}

@Test func appCatalogAllowsProvidersWithoutAnXPCService() throws {
	let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
	defer { try? FileManager.default.removeItem(at: root) }
	_ = try makeFixtureIntegration(at: root)
	let extensions = root.appendingPathComponent("provider/PiExtension")
	try FileManager.default.createDirectory(at: extensions, withIntermediateDirectories: true)
	try Data().write(to: extensions.appendingPathComponent("provider.ts"))
	let object: [String: Any] = [
		"schemaVersion": 1,
		"apps": [
			[
				"id": "dev-tools", "packagePath": "provider",
				"application": [
					"bundleName": "Provider.app", "executableProduct": "ProviderApp",
					"infoPlist": "Resources/Info.plist",
				],
				"piExtensions": [
					[
						"path": "PiExtension/provider.ts", "agents": ["create"],
						"tools": ["lookup"], "firstRequestOnly": false,
					]
				],
			]
		],
		"agents": [
			[
				"id": "chat", "apps": ["provider"], "baseTools": [], "systemPrompt": "Chat",
			]
		],
	]
	let catalogURL = root.appendingPathComponent("catalog.json")
	try JSONSerialization.data(withJSONObject: object).write(to: catalogURL)
	let catalog = try AgentIntegrationCatalog.load(from: catalogURL)
	let configuration = try catalog.configuration(agentID: "create", firstRequest: false, root: root)
	#expect(configuration.applications.isEmpty)
	#expect(configuration.tools.contains("lookup"))
	#expect(configuration.extensionURLs.contains(extensions.appendingPathComponent("provider.ts")))
}
