// @frontmatter:start
// Tests discovery of complete app bundles and exclusion of linked projects.
// @frontmatter:end
import Foundation
import Testing

@testable import AgentApplication

@Test func builtAppCatalogFindsOnlyCompleteProductionBundles() throws {
	let root = FileManager.default.temporaryDirectory.appendingPathComponent(
		UUID().uuidString, isDirectory: true)
	defer { try? FileManager.default.removeItem(at: root) }
	try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)

	let complete = root.appendingPathComponent(UUID().uuidString.lowercased(), isDirectory: true)
	try FileManager.default.createDirectory(at: complete, withIntermediateDirectories: true)
	let app = root.appendingPathComponent(
		"output/\(complete.lastPathComponent)/Weather Desk.app", isDirectory: true)
	let contents = app.appendingPathComponent("Contents", isDirectory: true)
	try FileManager.default.createDirectory(
		at: contents.appendingPathComponent("MacOS"), withIntermediateDirectories: true)
	let executable = contents.appendingPathComponent("MacOS/ProductionApp")
	try Data().write(to: executable)
	try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: executable.path)
	try
		"<?xml version=\"1.0\"?><plist version=\"1.0\"><dict><key>CFBundleDisplayName</key><string>Weather Desk</string></dict></plist>"
		.write(to: contents.appendingPathComponent("Info.plist"), atomically: true, encoding: .utf8)

	let incomplete = root.appendingPathComponent(
		"output/\(UUID().uuidString.lowercased())/Incomplete.app", isDirectory: true)
	try FileManager.default.createDirectory(at: incomplete, withIntermediateDirectories: true)

	let apps = try BuiltAppCatalog.discover(in: root)

	#expect(apps.count == 1)
	#expect(apps[0].name == "Weather Desk")
	#expect(apps[0].bundleURL.lastPathComponent == "Weather Desk.app")
	#expect(
		apps[0].bundleURL.path.hasSuffix("/output/\(complete.lastPathComponent)/Weather Desk.app"))
	#expect(apps[0].projectName == complete.lastPathComponent)
}

@Test func builtAppCatalogSkipsSymbolicLinkedProjects() throws {
	let root = FileManager.default.temporaryDirectory.appendingPathComponent(
		UUID().uuidString, isDirectory: true)
	defer { try? FileManager.default.removeItem(at: root) }
	try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
	try FileManager.default.createSymbolicLink(
		at: root.appendingPathComponent("linked"),
		withDestinationURL: FileManager.default.homeDirectoryForCurrentUser)

	#expect(try BuiltAppCatalog.discover(in: root).isEmpty)
}
