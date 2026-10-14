// @frontmatter:start
// Tests RunController development app staging, launch, and process cleanup.
// @frontmatter:end
import Darwin
import Foundation
import Scenario
import Testing

@testable import DevToolsApplication

@Test func runCanLaunchWithoutAnEndpointHandshake() async throws {
	let fixture = try LaunchFixture()
	defer { fixture.remove() }
	var environment = ProcessInfo.processInfo.environment
	environment["DEVTOOLS_LAUNCHED"] = fixture.launched.path
	try fixture.writeBranding("HTView")
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
	var firstPID: Int32?
	for _ in 0..<100 {
		if let text = try? String(contentsOf: fixture.launched, encoding: .utf8),
			let pid = Int32(text)
		{
			firstPID = pid
			break
		}
		try await Task.sleep(for: .milliseconds(10))
	}
	let plist = try fixture.stagedPlist(result.appBundle)
	#expect(plist["CFBundleName"] as? String == "HTView")
	#expect(plist["CFBundleDisplayName"] as? String == "HTView")
	#expect(plist["CFBundleExecutable"] as? String == "ProductionApp")
	#expect(plist["CFBundleIdentifier"] as? String == "com.macapper.dev." + fixture.projectID)
	#expect(plist["CFBundleVersion"] as? String == fixture.requestID)
	#expect(plist["CFBundleShortVersionString"] as? String == "0")
	#expect(plist["Unrelated"] == nil)
	try fixture.writeBranding("Renamed HTView")
	let replacement = try await launcher.run(
		project: fixture.approvedProject(), requestID: UUID().uuidString.lowercased())
	let previousWasReaped = firstPID.map { kill($0, 0) == -1 && errno == ESRCH } ?? false
	try await launcher.stopAll()
	let replacementPlist = try fixture.stagedPlist(replacement.appBundle)
	#expect(replacement.instanceID != result.instanceID)
	#expect(replacement.target == "ProductionApp")
	#expect(replacementPlist["CFBundleName"] as? String == "Renamed HTView")
	#expect(replacementPlist["CFBundleExecutable"] as? String == "ProductionApp")
	#expect(firstPID != nil)
	#expect(previousWasReaped)
}

@Test func runBrandingStagesChangedAndAbsentNames() async throws {
	let fixture = try LaunchFixture()
	defer { fixture.remove() }
	let project = try await fixture.approvedProject()
	let projects = ProjectResolver(projectsRoot: fixture.root)
	let gate = DevToolsOperationGate()
	let launcher = RunController(
		projects: projects, gate: gate, build: BuildController(projects: projects, gate: gate))
	let buildDirectory = project.scope.root.appendingPathComponent("fixture-build")
	let binary = buildDirectory.appendingPathComponent("debug/ProductionApp")
	try FileManager.default.createDirectory(
		at: binary.deletingLastPathComponent(), withIntermediateDirectories: true)
	try Data("fixture executable".utf8).write(to: binary)
	try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: binary.path)
	let build = SourceBuildResult(target: "ProductionApp", buildDirectory: buildDirectory, output: "")
	for name in [nil, "HTView", "Changed Name", String(repeating: "界", count: 64)] as [String?] {
		if let name { try fixture.writeBranding(name) }
		let requestID = UUID().uuidString.lowercased()
		let bundle = try await launcher.stage(build: build, project: project, requestID: requestID)
		let plist = try fixture.stagedPlist(bundle)
		#expect(bundle.lastPathComponent == "ProductionApp.app")
		#expect(plist["CFBundleName"] as? String == (name ?? "ProductionApp"))
		#expect(plist["CFBundleDisplayName"] as? String == (name ?? "ProductionApp"))
		#expect(plist["CFBundleExecutable"] as? String == "ProductionApp")
		#expect(plist["CFBundleIdentifier"] as? String == "com.macapper.dev." + fixture.projectID)
		#expect(plist["CFBundleVersion"] as? String == requestID)
		#expect(plist["CFBundleShortVersionString"] as? String == "0")
		#expect(plist["Unrelated"] == nil)
		#expect(
			try Data(contentsOf: bundle.appendingPathComponent("Contents/MacOS/ProductionApp"))
				== Data(contentsOf: binary))
	}
}

