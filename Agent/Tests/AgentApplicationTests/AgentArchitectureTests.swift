// @frontmatter:start
// Checks Agent package layout, packaging boundaries, and required architecture contracts.
// @frontmatter:end
import Foundation
import Testing

private let packageRoot = URL(fileURLWithPath: #filePath)
	.deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()

@Test func scaffoldV8GuidanceAndCompositionStayAligned() throws {
	let root = packageRoot.deletingLastPathComponent()
	let base = try String(
		contentsOf: packageRoot.appendingPathComponent("Sources/Application/BaseAppTemplate.swift"),
		encoding: .utf8)
	let protected = try String(
		contentsOf: packageRoot.appendingPathComponent("Sources/Application/PreviewTemplate.swift"),
		encoding: .utf8)
	#expect(base.contains("public static let version = \"8\""))
	#expect(base.contains("files.merge(persistenceFiles)"))
	#expect(protected.contains("ApplicationModel.production(appID:"))
	#expect(protected.contains("private let model = ApplicationModel()"))
	#expect(!protected.contains("NSManagedObjectContext"))
	for editable in ["Persistence.swift", "ApplicationState.swift"] {
		#expect(!protected.contains("Sources/AppModel/\(editable)"))
	}
	let persistence = try String(
		contentsOf: packageRoot.appendingPathComponent(
			"Sources/Application/ScaffoldPersistenceTemplate.swift"), encoding: .utf8)
	#expect(persistence.contains("public static func makeSchema() -> NSManagedObjectModel"))
	#expect(persistence.contains("schema.versionIdentifiers = [\"application-1\"]"))
	#expect(persistence.contains("schema.entities = []"))
	let fixture = try String(
		contentsOf: packageRoot.appendingPathComponent(
			"Tests/AgentApplicationTests/ScaffoldPersistenceTests.swift"), encoding: .utf8)
	#expect(fixture.contains("@NSManaged"))
	#expect(!fixture.contains(".enabled(if:"))
	for path in ["README.md", "Agent/README.yaml", ".pi/skills/scenario-write/SKILL.md"] {
		let document = try String(contentsOf: root.appendingPathComponent(path), encoding: .utf8)
		#expect(document.contains("CoreData/data.sqlite"), "Missing UUID storage contract in \(path)")
		#expect(document.contains("makeSchema"), "Missing schema extension point in \(path)")
	}
	let skill = try String(
		contentsOf: root.appendingPathComponent(".pi/skills/scenario-write/SKILL.md"), encoding: .utf8)
	#expect(skill.contains("New projects use scaffold version 8"))
	#expect(!skill.contains("replacement remains unimplemented"))
	#expect(!skill.contains("pass the opt-in generated entity smoke test"))
}

@Test func testRunnerCleansItsScratchDirectory() throws {
	let root = packageRoot.deletingLastPathComponent()
	let manifest = try String(
		contentsOf: root.appendingPathComponent("Package.swift"), encoding: .utf8)
	let plugin = try String(
		contentsOf: root.appendingPathComponent(
			"Plugins/CleanTestPlugin/plugin.swift"), encoding: .utf8)
	#expect(manifest.contains("verb: \"clean-test\""))
	#expect(plugin.contains("defer { try? manager.removeItem(at: scratch) }"))
	#expect(plugin.contains("\"--scratch-path\", scratch.path"))
}

@Test func packagingStagesGeneratedArtifactsOutsideSourceTree() throws {
	let root = packageRoot.deletingLastPathComponent()
	let plugin = try String(
		contentsOf: root.appendingPathComponent(
			"Plugins/BundlePlugin/plugin.swift"), encoding: .utf8)
	#expect(plugin.contains("build.appendingPathComponent(\"generated\")"))
	#expect(plugin.contains("generated.appendingPathComponent(\"IntegrationCatalog.json\")"))
	#expect(!plugin.contains("root.appendingPathComponent(\"Generated\")"))
	let catalog = try String(
		contentsOf: packageRoot.appendingPathComponent(
			"Sources/Application/AgentIntegrationCatalog.swift"), encoding: .utf8)
	#expect(!catalog.contains("Generated/PiExtensions"))
	#expect(!catalog.contains("Generated/IntegrationCatalog.json"))
}

@Test func clientModelDoesNotImportTheSharedAgentWireModule() throws {
	let manifest = try String(
		contentsOf: packageRoot.appendingPathComponent("Package.swift"), encoding: .utf8)
	#expect(manifest.contains("name: \"AgentMacosClientModel\", dependencies: []"))
	let model = packageRoot.appendingPathComponent("Sources/MacOSClient/Model")
	for file in try FileManager.default.contentsOfDirectory(
		at: model, includingPropertiesForKeys: nil)
	where file.pathExtension == "swift" {
		let source = try String(contentsOf: file, encoding: .utf8)
		#expect(!source.contains("import AgentXPC"))
	}
}

@Test func agentDeclaresOpenXPCV5ForServiceAndClientModelTargets() throws {
	let spec = try String(
		contentsOf: packageRoot.appendingPathComponent("OpenXPC.yaml"), encoding: .utf8)
	let generation = try String(
		contentsOf: packageRoot.appendingPathComponent("OpenXPCGen.yaml"), encoding: .utf8)
	let manifest = try String(
		contentsOf: packageRoot.appendingPathComponent("Package.swift"), encoding: .utf8)
	#expect(!spec.contains("schemaVersion:"))
	#expect(spec.contains("identifier: com.macapper.AgentXPCService"))
	for name in [
		"listPresets", "startSession", "promptSession", "sessionHistory", "abortSession", "stopSession",
		"workspace",
	] {
		#expect(spec.contains("name: \(name)"))
	}
	#expect(spec.contains("name: sessionEvents"))
	#expect(!spec.contains("type: data"))
	for type in [
		"AgentPresetRecord", "AgentEventRecord", "SessionEventBatch", "WorkspaceLibraryRecord",
		"WorkspaceRequest", "WorkspaceResponse",
	] {
		#expect(spec.contains("name: \(type)"))
	}
	#expect(!spec.contains("target:"))
	#expect(generation.contains("target: AgentApplication"))
	#expect(generation.contains("target: AgentMacosClientModel"))
	#expect(
		generation.contains(
			"operations: [startSession, promptSession, sessionHistory, abortSession, stopSession, workspace, prepareChatSession, prepareCreateProject, prepareCreateSession, resumeSession]"
		))
	#expect(!spec.contains("target: AgentMacosClient\n"))
	#expect(manifest.contains(".package(path: \"../OpenXPCGenerator\")"))
	#expect(!manifest.contains("OpenXPCGeneratorV2"))
	#expect(!manifest.contains("AgentBuildPlugin"))
	let applicationTarget = try #require(
		manifest.components(
			separatedBy: ".executableTarget(\n\t\t\tname: \"AgentApplication\","
		).dropFirst().first)
	#expect(
		applicationTarget.components(separatedBy: ".executableTarget(").first?
			.contains("OpenXPCBuildPlugin") == true)
	#expect(
		manifest.components(
			separatedBy: ".plugin(name: \"OpenXPCBuildPlugin\", package: \"OpenXPCGenerator\")"
		).count == 3)
	#expect(!generation.contains("target: AgentCountryScenarioClient"))
	#expect(!manifest.contains("AgentCountryScenarioClient"))
	#expect(
		!FileManager.default.fileExists(
			atPath: packageRoot.appendingPathComponent("Tests/AgentScenarioClient").path))
	#expect(!generation.contains("target: DirectAgentXPCScenario"))
	let modelTarget = try #require(
		manifest.components(separatedBy: "name: \"AgentMacosClientModel\"").dropFirst().first)
	#expect(
		modelTarget.components(separatedBy: ".executableTarget(").first?.contains("OpenXPCBuildPlugin")
			== true)
	let clientTarget = try #require(
		manifest.components(separatedBy: "name: \"AgentMacosClient\",\n").dropFirst().first)
	#expect(
		clientTarget.components(separatedBy: ".executableTarget(").first?.contains("OpenXPCBuildPlugin")
			== false)
}

