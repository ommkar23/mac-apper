import Foundation
import OpenXPCSpecification
import Testing

private let projectRoot = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
	.deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()

@Test func consolidatedBuildPluginUsesControllerDispatch() throws {
	let main = try String(
		contentsOf: projectRoot.appendingPathComponent(
			"OpenXPCGenerator/Sources/OpenXPCGenerator/main.swift"), encoding: .utf8)
	#expect(main.contains("serviceDispatch: .controllers"))
	let plugin = try String(contentsOf: projectRoot.appendingPathComponent(
		"OpenXPCGenerator/Plugins/OpenXPCBuildPlugin/plugin.swift"), encoding: .utf8)
	#expect(plugin.contains("OpenXPCGen.yaml"))
	#expect(plugin.contains("target.directoryURL.appendingPathComponent(\"OpenXPC.specpath\")"))
	#expect(!plugin.contains("target.directory.string"))
	#expect(plugin.contains("inputFiles: inputs + [spec, generation]"))
	// Swift Build plans commands before building their executable dependencies.
	#expect(!plugin.contains("query.run()"))
	#expect(plugin.contains("outputFiles: [output, extensionFile]"))
	#expect(
		!FileManager.default.fileExists(
			atPath: projectRoot.appendingPathComponent(
				"OpenXPCGeneratorV2/Package.swift"
			).path))
}

@Test func generatorEmitsControllerRoutingWithoutChangingExplicitHandlerMode() throws {
	let yaml = try String(
		contentsOf: projectRoot.appendingPathComponent(
			"apps/built-in/dev-tools/OpenXPC.yaml"), encoding: .utf8)
	let generation = try String(
		contentsOf: projectRoot.appendingPathComponent(
			"apps/built-in/dev-tools/OpenXPCGen.yaml"), encoding: .utf8)
	let spec = try OpenXPCSpecification(contractYAML: yaml, generationYAML: generation)
	let controllers = try OpenXPCSourceGenerator.generate(
		spec: spec, target: "DevToolsApplication", serviceDispatch: .controllers
	).swift
	for name in ["Build", "Run", "Preview", "Plan"] {
		#expect(controllers.contains("public protocol OpenXPC\(name)Controller: Sendable"))
	}
	#expect(controllers.contains("public struct Controllers: Sendable"))
	#expect(controllers.contains("listen(controllers: Controllers)"))
	#expect(
		controllers.contains("controllers.build.handle(request.projectID, request.sessionID, value)"))
	#expect(!controllers.contains("public struct Handlers:"))
	let legacy = try OpenXPCSourceGenerator.generate(
		spec: spec, target: "DevToolsApplication", serviceDispatch: .handlers
	).swift
	#expect(legacy.contains("public struct Handlers: Sendable"))
	#expect(legacy.contains("handlers.build(request.projectID, request.sessionID, value)"))
}

@Test func generatorEmitsV5OperationAndSubscriptionControllers() throws {
	let yaml = try String(
		contentsOf: projectRoot.appendingPathComponent("Agent/OpenXPC.yaml"), encoding: .utf8)
	let generation = try String(
		contentsOf: projectRoot.appendingPathComponent("Agent/OpenXPCGen.yaml"), encoding: .utf8)
	let spec = try OpenXPCSpecification(contractYAML: yaml, generationYAML: generation)
	#expect(spec.subscriptions.map(\.name) == ["sessionEvents"])
	let controllers = try OpenXPCSourceGenerator.generate(
		spec: spec, target: "AgentApplication", serviceDispatch: .controllers
	).swift
	#expect(controllers.contains("public protocol OpenXPCStartSessionController: Sendable"))
	#expect(controllers.contains("public protocol OpenXPCSessionEventsController: Sendable"))
	#expect(controllers.contains("public struct Controllers: Sendable"))
	#expect(controllers.contains("listen(controllers: Controllers)"))
	#expect(
		controllers.contains(
			"controllers.startSession.handle(request.projectID, request.sessionID, value)"))
	#expect(controllers.contains("controllers.sessionEvents.handle("))
	#expect(controllers.contains("value, emitter)"))
	#expect(controllers.contains("guard claim({ emitter.disconnected() })"))
	#expect(controllers.contains("connection.invalidationHandler ="))
	#expect(controllers.contains("connection.interruptionHandler ="))
	#expect(!controllers.contains("public struct Handlers:"))
	let legacy = try OpenXPCSourceGenerator.generate(
		spec: spec, target: "AgentApplication", serviceDispatch: .handlers
	).swift
	#expect(legacy.contains("public struct Handlers: Sendable"))
	#expect(legacy.contains("handlers.sessionEvents("))
	#expect(!legacy.contains("public struct Controllers:"))
	let client = try OpenXPCSourceGenerator.generate(
		spec: spec, target: "AgentMacosClientModel", serviceDispatch: .controllers
	).swift
	#expect(client.contains("subscribeSessionEvents("))
	#expect(!client.contains("public struct Controllers:"))
	let legacyClient = try OpenXPCSourceGenerator.generate(
		spec: spec, target: "AgentMacosClientModel"
	).swift
	#expect(client == legacyClient)
}
