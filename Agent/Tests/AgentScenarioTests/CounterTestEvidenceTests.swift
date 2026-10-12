// @frontmatter:start
// Exercises the counter evidence audit with an offline JSONL fixture and real standalone Swift 6.4 parse output.
// @frontmatter:end
import Foundation
import Testing

@Test func counterEvidenceParsesSwift64WithoutModelOrToolCalls() async throws {
	let root = URL(fileURLWithPath: "/private/tmp/mac-apper-counter-evidence-\(UUID().uuidString)")
	try FileManager.default.createDirectory(at: root, withIntermediateDirectories: false)
	defer { try? FileManager.default.removeItem(at: root) }
	let relative = "Tests/AppModelTests/CounterChecks.swift"
	let source = root.appendingPathComponent(relative)
	try FileManager.default.createDirectory(
		at: source.deletingLastPathComponent(), withIntermediateDirectories: true)
	try """
	import Testing
	import AppModel
	@Test @MainActor func counterBehaviors() {
	    let model = ApplicationModel()
	    #expect(model.count == 0)
	    model.increment()
	    model.decrement()
	    model.reset()
	    #expect(model.count == 0)
	}
	""".write(to: source, atomically: true, encoding: .utf8)
	let fixture = try orderedEvidenceFixture(names: ["write", "test"], nested: true, path: relative)
	let sessions = root.appendingPathComponent(".pi/sessions")
	let journals = root.appendingPathComponent(".pi/agent-events")
	for directory in [sessions, journals] {
		try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
	}
	let session = sessions.appendingPathComponent("fixture.jsonl")
	try fixture.session.write(to: session)
	try fixture.journal.write(to: journals.appendingPathComponent("fixture.jsonl"))
	try await verifyCounterTesting(session: session, project: root)
}
