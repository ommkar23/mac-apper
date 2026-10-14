// @frontmatter:start
// Tests journal tail repair, paged history, and rejection of foreign session paths.
// @frontmatter:end
import Foundation
import Scenario
import Testing
@testable import AgentApplication

@Test func journalRepairsIncompleteFinalRecordAndPagesEarlierHistory() throws {
	let root = try ProjectTemporaryDirectory.root().appendingPathComponent(UUID().uuidString)
	defer { try? FileManager.default.removeItem(at: root) }
	let session = root.appendingPathComponent(".pi/sessions/session-1.jsonl")
	try FileManager.default.createDirectory(
		at: session.deletingLastPathComponent(),
		withIntermediateDirectories: true)
	let journal = try SessionEventJournal(sessionFile: session, sessionID: "session-1")
	try journal.append(.init(sequence: 0, event: .textDelta("saved")))
	let tail = try FileHandle(forWritingTo: journal.url)
	try tail.seekToEnd()
	try tail.write(contentsOf: Data("{\"sequence\":1".utf8))
	try tail.close()
	#expect(throws: (any Error).self) { try journal.page(cursor: 0) }
	#expect(try journal.recover() == 1)
	try journal.append(.init(sequence: 1, event: .settled))
	let page = try journal.page(cursor: 0)
	#expect(page.events.map(\.event) == [.textDelta("saved"), .settled])
	#expect(page.nextCursor == 2)
}

@Test func journalRejectsForeignSessionPaths() throws {
	let root = try ProjectTemporaryDirectory.root().appendingPathComponent(UUID().uuidString)
	#expect(throws: (any Error).self) {
		try SessionEventJournal(
			sessionFile: root.appendingPathComponent("foreign.jsonl"),
			sessionID: "../escape")
	}
}
