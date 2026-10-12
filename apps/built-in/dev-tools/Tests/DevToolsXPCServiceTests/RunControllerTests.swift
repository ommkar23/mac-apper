// @frontmatter:start
// Tests RunController development app staging, launch, and process cleanup.
// @frontmatter:end
import Foundation
import Testing

@testable import DevToolsApplication

@Test func runCanLaunchWithoutAnEndpointHandshake() async throws {
	let fixture = try LaunchFixture()
	defer { fixture.remove() }
	var environment = ProcessInfo.processInfo.environment
	environment["DEVTOOLS_LAUNCHED"] = fixture.launched.path
	let projects = ProjectResolver(projectsRoot: fixture.root)
	let gate = DevToolsOperationGate()
	let build = BuildController(
		projects: projects, gate: gate, outputLimitBytes: 4_096, environment: environment)
	let launcher = RunController(
		projects: projects, gate: gate, build: build, environment: environment)
	let result = try await launcher.run(
		project: fixture.approvedProject(), requestID: fixture.requestID)
	#expect(result.target == "ProductionApp")
	#expect(result.appBundle.path == fixture.expectedBundle.path)
	try await launcher.stopAll()
}

private struct LaunchFixture {
	let root: URL
	let projectID: String
	let sessionID = UUID().uuidString
	let requestID = UUID().uuidString.lowercased()
	let instanceID = UUID().uuidString.lowercased()
	let launched: URL

	var expectedBundle: URL {
		root.appendingPathComponent(
			"\(projectID)/.mac-apper/DevBuild/\(requestID)/ProductionApp.app")
	}

	init() throws {
		root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
		try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
		projectID = UUID().uuidString.lowercased()
		let projectRoot = root.appendingPathComponent(projectID)
		try FileManager.default.createDirectory(at: projectRoot, withIntermediateDirectories: true)
		try Data(
			"""
			{"schemaVersion":1,"appID":"\(projectID)","executableTarget":"ProductionApp","previewTarget":"PreviewApp","devServiceID":"com.macapper.generated.\(projectID)"}
			""".utf8
		).write(to: projectRoot.appendingPathComponent("app-manifest.json"))
		try """
		// swift-tools-version: 6.0
		import PackageDescription
		let package = Package(
		  name: "Fixture",
		  platforms: [.macOS(.v14)],
		  products: [.executable(name: "ProductionApp", targets: ["ProductionApp"])],
		  targets: [.executableTarget(name: "ProductionApp")]
		)
		""".write(
			to: projectRoot.appendingPathComponent("Package.swift"), atomically: true, encoding: .utf8)
		let source = projectRoot.appendingPathComponent("Sources/ProductionApp/main.swift")
		try FileManager.default.createDirectory(
			at: source.deletingLastPathComponent(), withIntermediateDirectories: true)
		try """
		#if compiler(<6.4)
		#error("Swift 6.4 is required")
		#endif
		import Foundation
		let output = URL(fileURLWithPath: ProcessInfo.processInfo.environment["DEVTOOLS_LAUNCHED"]!)
		try String(ProcessInfo.processInfo.processIdentifier).write(to: output, atomically: true, encoding: .utf8)
		Thread.sleep(forTimeInterval: 10)
		""".write(to: source, atomically: true, encoding: .utf8)
		launched = root.appendingPathComponent("launched.txt")
	}

	func approvedProject() async throws -> ResolvedProject {
		let registry = ProjectResolver(projectsRoot: root)
		return try await registry.lookup(
			projectRoot: root.appendingPathComponent(projectID).path,
			projectID: projectID, sessionID: sessionID)
	}

	func remove() { try? FileManager.default.removeItem(at: root) }
}
