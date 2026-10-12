// @frontmatter:start
// Tests project-relative path validation and rejection of symlinked directories.
// @frontmatter:end
import Foundation
import Testing

@testable import DevToolsApplication

@Test func scopedPathsRejectTraversalAndSymlinks() throws {
	let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
	try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
	defer { try? FileManager.default.removeItem(at: root) }
	let scope = try ProjectScope(root: root)
	#expect(try scope.resolve("Sources/App.swift").lastPathComponent == "App.swift")
	for path in ["../escape", "/tmp/escape", "Sources/../escape", "", "a//b", "a/./b", "a\\b"] {
		#expect(throws: (any Error).self) { try scope.resolve(path) }
	}
	try FileManager.default.createSymbolicLink(
		at: root.appendingPathComponent("link"),
		withDestinationURL: root.deletingLastPathComponent())
	#expect(throws: (any Error).self) { try scope.resolve("link/output.png") }
	#expect(throws: (any Error).self) { try ProjectScope(root: root.appendingPathComponent("link")) }
}
