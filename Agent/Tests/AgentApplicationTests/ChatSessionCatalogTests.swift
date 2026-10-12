// @frontmatter:start
// Tests scoped Pi session catalog loading and rejection of linked histories.
// @frontmatter:end
import Foundation
import Testing
@testable import AgentApplication

private func writeCatalogSession(in project: URL, filename: String, prompt: String, answer: String)
	throws -> URL
{
	let directory = project.appendingPathComponent(".pi/sessions")
	try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
	let file = directory.appendingPathComponent(filename)
	let entries: [[String: Any]] = [
		["type": "session", "version": 3, "id": UUID().uuidString, "cwd": project.path],
		[
			"type": "message", "id": "user", "parentId": NSNull(),
			"message": ["role": "user", "content": prompt],
		],
		[
			"type": "message", "id": "answer", "parentId": "user",
			"message": ["role": "assistant", "content": [["type": "text", "text": answer]]],
		],
	]
	let text =
		try entries.map {
			String(decoding: try JSONSerialization.data(withJSONObject: $0), as: UTF8.self)
		}.joined(separator: "\n") + "\n"
	try text.write(to: file, atomically: true, encoding: .utf8)
	return file
}

@Test func sessionCatalogRejectsForeignAndLinkedHistories() throws {
	let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
	defer { try? FileManager.default.removeItem(at: root) }
	let first = root.appendingPathComponent("first")
	let second = root.appendingPathComponent("second")
	let file = try writeCatalogSession(
		in: first, filename: "one.jsonl", prompt: "One", answer: "Reply")
	_ = try writeCatalogSession(in: second, filename: "two.jsonl", prompt: "Two", answer: "Reply")
	#expect(throws: (any Error).self) { try ChatSessionCatalog.load(file, in: second) }
	let link = second.appendingPathComponent(".pi/sessions/link.jsonl")
	try FileManager.default.createSymbolicLink(at: link, withDestinationURL: file)
	#expect(throws: (any Error).self) { try ChatSessionCatalog.load(link, in: second) }
	#expect(try ChatSessionCatalog.discover(in: second).count == 1)
	let alias = root.appendingPathComponent("alias")
	try FileManager.default.createSymbolicLink(
		at: alias, withDestinationURL: first.appendingPathComponent(".pi/sessions"))
	#expect(throws: (any Error).self) {
		try ChatSessionCatalog.load(alias.appendingPathComponent("one.jsonl"), in: first)
	}
}

@Test func sessionCatalogLoadsRealPiHistoryAndGeneratesTitles() throws {
	let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
	defer { try? FileManager.default.removeItem(at: root) }
	let file = try writeCatalogSession(
		in: root, filename: "one.jsonl", prompt: "Build a notes app", answer: "Done")
	let sessions = try ChatSessionCatalog.discover(in: root)
	#expect(sessions.count == 1)
	#expect(sessions.first?.title == "Build a notes app")
	let loaded = try ChatSessionCatalog.load(file, in: root)
	#expect(loaded.messages.map(\.text) == ["Build a notes app", "Done"])
	#expect(loaded.messages.map(\.isUser) == [true, false])
}
