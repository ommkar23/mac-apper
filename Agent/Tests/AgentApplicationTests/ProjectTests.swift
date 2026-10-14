// @frontmatter:start
// Tests generated project scaffolding, Git baseline, and buildable app contracts.
// @frontmatter:end
import Foundation
import Scenario
import Testing

@testable import AgentApplication

private func git(_ arguments: [String], in project: URL) throws -> String {
	let process = Process()
	let output = Pipe()
	process.executableURL = URL(fileURLWithPath: "/usr/bin/git")
	process.arguments = arguments
	process.currentDirectoryURL = project
	process.standardOutput = output
	process.standardError = output
	try process.run()
	process.waitUntilExit()
	let text = String(decoding: output.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
	guard
		process.terminationStatus == 0
	else {
		throw NSError(
			domain: "ProjectTests.Git", code: Int(process.terminationStatus),
			userInfo: [NSLocalizedDescriptionKey: text])
	}
	return text.trimmingCharacters(in: .whitespacesAndNewlines)
}

@Test func projectScaffoldOwnsManifestAndValidatesTampering() throws {
	let parent = try ProjectTemporaryDirectory.root().appendingPathComponent(UUID().uuidString)
	try FileManager.default.createDirectory(at: parent, withIntermediateDirectories: true)
	defer { try? FileManager.default.removeItem(at: parent) }
	let project = try ProjectScaffold.create(under: parent)
	try ProjectScaffold.validate(project)
	let manifest = try String(
		contentsOf: project.appendingPathComponent("Package.swift"), encoding: .utf8)
	#expect(manifest.contains("AppModel"))
	#expect(manifest.contains("ProductionApp"))
	let info = try #require(NSDictionary(contentsOf: project.appendingPathComponent("Info.plist")))
	#expect(info["CFBundleDisplayName"] as? String == "Generated App")
	#expect(
		info["CFBundleIdentifier"] as? String == "com.macapper.generated.\(project.lastPathComponent)")
	for path in [
		"Sources/AppModel/ApplicationModel.swift", "Sources/AppModel/Persistence.swift",
		"Sources/AppModel/ApplicationState.swift", "Sources/AppViews/ApplicationRoot.swift",
		"Sources/PreviewSupport/PreviewController.swift", "Tests/AppModelTests/ApplicationTests.swift",
	] {
		#expect(FileManager.default.fileExists(atPath: project.appendingPathComponent(path).path))
	}
	#expect(FileManager.default.fileExists(atPath: project.appendingPathComponent(".git").path))
	#expect(try git(["rev-list", "--count", "HEAD"], in: project) == "1")
	#expect(try git(["log", "-1", "--pretty=%s"], in: project) == "Initial Mac Apper scaffold")
	#expect(try git(["status", "--porcelain"], in: project).isEmpty)
	#expect(manifest.contains("#if os(macOS)"))
	#expect(manifest.contains("DevExtension"))
	#expect(
		manifest.contains(
			"ProductionApp\", dependencies: [\"AppModel\", \"AppViews\", \"DevExtension\"]"))
	#expect(
		try String(contentsOf: project.appendingPathComponent("Scaffold.version"), encoding: .utf8)
			== "9")
	#expect(!manifest.contains("PreviewFixtures"))
	#expect(!FileManager.default.fileExists(atPath: project.appendingPathComponent("Fixtures").path))
	for path in [
		"app-manifest.json",
		"Sources/DevExtension/GeneratedAppXPCService.swift",
	] {
		#expect(FileManager.default.fileExists(atPath: project.appendingPathComponent(path).path))
	}
	let appManifest =
		try JSONSerialization.jsonObject(
			with: Data(contentsOf: project.appendingPathComponent("app-manifest.json"))) as? [String: Any]
	#expect(appManifest?["schemaVersion"] as? Int == 1)
	#expect(appManifest?["appID"] as? String == project.lastPathComponent)
	#expect(appManifest?["executableTarget"] as? String == "ProductionApp")
	#expect(appManifest?["previewTarget"] as? String == "PreviewApp")
	#expect(
		appManifest?["devServiceID"] as? String
			== "com.macapper.generated.\(project.lastPathComponent)")
	#expect(appManifest?["capabilities"] == nil)
	try "tampered".write(
		to: project.appendingPathComponent("Package.swift"), atomically: true, encoding: .utf8)
	#expect(throws: (any Error).self) { try ProjectScaffold.validate(project) }
}

@Test func generatedDevExtensionBuildsAndPassesItsContractTests() throws {
	let parent = try ProjectTemporaryDirectory.root().appendingPathComponent(UUID().uuidString)
	try FileManager.default.createDirectory(at: parent, withIntermediateDirectories: true)
	defer { try? FileManager.default.removeItem(at: parent) }
	let project = try ProjectScaffold.create(under: parent)
	let process = Process()
	let output = Pipe()
	process.executableURL = try SwiftToolchain.executable("swift")
	var environment = ProcessInfo.processInfo.environment
	environment["SWIFT_EXEC"] = try SwiftToolchain.executable("swiftc").path
	process.environment = environment
	process.arguments = [
		"test", "-j", "2", "--scratch-path",
		parent.appendingPathComponent("generated-build").path,
	]
	process.currentDirectoryURL = project
	process.standardOutput = output
	process.standardError = output
	try process.run()
	let log = String(decoding: output.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
	process.waitUntilExit()
	#expect(process.terminationStatus == 0, "Generated scaffold verification failed:\n\(log)")
}
