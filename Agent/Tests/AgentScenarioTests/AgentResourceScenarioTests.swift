// @frontmatter:start
// Verifies no-model native Agent XPC project preparation and scaffold resource bytes in an isolated signed test host.
// @frontmatter:end
import AgentMacosClient
import AgentMacosClientModel
import Darwin
import Foundation
import Scenario
import Testing

private final class ResourceTestBundleAnchor: NSObject {}

@Test(.enabled(if: ProcessInfo.processInfo.environment["AGENT_RESOURCE_SCENARIO"] == "1"))
@MainActor func agentBundledResourceScenario() async throws {
	let environment = ProcessInfo.processInfo.environment
	if environment["AGENT_RESOURCE_TEST_HOST"] == "1" {
		let home = URL(fileURLWithPath: try #require(environment["AGENT_RESOURCE_HOME"]))
		let expectedRoot = home.appendingPathComponent(".mac-apper")
		let adapter = AgentServiceXPCAdapter()
		let store = AgentXPCWorkspaceStore(transport: adapter)
		let model = WorkspaceSession(
			runtime: AgentXPCRuntime(transport: adapter), workspaceStore: store)
		await model.refreshLibrary()
		print("RESOURCE_HOME: \(expectedRoot.resolvingSymlinksInPath().path)")
		for group in model.library {
			print(
				"RESOURCE_LIBRARY: \(group.project.path), chat=\(group.isChatOnly), sessions=\(group.sessions.count)"
			)
		}
		try #require(
			model.library.allSatisfy {
				$0.project.deletingLastPathComponent().resolvingSymlinksInPath().path
					== expectedRoot.resolvingSymlinksInPath().path
					&& $0.isChatOnly && $0.sessions.isEmpty
			}, "Service must use the empty test-owned home")
		try #require(!model.activity.hasPrefix("Could not"), "Native workspace XPC read failed")
		print("RESOURCE_SMOKE: native workspace library XPC succeeded")
		try resourceServiceIdentity()
		let prepared = try await store.prepareCreateProject(request: "Offline resource smoke fixture")
		try #require(
			prepared.project.deletingLastPathComponent().resolvingSymlinksInPath().path
				== expectedRoot.resolvingSymlinksInPath().path)
		try #require(UUID(uuidString: prepared.project.lastPathComponent) != nil)
		defer { try? FileManager.default.removeItem(at: prepared.project) }
		try #require(prepared.isNew && prepared.creatingApp)
		try #require(
			String(
				contentsOf: prepared.project.appendingPathComponent("Scaffold.version"), encoding: .utf8)
				== "9")
		let persistence = try String(
			contentsOf: prepared.project.appendingPathComponent("Sources/AppModel/Persistence.swift"),
			encoding: .utf8)
		try #require(
			persistence.contains("schema.entities = []") && persistence.contains("CoreData/data.sqlite"))
		print("RESOURCE_V8: empty programmatic Core Data schema and UUID SQLite path")
		try #require(!FileManager.default.fileExists(atPath: prepared.sessionFile.path))
		let resources = Bundle.main.bundleURL.appendingPathComponent(
			"Contents/Resources/Agent_AgentApplication.bundle")
		let bundle = try #require(Bundle(url: resources))
		for (name, ext, subdirectory, relative) in [
			("AnimationIntent", "swift", nil, "Sources/AppModel/AnimationIntent.swift"),
			("PreviewProtocol", "swift", nil, "Sources/PreviewContract/PreviewProtocol.swift"),
			(
				"GeneratedAppXPCService", "swift.txt", "DevExtension",
				"Sources/DevExtension/GeneratedAppXPCService.swift"
			),
		] {
			let source = try #require(
				bundle.url(forResource: name, withExtension: ext, subdirectory: subdirectory))
			#expect(
				try Data(contentsOf: prepared.project.appendingPathComponent(relative))
					== Data(contentsOf: source))
		}
		await model.openProject(prepared.project)
		#expect(model.project == prepared.project)
		#expect(model.sessions.isEmpty)
		#expect(!model.connected)
		print("RESOURCE_SMOKE: service prepared scaffold from all three bundled resources; no Pi start")
		if let path = environment["AGENT_RESOURCE_EXPORT_DIRECTORY"] {
			let directory = URL(fileURLWithPath: path)
			let values = try directory.resourceValues(forKeys: [.isDirectoryKey, .isSymbolicLinkKey])
			try #require(
				directory.deletingLastPathComponent() == ProjectTemporaryDirectory.root()
					&& directory.lastPathComponent.hasPrefix("mac-apper-coredata-task6-")
					&& values.isDirectory == true && values.isSymbolicLink != true)
			let exported = directory.appendingPathComponent(prepared.project.lastPathComponent)
			try FileManager.default.createDirectory(at: exported, withIntermediateDirectories: false)
			for name in [
				"Sources", "Tests", "Package.swift", "Package.resolved", "Scaffold.version",
				"app-manifest.json", ".gitignore",
			] {
				try FileManager.default.copyItem(
					at: prepared.project.appendingPathComponent(name),
					to: exported.appendingPathComponent(name))
			}
			print("RESOURCE_EXPORTED_SOURCE: \(exported.path)")
		}
	} else {
		let home = try ProjectTemporaryDirectory.root()
			.appendingPathComponent("mac-apper-resource-home-\(UUID().uuidString)")
		try FileManager.default.createDirectory(
			at: home, withIntermediateDirectories: false, attributes: [.posixPermissions: 0o700])
		var cleaned = false
		defer {
			if cleaned {
				try? FileManager.default.removeItem(at: home)
			} else {
				print("RESOURCE_RETAINED_HOME: \(home.path)")
			}
		}
		try FileManager.default.createDirectory(
			at: home.appendingPathComponent(".mac-apper"), withIntermediateDirectories: false,
			attributes: [.posixPermissions: 0o700])
		let host = try AgentResourceScenarioInputs.prepareHost(home: home)
		defer {
			do {
				try stopScaffoldService(
					host.app, relative: "AgentXPCService.xpc/Contents/MacOS/AgentApplication")
				try host.remove()
				cleaned = true
			} catch { Issue.record("Owned resource service cleanup failed: \(error)") }
		}
		print("RESOURCE_SMOKE_HOST: \(try #require(host.app).path)")
		let result = try host.runTest(
			filter: "^AgentScenarioTests.agentBundledResourceScenario",
			environment: ["AGENT_RESOURCE_TEST_HOST": "1", "AGENT_RESOURCE_HOME": home.path],
			timeoutSeconds: 90)
		print(result.output)
		try #require(result.output.contains("Test agentBundledResourceScenario() started."))
		try #require(result.status == 0, "Packaged no-model resource scenario failed")
	}
}

