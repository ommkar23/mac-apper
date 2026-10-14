// @frontmatter:start
// Tests scaffold integrity checks against tampering, extra files, and symlinks.
// @frontmatter:end
import Foundation
import Scenario
import Testing

@testable import AgentApplication

@Test func scaffoldNamingRejectsOldVersionWithoutMigration() throws {
	let parent = try ProjectTemporaryDirectory.root().appendingPathComponent(UUID().uuidString)
	defer { try? FileManager.default.removeItem(at: parent) }
	let root = try ProjectScaffold.create(under: parent)
	let version = root.appendingPathComponent("Scaffold.version")
	let production = root.appendingPathComponent("Sources/ProductionApp/ProductionApp.swift")
	let original = try Data(contentsOf: production)
	try "8".write(to: version, atomically: true, encoding: .utf8)
	#expect(throws: ScaffoldError.self) { try ProjectScaffold.validate(root) }
	#expect(try String(contentsOf: version, encoding: .utf8) == "8")
	#expect(try Data(contentsOf: production) == original)
}

@Test func scaffoldNamingProtectsProductionSceneBytes() throws {
	let parent = try ProjectTemporaryDirectory.root().appendingPathComponent(UUID().uuidString)
	defer { try? FileManager.default.removeItem(at: parent) }
	let root = try ProjectScaffold.create(under: parent)
	let path = "Sources/ProductionApp/ProductionApp.swift"
	let production = root.appendingPathComponent(path)
	let expected = try #require(BaseAppTemplate.protectedFiles(appID: root.lastPathComponent)[path])
	#expect(try String(contentsOf: production, encoding: .utf8) == expected)
	try (expected + "\n// changed protected bytes\n").write(
		to: production, atomically: true, encoding: .utf8)
	#expect(throws: ScaffoldError.self) { try ProjectScaffold.validate(root) }
}

@Test func protectedInventoryRejectsAlteredAndExtraFiles() throws {
	let parent = try ProjectTemporaryDirectory.root().appendingPathComponent(UUID().uuidString)
	defer { try? FileManager.default.removeItem(at: parent) }
	let root = try ProjectScaffold.create(under: parent)
	let protected = root.appendingPathComponent("Sources/PreviewContract/PreviewProtocol.swift")
	try "tampered".write(to: protected, atomically: true, encoding: .utf8)
	#expect(throws: (any Error).self) { try ProjectScaffold.validate(root) }
	try ContractSource.text.write(to: protected, atomically: true, encoding: .utf8)
	try "// extra".write(
		to: protected.deletingLastPathComponent().appendingPathComponent("Extra.swift"),
		atomically: true, encoding: .utf8)
	#expect(throws: (any Error).self) { try ProjectScaffold.validate(root) }
	let other = try ProjectScaffold.create(under: parent)
	try FileManager.default.createSymbolicLink(
		at: other.appendingPathComponent("Sources/AppModel/Link.swift"),
		withDestinationURL: URL(fileURLWithPath: "/etc/passwd"))
	#expect(throws: (any Error).self) { try ProjectScaffold.validate(other) }
}