@Test func agentOwnsBundledApplicationAndServiceMetadata() throws {
	let root = packageRoot.deletingLastPathComponent()
	let plugin = try String(
		contentsOf: root.appendingPathComponent(
			"Plugins/BundlePlugin/plugin.swift"), encoding: .utf8)
	for name in ["Info.plist", "AgentXPCService-Info.plist"] {
		let plist = packageRoot.appendingPathComponent("Resources/\(name)")
		#expect(FileManager.default.fileExists(atPath: plist.path))
		if name == "Info.plist" {
			#expect(plugin.contains("Bundles/app/Info.plist"))
		} else {
			#expect(plugin.contains("Agent/Resources/\(name)"))
		}
	}
	#expect(!FileManager.default.fileExists(atPath: root.appendingPathComponent("Resources").path))
}

@Test func sourceLayoutGroupsApplicationAndClient() throws {
	let root = packageRoot.appendingPathComponent("Sources")
	for path in [
		"Application/PiRPCProcess.swift",
		"Application/AgentOpenXPCService.swift",
		"Application/AgentApplicationMain.swift",
		"Application/AgentServiceManagers.swift",
		"Application/AppName.swift",
		"Application/Controllers/ControllerFactory.swift",
		"Application/Controllers/ListPresetsController.swift",
		"Application/Controllers/StartSessionController.swift",
		"Application/Controllers/PromptSessionController.swift",
		"Application/Controllers/SessionHistoryController.swift",
		"Application/Controllers/AbortSessionController.swift",
		"Application/Controllers/StopSessionController.swift",
		"Application/Controllers/WorkspaceController.swift",
		"Application/Controllers/PrepareChatSessionController.swift",
		"Application/Controllers/PrepareCreateProjectController.swift",
		"Application/Controllers/PrepareCreateSessionController.swift",
		"Application/Controllers/ResumeSessionController.swift",
		"Application/Controllers/SessionEventsController.swift",
		"MacOSClient/View/WorkspaceView.swift",
		"MacOSClient/Model/WorkspaceSession.swift",
		"MacOSClient/Model/WorkspacePresentation.swift",
		"MacOSClient/Model/AppModel.swift",
		"MacOSClient/Model/WorkspaceWire.swift",
		"MacOSClient/Model/AgentSessionWire.swift",
		"MacOSClient/Model/AgentXPCRuntime.swift",
		"MacOSClient/Model/AgentSessionRuntime.swift",
		"MacOSClient/Model/AgentXPCWorkspaceStore.swift",
		"MacOSClient/AgentServiceXPCAdapter.swift",
		"MacOSClient/AgentMacosClientMain.swift",

	] {
		#expect(FileManager.default.fileExists(atPath: root.appendingPathComponent(path).path))
	}
	#expect(
		FileManager.default.fileExists(
			atPath: root.appendingPathComponent("Application/AgentCatalog.swift").path))
	for name in ["chat", "create"] {
		#expect(
			!FileManager.default.fileExists(
				atPath: packageRoot.deletingLastPathComponent()
					.appendingPathComponent("agents/built-in/\(name)/AgentSpec.swift").path))
	}
}

