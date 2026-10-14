// @frontmatter:start
// Checks repository-local scenario temporary storage and child temporary-directory configuration.
// @frontmatter:end
import Foundation
import Testing

@testable import Scenario

@Test func scenarioTemporaryStorageUsesProjectRoot() throws {
	let project = URL(fileURLWithPath: #filePath)
		.deletingLastPathComponent().deletingLastPathComponent()
		.deletingLastPathComponent().deletingLastPathComponent()
	let expected = project.appendingPathComponent(".tmp", isDirectory: true)
	let home = try IsolatedScenarioHome()
	defer { try? home.remove(cleanupConfirmed: true) }
	#expect(
		home.directory.deletingLastPathComponent().standardizedFileURL == expected.standardizedFileURL)
	#expect(home.environment["TMPDIR"] == expected.path + "/")
}

@Test func projectTemporaryRootRejectsLinksFilesAndPublicPermissions() throws {
	let manager = FileManager.default
	let fixture = try ProjectTemporaryDirectory.appending("tmp-root-check-\(UUID().uuidString)")
	try manager.createDirectory(at: fixture, withIntermediateDirectories: false)
	defer { try? manager.removeItem(at: fixture) }
	let outside = fixture.appendingPathComponent("outside")
	try manager.createDirectory(at: outside, withIntermediateDirectories: false)
	let root = fixture.appendingPathComponent(".tmp")
	try manager.createSymbolicLink(at: root, withDestinationURL: outside)
	#expect(throws: (any Error).self) { try ProjectTemporaryDirectory.root(project: fixture) }
	#expect(try manager.contentsOfDirectory(atPath: outside.path).isEmpty)
	try manager.removeItem(at: root)
	try manager.createDirectory(
		at: root, withIntermediateDirectories: false, attributes: [.posixPermissions: 0o755])
	#expect(throws: (any Error).self) { try ProjectTemporaryDirectory.root(project: fixture) }
	try manager.removeItem(at: root)
	let bytes = Data("not a directory".utf8)
	try bytes.write(to: root)
	#expect(throws: (any Error).self) { try ProjectTemporaryDirectory.root(project: fixture) }
	#expect(try Data(contentsOf: root) == bytes)
}

@Test func projectTemporaryPathsAndEnvironmentFailClosed() throws {
	for name in [
		"", ".", "..", "../escape", "/escape", "a\\b", "a\n", String(repeating: "x", count: 256),
	] {
		#expect(throws: (any Error).self) { try ProjectTemporaryDirectory.appending(name) }
	}
	let root = try ProjectTemporaryDirectory.root()
	let attributes = try FileManager.default.attributesOfItem(atPath: root.path)
	#expect((attributes[.posixPermissions] as? NSNumber)?.intValue == 0o700)
	let environment = try ProjectTemporaryDirectory.environment([
		"TMPDIR": "/must-not-be-used", "PRESERVED": "ordinary configuration",
	])
	#expect(environment["TMPDIR"] == root.path + "/")
	#expect(environment["PRESERVED"] == "ordinary configuration")
	#expect(
		try ProjectTemporaryDirectory.appending("disposable.log").deletingLastPathComponent() == root)
}