private func resourceServiceIdentity() throws {
	let service = Bundle.main.bundleURL.appendingPathComponent(
		"Contents/XPCServices/AgentXPCService.xpc/Contents/MacOS/AgentApplication")
	let process = Process()
	let output = Pipe()
	process.executableURL = URL(fileURLWithPath: "/bin/ps")
	process.arguments = ["-axww", "-o", "pid=,lstart="]
	process.standardOutput = output
	try process.run()
	let data = output.fileHandleForReading.readDataToEndOfFile()
	process.waitUntilExit()
	try #require(process.terminationStatus == 0 && data.count <= 1_048_576)
	let identities = String(decoding: data, as: UTF8.self).split(separator: "\n").compactMap {
		line -> String? in
		guard
			let first = line.split(separator: " ").first,
			let pid = Int32(first)
		else { return nil }
		var buffer = [UInt8](repeating: 0, count: 4096)
		let length = buffer.withUnsafeMutableBufferPointer {
			proc_pidpath(pid, $0.baseAddress, 4096)
		}
		guard
			length > 0,
			length <= 4096
		else { return nil }
		let path = String(decoding: buffer.prefix(Int(length)).prefix { $0 != 0 }, as: UTF8.self)
		guard
			URL(fileURLWithPath: path).resolvingSymlinksInPath().path
				== service.resolvingSymlinksInPath().path
		else { return nil }
		return "\(line) \(path)"
	}
	try #require(identities.count == 1, "Expected exactly one task-owned bundled Agent service")
	print("RESOURCE_SERVICE_IDENTITY: \(identities[0])")
}

@MainActor enum AgentResourceScenarioInputs {
	static func prepareHost(home: URL) throws -> PackagedTestHost {
		let package = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
			.deletingLastPathComponent().deletingLastPathComponent()
		let environment = ProcessInfo.processInfo.environment
		let products =
			environment["AGENT_SCENARIO_PRODUCTS"].map { URL(fileURLWithPath: $0) }
			?? package.appendingPathComponent(".build/debug")
		let deployed = environment["AGENT_RESOURCE_APP"].map { URL(fileURLWithPath: $0) }
		let service = deployed?.appendingPathComponent("Contents/XPCServices/AgentXPCService.xpc")
		let executable =
			service?.appendingPathComponent("Contents/MacOS/AgentApplication")
			?? products.appendingPathComponent("AgentApplication")
		let plist =
			service?.appendingPathComponent("Contents/Info.plist")
			?? package.appendingPathComponent("Resources/AgentXPCService-Info.plist")
		let resources =
			deployed?.appendingPathComponent("Contents/Resources/Agent_AgentApplication.bundle")
			?? products.appendingPathComponent("Agent_AgentApplication.bundle")
		let tests = try #require(Bundle(for: ResourceTestBundleAnchor.self).executableURL)
		return try PackagedTestHost.withInputDirectory { inputs in
			var info = try #require(
				PropertyListSerialization.propertyList(from: Data(contentsOf: plist), format: nil)
					as? [String: Any])
			var xpc = try #require(info["XPCService"] as? [String: Any])
			xpc["EnvironmentVariables"] = ["CFFIXED_USER_HOME": home.path, "HOME": home.path]
			info["XPCService"] = xpc
			let scopedPlist = inputs.appendingPathComponent("Agent.plist")
			try PropertyListSerialization.data(fromPropertyList: info, format: .xml, options: 0)
				.write(to: scopedPlist)
			let localResources =
				service?.appendingPathComponent(
					"Contents/Resources/Agent_AgentApplication.bundle") ?? resources
			let serviceResources: [TestHostResource] =
				if FileManager.default.fileExists(atPath: localResources.path) {
					[TestHostResource(source: localResources, relativePath: "Agent_AgentApplication.bundle")]
				} else { [] }
			let host = PackagedTestHost(
				testBundleExecutable: tests, loader: try PackagedTestHost.swiftPMTestLoader(),
				services: [
					TestHostService(
						bundleName: "AgentXPCService.xpc", executable: executable, infoPlist: scopedPlist,
						resources: serviceResources)
				], applications: [],
				resources: [
					TestHostResource(source: resources, relativePath: "Agent_AgentApplication.bundle")
				])
			try host.prepare()
			return host
		}
	}
}