@Test func testTargetsSeparateUnitAndCrossTargetCoverage() throws {
	let manifest = try String(
		contentsOf: packageRoot.appendingPathComponent("Package.swift"), encoding: .utf8)
	func dependencies(of name: String) throws -> String {
		let marker = "name: \"\(name)\",\n\t\t\tdependencies: ["
		let range = try #require(manifest.range(of: marker))
		return String(manifest[range.upperBound...].prefix(while: { $0 != "]" }))
	}
	let application = try dependencies(of: "AgentApplicationTests")
	let model = try dependencies(of: "AgentMacosClientModelTests")
	let client = try dependencies(of: "AgentMacosClientTests")
	let combined = try dependencies(of: "AgentTests")
	#expect(application.contains("\"AgentApplication\""))
	#expect(!application.contains("\"AgentMacosClient\""))
	#expect(model.contains("\"AgentMacosClientModel\""))
	#expect(!model.contains("\"AgentApplication\""))
	#expect(client.contains("\"AgentMacosClient\""))
	#expect(!client.contains("\"AgentApplication\""))
	#expect(!client.contains("\"AgentMacosClientModel\""))
	for target in [
		"AgentApplication", "AgentMacosClient", "AgentMacosClientModel", "PreviewContract",
		"PortableAnimation",
	] {
		#expect(combined.contains("\"\(target)\""))
	}
	for oldName in ["AgentArchitectureTests", "AgentXPCServiceTests"] {
		#expect(!manifest.contains("name: \"\(oldName)\""))
	}
}