@Test func runBrandingValidatesMetadata() throws {
	let fixture = try LaunchFixture()
	defer { fixture.remove() }
	let scope = try ProjectScope(root: fixture.root.appendingPathComponent(fixture.projectID))
	let metadata = scope.root.appendingPathComponent("Info.plist")
	func write(_ plist: Any, binary: Bool = false) throws {
		try PropertyListSerialization.data(
			fromPropertyList: plist, format: binary ? .binary : .xml, options: 0
		).write(to: metadata)
	}
	#expect(
		try DevelopmentBranding.load(scope: scope, fallback: "ProductionApp").name == "ProductionApp")
	try write(["CFBundleName": "  One/:\\\\ Two.app.APP  "])
	#expect(try DevelopmentBranding.load(scope: scope, fallback: "ProductionApp").name == "One Two")
	try write(["CFBundleDisplayName": "Display", "CFBundleName": "Internal"], binary: true)
	#expect(try DevelopmentBranding.load(scope: scope, fallback: "ProductionApp").name == "Display")
	try write(["CFBundleDisplayName": "X"])
	#expect(try DevelopmentBranding.load(scope: scope, fallback: "ProductionApp").name == "X")
	for plist: Any in [
		["CFBundleName": ""], ["CFBundleName": ".hidden"],
		["CFBundleName": String(repeating: "a", count: 65)],
		["CFBundleName": 42], ["CFBundleDisplayName": false, "CFBundleName": "Valid"],
		["CFBundleDisplayName": "Valid", "CFBundleName": []],
		["Unrelated": "no name"], ["not a dictionary"],
	] {
		try write(plist)
		#expect(throws: DevelopmentLaunchError.invalidBranding) {
			try DevelopmentBranding.load(scope: scope, fallback: "ProductionApp")
		}
	}
	for data in [Data(), Data("not a plist".utf8), Data(repeating: 32, count: 16_385)] {
		try data.write(to: metadata)
		#expect(throws: DevelopmentLaunchError.invalidBranding) {
			try DevelopmentBranding.load(scope: scope, fallback: "ProductionApp")
		}
	}
	try FileManager.default.removeItem(at: metadata)
	let external = fixture.root.appendingPathComponent("external.plist")
	try Data("external".utf8).write(to: external)
	try FileManager.default.createSymbolicLink(at: metadata, withDestinationURL: external)
	#expect(throws: ProjectValidationError.self) {
		try DevelopmentBranding.load(scope: scope, fallback: "ProductionApp")
	}
	try FileManager.default.removeItem(at: metadata)
	try FileManager.default.createDirectory(at: metadata, withIntermediateDirectories: false)
	#expect(throws: DevelopmentLaunchError.invalidBranding) {
		try DevelopmentBranding.load(scope: scope, fallback: "ProductionApp")
	}
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
		root = try ProjectTemporaryDirectory.root().appendingPathComponent(UUID().uuidString)
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
		Thread.sleep(forTimeInterval: 60)
		""".write(to: source, atomically: true, encoding: .utf8)
		launched = root.appendingPathComponent("launched.txt")
	}

	func approvedProject() async throws -> ResolvedProject {
		let registry = ProjectResolver(projectsRoot: root)
		return try await registry.lookup(
			projectRoot: root.appendingPathComponent(projectID).path,
			projectID: projectID, sessionID: sessionID)
	}

	func writeBranding(_ name: String) throws {
		let plist: [String: Any] = [
			"CFBundleName": name, "CFBundleDisplayName": name,
			"CFBundleExecutable": "Untrusted", "CFBundleIdentifier": "untrusted.id",
			"CFBundleVersion": "999", "CFBundleShortVersionString": "999",
			"Unrelated": "must not copy",
		]
		try PropertyListSerialization.data(fromPropertyList: plist, format: .xml, options: 0)
			.write(to: root.appendingPathComponent("\(projectID)/Info.plist"))
	}

	func stagedPlist(_ bundle: URL) throws -> [String: Any] {
		try #require(
			PropertyListSerialization.propertyList(
				from: Data(contentsOf: bundle.appendingPathComponent("Contents/Info.plist")),
				options: [], format: nil) as? [String: Any])
	}

	func remove() { try? FileManager.default.removeItem(at: root) }
}
