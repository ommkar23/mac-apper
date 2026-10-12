// @frontmatter:start
// Tests scaffold integrity checks against tampering, extra files, and symlinks.
// @frontmatter:end
import Foundation
import Testing

@testable import AgentApplication

@Test func protectedInventoryRejectsAlteredAndExtraFiles() throws {
	let parent = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
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