@Test func unitTestSourcesDoNotImportOtherOwnershipTargets() throws {
	for (target, forbidden) in [
		("AgentApplicationTests", ["AgentMacosClient", "AgentMacosClientModel"]),
		("AgentMacosClientModelTests", ["AgentApplication", "AgentMacosClient"]),
		("AgentMacosClientTests", ["AgentApplication"]),
	] {
		let directory = packageRoot.appendingPathComponent("Tests/\(target)")
		let files = try FileManager.default.contentsOfDirectory(
			at: directory, includingPropertiesForKeys: nil)
		for file in files where file.pathExtension == "swift" {
			let source = try String(contentsOf: file, encoding: .utf8)
			let imports = source.split(separator: "\n").map {
				$0.trimmingCharacters(in: .whitespaces)
			}.filter { $0.hasPrefix("import ") || $0.hasPrefix("@testable import ") }
			for module in forbidden {
				#expect(
					!imports.contains("import \(module)") && !imports.contains("@testable import \(module)"),
					"\(file.lastPathComponent) imports \(module)")
			}
		}
	}
}

@Test func generatedRecordsReplaceAuthoredWorkspaceSnapshotsAndSessionRequests() throws {
	for folder in ["Application", "MacOSClient/Model"] {
		let sourceRoot = packageRoot.appendingPathComponent("Sources/\(folder)")
		let workspace = try String(
			contentsOf: sourceRoot.appendingPathComponent("WorkspaceWire.swift"), encoding: .utf8)
		let session = try String(
			contentsOf: sourceRoot.appendingPathComponent("AgentSessionWire.swift"), encoding: .utf8)
		for oldType in [
			"WorkspaceMessageWire", "WorkspaceSessionWire", "WorkspaceAppWire",
			"WorkspaceGroupWire", "WorkspaceLibraryWire", "WorkspaceHistoryWire",
			"WorkspaceOpenWire", "WorkspacePreparedWire",
		] {
			#expect(!workspace.contains("struct \(oldType)"))
		}
		for oldType in [
			"AgentSessionStartRequest", "AgentSessionPromptRequest", "AgentSessionIdentifier",
			"AgentSessionPollRequest", "AgentSessionAttachment", "AgentServiceAcknowledgement",
		] {
			#expect(!session.contains("struct \(oldType)"))
		}
		#expect(session.contains("typealias AgentSessionStartRequest = StartSessionRequest"))
		#expect(workspace.contains("case library(WorkspaceLibraryRecord)"))
	}
}

@Test func packageUsesOnlyAgreedAgentTargetNames() throws {
	let manifest = try String(
		contentsOf: packageRoot.appendingPathComponent("Package.swift"), encoding: .utf8)
	#expect(manifest.contains("name: \"AgentApplication\""))
	#expect(!manifest.contains("name: \"AgentXPC\""))
	#expect(!manifest.contains(".library(name: \"AgentXPC\""))
	#expect(!manifest.contains("AgentAPI"))
	#expect(!manifest.contains(".library(name: \"ChatAgent\""))
	#expect(!manifest.contains(".library(name: \"CreateAgent\""))
	#expect(!manifest.contains("AgentSpecGenerator"))
	#expect(!manifest.contains("AgentSpecPlugin"))
}

@Test func agentPackageOwnsTheNativeClientBoundary() throws {
	let manifest = try String(
		contentsOf: packageRoot.appendingPathComponent("Package.swift"), encoding: .utf8)
	#expect(manifest.contains(".executable(name: \"AgentMacosClient\""))
	#expect(manifest.contains(".executableTarget(\n\t\t\tname: \"AgentMacosClient\""))
	#expect(!manifest.contains("AgentMacosClientApplication"))
	#expect(!manifest.contains("AgentMacosClientLibrary"))
	#expect(!manifest.contains("\"AgentXPC\""))
	#expect(manifest.contains("name: \"AgentApplication\""))

	let root = packageRoot.deletingLastPathComponent()
	#expect(
		!FileManager.default.fileExists(atPath: root.appendingPathComponent("App/Package.swift").path))
	#expect(
		!FileManager.default.fileExists(
			atPath: root.appendingPathComponent("MacApperModel/Package.swift").path))
}

