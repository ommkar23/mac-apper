// @frontmatter:start
// Tests Pi JSONL commands, streamed RPC event parsing, limits, and task updates.
// @frontmatter:end
import Foundation
import Testing

@testable import AgentApplication

@Test func macApperCreatesProjectsDirectlyUnderItsHomeDirectory() throws {
	let home = URL(fileURLWithPath: "/Users/example", isDirectory: true)
	#expect(AgentPaths.projectsRoot(home: home).path == "/Users/example/.mac-apper")
}

@Test func piPromptCommandUsesStrictJSONLFraming() throws {
	let bytes = try PiRPCCommand.prompt(id: "prompt-1", message: "Build a notes app").encodedLine()
	#expect(bytes.last == 10)
	let object = try #require(
		JSONSerialization.jsonObject(with: bytes.dropLast()) as? [String: String])
	#expect(
		object == [
			"id": "prompt-1", "type": "prompt", "message": "Build a notes app",
			"streamingBehavior": "steer",
		])
}

@Test func piRPCCommandsPreserveUTF8InputBoundsAndAbortFraming() throws {
	let message = String(repeating: "é", count: 32_768)
	let bytes = try PiRPCCommand.prompt(id: "prompt", message: message).encodedLine()
	let object = try #require(
		JSONSerialization.jsonObject(with: bytes.dropLast()) as? [String: String])
	#expect(object["message"] == message)
	#expect(throws: AgentApplication.PiRPCError.invalidRecord) {
		try PiRPCCommand.prompt(id: "prompt", message: message + "x").encodedLine()
	}
	#expect(throws: AgentApplication.PiRPCError.invalidRecord) {
		try PiRPCCommand.prompt(id: "prompt", message: "").encodedLine()
	}
	#expect(throws: AgentApplication.PiRPCError.invalidRecord) {
		try PiRPCCommand.abort(id: "").encodedLine()
	}
	let abort = try PiRPCCommand.abort(id: "abort").encodedLine()
	#expect(abort.last == 10)
	#expect(
		try JSONSerialization.jsonObject(with: abort.dropLast()) as? [String: String]
			== ["id": "abort", "type": "abort"])
}

@Test func piRPCParserPreservesCodemodeAndNestedMCPFailures() throws {
	var parser = PiRPCParser()
	let records = [
		#"{"type":"response","id":"prompt","command":"prompt","success":false,"error":"Prompt rejected"}"#,
		#"{"type":"extension_error","event":"session_start","error":"MCP initialization failed"}"#,
		#"{"type":"extension_ui_request","method":"notify","message":"MCP needs sign-in","notifyType":"error"}"#,
		#"{"type":"tool_execution_end","toolCallId":"code/1","parentToolCallId":"code","toolName":"mcp__parallel__web_search","result":{"content":[{"type":"text","text":"Search failed"}]},"isError":true}"#,
		#"{"type":"tool_execution_end","toolCallId":"code","toolName":"codemode","result":{"content":[{"type":"text","text":"Script failed"}]},"isError":true}"#,
		#"{"type":"response","id":"abort","command":"abort","success":true}"#,
	]
	let bytes = Data((records.joined(separator: "\r\n") + "\r\n").utf8)
	var events: [PiRPCEvent] = []
	for byte in bytes { events += try parser.feed(Data([byte])) }
	#expect(
		events == [
			.response(id: "prompt", command: "prompt", success: false, error: "Prompt rejected"),
			.extensionError("MCP initialization failed"), .notification("MCP needs sign-in"),
			.toolFinished(
				id: "code/1", name: "mcp__parallel__web_search", text: "Search failed", isError: true),
			.toolFinished(id: "code", name: "codemode", text: "Script failed", isError: true),
			.response(id: "abort", command: "abort", success: true, error: nil),
		])
	#expect(try parser.finish().isEmpty)
}

@Test func piRPCParserStreamsTextAndToolActivity() throws {
	var parser = PiRPCParser()
	let first = Data(
		(#"{"type":"message_update","assistantMessageEvent":{"type":"text_delta","contentIndex":0,"delta":"Hello "}}"#
			+ "\n"
			+ #"{"type":"tool_execution_start","toolCallId":"call-1","toolName":"build","args":{}}"#
			+ "\n").utf8)
	let second = Data(
		(#"{"type":"tool_execution_end","toolCallId":"call-1","toolName":"build","result":{"content":[{"type":"text","text":"Build verified"}],"details":{}},"isError":false}"#
			+ "\n" + #"{"type":"agent_settled"}"# + "\n").utf8)

	#expect(
		try parser.feed(first) == [
			.textDelta("Hello "), .toolStarted(id: "call-1", name: "build", argumentsJSON: "{}"),
		])
	#expect(
		try parser.feed(second) == [
			.toolFinished(id: "call-1", name: "build", text: "Build verified", isError: false),
			.settled,
		])
	#expect(try parser.finish().isEmpty)
}

