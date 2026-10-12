// @frontmatter:start
// Tests Pi process identity parsing when command arguments contain multiline system prompts.
// @frontmatter:end
import AgentScenarioSupport
import Testing

@Test func piProcessSnapshotKeepsMultilineArgumentsWithTheirPID() throws {
	let snapshot = """
		100 /usr/bin/unrelated --session /other.jsonl
		200 node pi --tools search,extract --no-skills --system-prompt First line.
		Second line. --session /fixture/session.jsonl --name Chat
		300 /usr/bin/unrelated
		"""
	let found = try ScenarioProcessSnapshot.find(snapshot, sessionPath: "/fixture/session.jsonl")
	#expect(found.pid == "200")
	#expect(found.arguments.contains("--tools search,extract"))
	#expect(found.arguments.contains("Second line."))
	let withChild = snapshot + "\n400 node helper --session /fixture/session.jsonl"
	#expect(throws: (any Error).self) {
		try ScenarioProcessSnapshot.find(withChild, sessionPath: "/fixture/session.jsonl")
	}
	#expect(
		try ScenarioProcessSnapshot.find(
			withChild, sessionPath: "/fixture/session.jsonl", expectedPID: "200"
		).pid == "200")
	#expect(throws: (any Error).self) {
		try ScenarioProcessSnapshot.find(snapshot, sessionPath: "/foreign.jsonl")
	}
}