@Test func clientPresentationAndServiceWireStaySeparate() throws {
	let manifest = try String(
		contentsOf: packageRoot.appendingPathComponent("Package.swift"), encoding: .utf8)
	#expect(!manifest.contains("AgentSharedModel"))
	#expect(manifest.contains("name: \"AgentMacosClientModel\", dependencies: []"))
	let shared = packageRoot.appendingPathComponent("Sources/AgentSharedModel")
	#expect(!FileManager.default.fileExists(atPath: shared.path))
	for path in [
		"Sources/Application/PiRPCProtocol.swift",
		"Sources/Application/WorkspaceStoreProtocol.swift",
		"Sources/MacOSClient/Model/WorkspaceStore.swift",
		"Sources/MacOSClient/Model/WorkspaceModels.swift",
		"Sources/Application/WorkspaceModels.swift",
	] {
		#expect(FileManager.default.fileExists(atPath: packageRoot.appendingPathComponent(path).path))
	}
	#expect(
		!FileManager.default.fileExists(
			atPath: packageRoot.appendingPathComponent(
				"Sources/AgentXPC"
			).path))
}

@Test func serviceDoesNotDependOnClientOwnedModel() throws {
	let manifest = try String(
		contentsOf: packageRoot.appendingPathComponent("Package.swift"), encoding: .utf8)
	let marker = "name: \"AgentApplication\",\n\t\t\tdependencies:"
	let application = try #require(manifest.components(separatedBy: marker).dropFirst().first)
	let dependencies = try #require(application.components(separatedBy: "]").first)
	#expect(!dependencies.contains("AgentMacosClientModel"))
	let sources = packageRoot.appendingPathComponent("Sources/Application")
	let files = try FileManager.default.contentsOfDirectory(
		at: sources, includingPropertiesForKeys: nil)
	for file in files where file.pathExtension == "swift" {
		let source = try String(contentsOf: file, encoding: .utf8)
		#expect(!source.contains("import AgentMacosClientModel"))
	}
}

@Test func nativeClientContainsModelAndViewsWithoutOwningServiceRuntime() throws {
	let manifest = try String(
		contentsOf: packageRoot.appendingPathComponent("Package.swift"), encoding: .utf8)
	#expect(manifest.contains("dependencies: [\"AgentMacosClientModel\"]"))

	let directory = packageRoot.appendingPathComponent("Sources/MacOSClient")
	let files = try FileManager.default.contentsOfDirectory(
		at: directory, includingPropertiesForKeys: nil)
	let source = try files.filter { $0.pathExtension == "swift" }
		.map { try String(contentsOf: $0, encoding: .utf8) }
		.joined(separator: "\n")
	#expect(source.contains("import AgentMacosClientModel"))
	let modelDirectory = directory.appendingPathComponent("Model")
	let modelFiles = try FileManager.default.contentsOfDirectory(
		at: modelDirectory, includingPropertiesForKeys: nil)
	let modelSource = try modelFiles.filter { $0.pathExtension == "swift" }
		.map { try String(contentsOf: $0, encoding: .utf8) }
		.joined(separator: "\n")
	#expect(modelSource.contains("@Observable"))
	#expect(modelSource.contains("class WorkspaceSession"))
	#expect(modelSource.contains("protocol AgentSessionRuntime"))
	#expect(!modelSource.contains("import AgentMacosClient\n"))
	#expect(
		!FileManager.default.fileExists(
			atPath: modelDirectory.appendingPathComponent("PiRPCProtocol.swift").path))
	let viewDirectory = directory.appendingPathComponent("View")
	let viewFiles = try FileManager.default.contentsOfDirectory(
		at: viewDirectory, includingPropertiesForKeys: nil)
	#expect(
		Set(viewFiles.map(\.lastPathComponent)) == [
			"WorkspaceView.swift", "DiagnosticsAccessView.swift",
		])
	let viewSource = try viewFiles.map { try String(contentsOf: $0, encoding: .utf8) }.joined(
		separator: "\n")
	#expect(viewSource.contains("WorkspaceView"))
	#expect(!viewSource.contains("AgentXPCServiceClient"))
	for forbidden in ["PiRPCProcess", "FileManager.default", "ProjectScaffold", "ChatSessionCatalog"]
	{
		#expect(!source.contains(forbidden))
	}
	#expect(!source.contains("import AgentApplication\n"))
	#expect(!source.contains("import AgentXPCService\n"))
}