@Test func generatedDevToolsPlanResultUpdatesPresentedTasks() throws {
	var parser = PiRPCParser()
	let record = Data(
		(#"{"type":"tool_execution_end","toolCallId":"plan-1","toolName":"plan","isError":false,"result":{"content":[{"type":"text","text":"Plan updated."}],"details":{"result":{"summary":"Plan updated.","tasks":[{"id":"design","title":"Design the app","status":"in_progress"}]}}}}"#
			+ "\n").utf8)
	let events = try parser.feed(record)
	#expect(events.count == 2)
	#expect(
		events.first
			== .tasksUpdated([
				.init(id: "design", title: "Design the app", status: .inProgress)
			]))
}

@Test(arguments: [
	#"{"type":"agent_end","messages":[],"willRetry":true}"#,
	#"{"type":"agent_end","messages":[],"willRetry":false}"#,
	#"{"type":"agent_end","messages":[]}"#,
])
func piRPCParserWaitsForSessionSettlement(_ end: String) throws {
	var parser = PiRPCParser()
	#expect(try parser.feed(Data((end + "\n").utf8)).isEmpty)
	#expect(
		try parser.feed(Data((#"{"type":"agent_settled","aborted":false}"# + "\n").utf8))
			== [.settled])
	#expect(try parser.finish().isEmpty)
}

@Test func piRPCParserPreservesPiRetryContinuationUntilSettled() throws {
	var parser = PiRPCParser()
	let records = [
		#"{"type":"agent_end","messages":[],"willRetry":true}"#,
		#"{"type":"auto_retry_start","attempt":1,"maxAttempts":3,"delayMs":2000,"errorMessage":"WebSocket error"}"#,
		#"{"type":"agent_start"}"#,
		#"{"type":"message_update","assistantMessageEvent":{"type":"text_delta","delta":"Continuing"}}"#,
		#"{"type":"tool_execution_start","toolCallId":"retry-tool","toolName":"build","args":{}}"#,
		#"{"type":"tool_execution_end","toolCallId":"retry-tool","toolName":"build","result":{"content":[{"type":"text","text":"Built"}]},"isError":false}"#,
		#"{"type":"auto_retry_end","success":true,"attempt":1}"#,
		#"{"type":"agent_end","messages":[],"willRetry":false}"#,
	]
	#expect(
		try parser.feed(Data((records.joined(separator: "\n") + "\n").utf8)) == [
			.textDelta("Continuing"),
			.toolStarted(id: "retry-tool", name: "build", argumentsJSON: "{}"),
			.toolFinished(id: "retry-tool", name: "build", text: "Built", isError: false),
		])
	#expect(
		try parser.feed(Data("{\"type\":\"agent_settled\",\"aborted\":false}\n".utf8)) == [.settled])
}

@Test(arguments: [true, false])
func piRPCParserSettlesAfterAbortOrExhaustedRetries(_ aborted: Bool) throws {
	var parser = PiRPCParser()
	let records = [
		#"{"type":"agent_end","messages":[],"willRetry":true}"#,
		#"{"type":"auto_retry_end","success":false,"attempt":3,"errorMessage":"Retry ended"}"#,
		#"{"type":"agent_end","messages":[],"willRetry":false}"#,
	]
	#expect(try parser.feed(Data((records.joined(separator: "\n") + "\n").utf8)).isEmpty)
	#expect(
		try parser.feed(Data("{\"type\":\"agent_settled\",\"aborted\":\(aborted)}\n".utf8))
			== [.settled])
}

@Test func piRPCParserRejectsNonJSONAndOversizedRecords() throws {
	var malformed = PiRPCParser()
	#expect(throws: AgentApplication.PiRPCError.invalidRecord) {
		try malformed.feed(Data("not-json\n".utf8))
	}

	var oversized = PiRPCParser(maximumRecordBytes: 32)
	#expect(throws: AgentApplication.PiRPCError.recordTooLarge) {
		try oversized.feed(Data((String(repeating: "x", count: 33) + "\n").utf8))
	}
}

@Test func piRPCParserAcceptsBoundedPreviewImagesWithoutPublishingImageBytes() throws {
	var parser = PiRPCParser()
	let record =
		try JSONSerialization.data(withJSONObject: [
			"type": "tool_execution_end", "toolCallId": "preview-1", "toolName": "preview",
			"isError": false,
			"result": [
				"content": [
					["type": "text", "text": "Rendered preview"],
					[
						"type": "image", "mimeType": "image/png",
						"data": Data(repeating: 1, count: 2_097_152).base64EncodedString(),
					],
				]
			],
		]) + Data([10])
	let split = record.count / 2
	#expect(try parser.feed(Data(record.prefix(split))).isEmpty)
	#expect(
		try parser.feed(Data(record.dropFirst(split))) == [
			.toolFinished(id: "preview-1", name: "preview", text: "Rendered preview", isError: false)
		])
	#expect(try parser.finish().isEmpty)
	var oversized = PiRPCParser()
	#expect(throws: AgentApplication.PiRPCError.recordTooLarge) {
		try oversized.feed(Data(repeating: 0, count: 4_194_305))
	}
}

@Test func piRPCParserRequiresLFDelimitedCompleteRecords() throws {
	var parser = PiRPCParser()
	_ = try parser.feed(Data(#"{"type":"agent_settled"}"#.utf8))
	#expect(throws: AgentApplication.PiRPCError.incompleteRecord) { try parser.finish() }
}