@Test func productionIdentifiersDoNotUseLegacyMacApperName() throws {
	let manifest = try String(
		contentsOf: packageRoot.appendingPathComponent("Package.swift"), encoding: .utf8)
	#expect(!manifest.contains("MacApper"))

	let clientDirectory = packageRoot.appendingPathComponent("Sources/MacOSClient")
	if FileManager.default.fileExists(atPath: clientDirectory.path) {
		let files = try FileManager.default.contentsOfDirectory(
			at: clientDirectory, includingPropertiesForKeys: nil)
		let source = try files.filter { $0.pathExtension == "swift" }
			.map { try String(contentsOf: $0, encoding: .utf8) }
			.joined(separator: "\n")
		#expect(!source.contains("import MacApper"))
	}
}

@Test func agentPackageOwnsTheOnlyAgentServiceBoundary() throws {
	let manifest = try String(
		contentsOf: packageRoot.appendingPathComponent("Package.swift"), encoding: .utf8)
	#expect(
		manifest.contains(".executable(name: \"AgentApplication\", targets: [\"AgentApplication\"])"))
	#expect(manifest.contains(".executable(name: \"AgentApplication\""))
	#expect(!manifest.contains(".library(name: \"Agent\""))
	#expect(!manifest.contains(".library(name: \"AgentXPCService\""))
	#expect(!manifest.contains("AgentXPCServiceExecutable"))

	let legacyPackage = packageRoot.deletingLastPathComponent()
		.appendingPathComponent("AgentXPCService/Package.swift")
	#expect(!FileManager.default.fileExists(atPath: legacyPackage.path))
	let serviceDirectory = packageRoot.appendingPathComponent("Sources/Application")
	let serviceSource = try FileManager.default.contentsOfDirectory(
		at: serviceDirectory, includingPropertiesForKeys: nil
	)
	.filter { $0.pathExtension == "swift" }
	.map { try String(contentsOf: $0, encoding: .utf8) }
	.joined(separator: "\n")
	#expect(!serviceSource.contains("import AgentXPC\n"))
	#expect(serviceSource.contains("OpenXPCGeneratedService.listen(controllers:"))
	#expect(!serviceSource.contains("OpenXPCGeneratedService.Handlers"))
	#expect(!serviceSource.contains("AgentServiceClient"))
	#expect(!serviceSource.contains("AgentServiceXPCProtocol"))
}

@Test func agentOwnsPiRPCProcessAndAgentCatalog() throws {
	let source = try String(
		contentsOf: packageRoot.appendingPathComponent("Sources/Application/PiRPCProcess.swift"),
		encoding: .utf8)
	#expect(source.contains("final class PiRPCProcess"))
	#expect(source.contains("AgentCatalog"))

	let oldSource = packageRoot.deletingLastPathComponent()
		.appendingPathComponent("MacApperModel/Sources/MacApperHost/PiRPCProcess.swift")
	#expect(!FileManager.default.fileExists(atPath: oldSource.path))
}

@Test func agentDoesNotDeclareTheRetiredXPCModule() throws {
	let manifest = try String(
		contentsOf: packageRoot.appendingPathComponent("Package.swift"), encoding: .utf8)
	#expect(!manifest.contains(".library(name: \"AgentXPC\""))
	#expect(!manifest.contains(".target(name: \"AgentXPC\""))
	#expect(
		!FileManager.default.fileExists(
			atPath: packageRoot.appendingPathComponent(
				"Sources/AgentXPC"
			).path))
}

@Test func workspaceStoreInterfacesUseExplicitPreparationOperations() throws {
	for path in [
		"Sources/Application/WorkspaceStoreProtocol.swift",
		"Sources/MacOSClient/Model/WorkspaceStore.swift",
	] {
		let source = try String(contentsOf: packageRoot.appendingPathComponent(path), encoding: .utf8)
		for name in [
			"prepareChatSession", "prepareCreateProject", "prepareCreateSession", "resumeSession",
		] {
			#expect(source.contains("func \(name)("))
		}
		#expect(!source.contains("func prepareSession("))
		#expect(!source.contains("isChatOnly: Bool"))
	}
}

@Test func nativeClientDoesNotKeepAnAgentRequestEnvelope() throws {
	#expect(
		!FileManager.default.fileExists(
			atPath: packageRoot.appendingPathComponent(
				"Sources/MacOSClient/AgentXPCServiceWire.swift"
			).path))
	let transport = try String(
		contentsOf: packageRoot.appendingPathComponent(
			"Sources/MacOSClient/AgentServiceXPCAdapter.swift"), encoding: .utf8)
	#expect(!transport.contains("AgentXPCRequest"))
	#expect(!transport.contains("AgentXPCReply"))
	#expect(transport.contains("OpenXPCGeneratedClient"))
}

@Test func nativeClientUsesOneGeneratedXPCAdapter() throws {
	let client = packageRoot.appendingPathComponent("Sources/MacOSClient")
	for obsolete in ["AgentXPCServiceClient.swift", "GeneratedAgentXPCTransport.swift"] {
		#expect(!FileManager.default.fileExists(atPath: client.appendingPathComponent(obsolete).path))
	}
	#expect(
		!FileManager.default.fileExists(
			atPath: client.appendingPathComponent("Model/AgentOpenXPCClient.swift").path))
	let source = try String(
		contentsOf: client.appendingPathComponent("AgentServiceXPCAdapter.swift"),
		encoding: .utf8)
	#expect(source.contains("struct AgentServiceXPCAdapter"))
}

@Test func packagedAgentExecutableExposesStaticPresetQuery() throws {
	let source = try String(
		contentsOf: packageRoot.appendingPathComponent(
			"Sources/MacOSClient/AgentMacosClientMain.swift"),
		encoding: .utf8)
	#expect(source.contains("@main @MainActor enum AgentMacosClientMain"))
	#expect(source.contains("--service-presets"))
	#expect(source.contains("BuiltInAgentPresets.all"))
}

@Test func agentServiceUsesGeneratedOpenXPCListener() throws {
	let source = try String(
		contentsOf: packageRoot.appendingPathComponent(
			"Sources/Application/AgentXPCServiceMain.swift"), encoding: .utf8)
	#expect(source.contains("OpenXPCGeneratedService.listen(controllers:"))
	#expect(!source.contains("OpenXPCGeneratedService.listen(handlers:"))
	let factory = try String(
		contentsOf: packageRoot.appendingPathComponent(
			"Sources/Application/Controllers/ControllerFactory.swift"), encoding: .utf8)
	#expect(factory.contains("OpenXPCGeneratedService.Controllers"))
	#expect(factory.contains("sessionEvents:"))
	#expect(!source.contains("AgentXPCServiceListenerDelegate"))
	#expect(
		!FileManager.default.fileExists(
			atPath: packageRoot.appendingPathComponent(
				"Sources/Application/AgentXPCServiceDispatcher.swift"
			).path))
	#expect(
		!FileManager.default.fileExists(
			atPath: packageRoot.appendingPathComponent(
				"Sources/Application/AgentXPCServiceEndpoint.swift"
			).path))
}

@Test func xpcServiceStartsItsListenerBeforeEnteringTheMainDispatchLoop() throws {
	let source = try String(
		contentsOf: packageRoot.appendingPathComponent(
			"Sources/Application/AgentApplicationMain.swift"), encoding: .utf8)
	#expect(source.contains("@main @MainActor enum AgentApplicationMain"))
	#expect(!source.contains("Task { @MainActor"))
	#expect(!source.contains("dispatchMain()"))
}
