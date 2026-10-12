// @frontmatter:start
// Checks direct and nested tool evidence correlation against offline Pi session and Agent journal fixtures.
// @frontmatter:end
import Foundation
import Testing

@Test func toolEvidenceMatchesDirectAndNestedResultsOffline() throws {
	for nested in [false, true] {
		let fixture = try evidenceFixture(nested: nested)
		let evidence = try ScenarioToolEvidence(session: fixture.session, journal: fixture.journal)
		let call = try #require(evidence.calls.first { $0.name == "test" })
		#expect(call.succeeded)
		#expect(call.typedResult?["status"] as? String == "passed")
		#expect(call.typedResult?["exitCode"] as? Int == 0)
		#expect(call.parentID == (nested ? "outer" : nil))
	}
}

@Test func toolEvidenceRejectsForgedIncompleteAndMismatchedOffline() throws {
	for mutation in [
		"missingStart", "missingEnd", "duplicateStart", "duplicateEnd", "wrongName",
		"wrongArgs", "wrongStatus", "incomplete", "unknownChild", "outsideParent", "forgedText",
		"duplicateResult", "sequenceGap",
	] {
		let fixture = try evidenceFixture(nested: true, mutation: mutation)
		#expect(throws: (any Error).self) {
			try ScenarioToolEvidence(session: fixture.session, journal: fixture.journal)
		}
	}
}

@Test func toolEvidenceDoesNotBorrowLaterPreviewCompletionOffline() throws {
	for nested in [false, true] {
		let fixture = try orderedEvidenceFixture(
			names: ["preview", "preview"], nested: nested, path: "",
			results: [["status": "error", "summary": "Render failed"], ["status": "rendered"]])
		let firstID = nested ? "call-0/1" : "call-0"
		var records = try fixture.journal.split(separator: 10).map {
			try #require(JSONSerialization.jsonObject(with: Data($0)) as? [String: Any])
		}
		records.removeAll {
			let event = $0["event"] as? [String: Any]
			let end = event?["toolFinished"] as? [String: Any]
			return end?["id"] as? String == firstID
		}
		let journal = try evidenceJSONL(
			records.enumerated().map {
				["sequence": $0.offset, "event": $0.element["event"]!]
			})
		#expect(throws: (any Error).self) {
			try ScenarioToolEvidence(session: fixture.session, journal: journal)
		}
	}
}

@Test func toolEvidenceRejectsForgedDirectResultsOffline() throws {
	for mutation in ["wrongDetails", "forgedDirectText", "collidingRoot", "missingResult"] {
		let fixture = try evidenceFixture(nested: false, mutation: mutation)
		#expect(throws: (any Error).self) {
			try ScenarioToolEvidence(session: fixture.session, journal: fixture.journal)
		}
	}
}

@Test func toolEvidenceDoesNotPromoteFailedCallsOrOuterScriptTextOffline() throws {
	let fixture = try evidenceFixture(nested: true, mutation: "failed")
	let evidence = try ScenarioToolEvidence(session: fixture.session, journal: fixture.journal)
	#expect(evidence.calls.first { $0.name == "test" }?.succeeded == false)
	#expect(evidence.calls.first { $0.name == "test" }?.typedResult == nil)
}

@Test func toolEvidenceRejectsTransportOnlyAndFailedTypedTestsOffline() throws {
	for nested in [false, true] {
		let fixture = try orderedEvidenceFixture(
			names: ["write", "test"], nested: nested, path: "Tests/AppModelTests/Counter.swift",
			passing: false)
		let evidence = try ScenarioToolEvidence(session: fixture.session, journal: fixture.journal)
		#expect(evidence.calls.first { $0.name == "test" }?.succeeded == true)
		#expect(
			try evidence.testedSourcePaths(project: URL(fileURLWithPath: "/private/tmp/owned-project"))
				.isEmpty)
	}
}

@Test func toolEvidenceRejectsBooleanExitCodesOffline() throws {
	let fixture = try orderedEvidenceFixture(
		names: ["write", "test"], nested: true, path: "Tests/AppModelTests/Counter.swift",
		results: [[:], ["status": "passed", "exitCode": false]])
	let evidence = try ScenarioToolEvidence(session: fixture.session, journal: fixture.journal)
	#expect(
		try evidence.testedSourcePaths(project: URL(fileURLWithPath: "/private/tmp/owned-project"))
			.isEmpty)
}

@Test func toolEvidenceRequiresActualParentImageForwardingOffline() throws {
	// Generic image-contract identity fixture; path-only Preview does not require image delivery.
	let bytes = Data([137, 80, 78, 71])
	for nested in [false, true] {
		let fixture = try evidenceFixture(nested: nested)
		let plain = try ScenarioToolEvidence(session: fixture.session, journal: fixture.journal)
		#expect(plain.calls.first { $0.name == "test" }?.deliversPNG(bytes) == false)
		var records = try fixture.session.split(separator: 10).map {
			try #require(JSONSerialization.jsonObject(with: Data($0)) as? [String: Any])
		}
		var message = try #require(records[1]["message"] as? [String: Any])
		var content = try #require(message["content"] as? [[String: Any]])
		content.append(["type": "image", "mimeType": "image/png", "data": bytes.base64EncodedString()])
		message["content"] = content; records[1]["message"] = message
		let forwarded = try ScenarioToolEvidence(
			session: evidenceJSONL(records), journal: fixture.journal)
		let call = try #require(forwarded.calls.first { $0.name == "test" })
		#expect(call.deliversPNG(bytes))
		#expect(!call.deliversPNG(Data([0])))
	}
}

@Test func toolEvidenceRequiresLatestAuthoredRevisionBeforePassingTestOffline() throws {
	let project = URL(fileURLWithPath: "/private/tmp/owned-evidence-project")
	let path = "Tests/AppModelTests/Counter.swift"
	for nested in [false, true] {
		for names in [
			["write", "test"], ["test", "write"], ["write", "test", "edit"],
			["write", "test", "edit", "test"],
		] {
			let fixture = try orderedEvidenceFixture(names: names, nested: nested, path: path)
			let evidence = try ScenarioToolEvidence(session: fixture.session, journal: fixture.journal)
			let expected = names.last == "test" ? [path] : []
			#expect(try evidence.testedSourcePaths(project: project) == expected)
		}
	}
}

func orderedEvidenceFixture(
	names: [String], nested: Bool, path: String, passing: Bool = true,
	arguments suppliedArguments: [[String: Any]]? = nil,
	results suppliedResults: [[String: Any]]? = nil, images: [Int: Data] = [:]
) throws
	-> (session: Data, journal: Data)
{
	var messages: [[String: Any]] = [], events: [[String: Any]] = []
	for (index, name) in names.enumerated() {
		let rootID = "call-\(index)", id = nested ? "call-\(index)/1" : rootID
		let arguments: [String: Any] =
			suppliedArguments?[index] ?? (name == "test" ? [:] : ["path": path])
		let rootArgs: [String: Any] = nested ? ["code": "fixture"] : arguments
		let tool = nested ? "codemode" : name
		let result: [String: Any] =
			suppliedResults?[index]
			?? (name == "test"
				? ["status": passing ? "passed" : "failed", "exitCode": passing ? 0 : 1] : [:])
		let text = String(decoding: try JSONSerialization.data(withJSONObject: result), as: UTF8.self)
		let rootText = nested ? "Script completed" : text
		messages.append([
			"type": "message",
			"message": [
				"role": "assistant",
				"content": [
					["type": "toolCall", "id": rootID, "name": tool, "arguments": rootArgs]
				],
			],
		])
		var message: [String: Any] = [
			"role": "toolResult", "toolCallId": rootID, "toolName": tool,
			"isError": false, "content": [["type": "text", "text": rootText]],
		]
		if let image = images[index] {
			message["content"] = [
				["type": "text", "text": rootText],
				["type": "image", "mimeType": "image/png", "data": image.base64EncodedString()],
			]
		}
		if nested {
			message["nestedCalls"] = [
				"complete": true,
				"calls": [
					["id": id, "name": name, "arguments": arguments, "status": "ok"]
				],
			]
		} else {
			message["details"] = ["result": result]
		}
		messages.append(["type": "message", "message": message])
		func start(_ callID: String, _ toolName: String, _ args: [String: Any]) throws {
			events.append([
				"toolStarted": [
					"id": callID, "name": toolName,
					"text": String(decoding: try JSONSerialization.data(withJSONObject: args), as: UTF8.self),
				]
			])
		}
		func end(_ callID: String, _ toolName: String, _ output: String) {
			events.append([
				"toolFinished": ["id": callID, "name": toolName, "text": output, "isError": false]
			])
		}
		try start(rootID, tool, rootArgs)
		if nested { try start(id, name, arguments); end(id, name, text) }
		end(rootID, tool, rootText)
	}
	return (
		try evidenceJSONL(messages),
		try evidenceJSONL(
			events.enumerated().map {
				["sequence": $0.offset, "event": $0.element]
			})
	)
}

private func evidenceFixture(nested: Bool, mutation: String = "") throws
	-> (session: Data, journal: Data)
{
	let id = nested ? "outer/1" : "test-1"
	let result: [String: Any] = ["status": "passed", "exitCode": 0]
	let text = String(
		decoding: try JSONSerialization.data(withJSONObject: result, options: [.sortedKeys]),
		as: UTF8.self)
	let name = nested ? "codemode" : "test"
	let rootID = nested ? "outer" : id
	let args: [String: Any] = nested ? ["code": "return 'test passed';"] : [:]
	var message: [String: Any] = [
		"role": "toolResult", "toolCallId": rootID, "toolName": name, "isError": false,
		"content": [["type": "text", "text": nested ? "Script completed\ntest passed" : text]],
	]
	if nested {
		var child: [String: Any] = [
			"id": id, "name": "test", "arguments": [String: Any](), "status": "ok",
		]
		if mutation == "wrongArgs" { child["arguments"] = ["unexpected": true] }
		if mutation == "wrongStatus" { child["status"] = "error" }
		if mutation == "unknownChild" { child["id"] = "other/1" }
		if mutation == "failed" { child["status"] = "error" }
		message["nestedCalls"] = ["calls": [child], "complete": mutation != "incomplete"]
	} else {
		message["details"] = ["result": mutation == "wrongDetails" ? ["status": "failed"] : result]
		if mutation == "forgedDirectText" {
			message["content"] = [["type": "text", "text": "{\"status\":\"failed\"}"]]
		}
	}
	var session: [[String: Any]] = [
		[
			"type": "message",
			"message": [
				"role": "assistant",
				"content": [
					["type": "toolCall", "id": rootID, "name": name, "arguments": args]
				],
			],
		],
		["type": "message", "message": message],
	]
	if mutation == "duplicateResult" { session.append(session[1]) }
	if mutation == "collidingRoot" { session.append(contentsOf: session) }
	if mutation == "missingResult" { session.removeLast() }
	var events: [[String: Any]] = []
	func start(_ callID: String, _ tool: String, _ arguments: [String: Any]) throws -> [String: Any] {
		[
			"toolStarted": [
				"id": callID, "name": tool,
				"text": String(
					decoding: try JSONSerialization.data(withJSONObject: arguments, options: [.sortedKeys]),
					as: UTF8.self),
			]
		]
	}
	func end(_ callID: String, _ tool: String, _ output: String, failed: Bool = false) -> [String:
		Any]
	{
		["toolFinished": ["id": callID, "name": tool, "text": output, "isError": failed]]
	}
	events.append(try start(rootID, name, args))
	if nested {
		if mutation != "missingStart" { events.append(try start(id, "test", [:])) }
		if mutation == "duplicateStart" { events.append(try start(id, "test", [:])) }
		if mutation == "outsideParent" {
			events.append(end(rootID, name, "Script completed\ntest passed"))
		}
		let childEnd = end(
			id, mutation == "wrongName" ? "preview" : "test",
			mutation == "forgedText" ? "not JSON" : text, failed: mutation == "failed")
		if mutation != "missingEnd" { events.append(childEnd) }
		if mutation == "duplicateEnd" { events.append(childEnd) }
	}
	if mutation != "outsideParent" {
		events.append(end(rootID, name, nested ? "Script completed\ntest passed" : text))
	}
	let journal = events.enumerated().map { index, event in
		["sequence": index + (mutation == "sequenceGap" ? 1 : 0), "event": event] as [String: Any]
	}
	return (try evidenceJSONL(session), try evidenceJSONL(journal))
}

@Test func toolEvidenceChecksCompleteMultiLevelAncestryOffline() throws {
	for mutation in ["", "failedParent", "missingParent", "collidingChild", "outsideIntermediate"] {
		let fixture = try evidenceFixture(nested: true)
		var records = try fixture.session.split(separator: 10).map {
			try #require(JSONSerialization.jsonObject(with: Data($0)) as? [String: Any])
		}
		var message = try #require(records[1]["message"] as? [String: Any])
		let arguments: [String: Any] = ["code": "nested fixture"]
		let child: [String: Any] = [
			"id": "outer/1/1", "name": "test", "arguments": [:], "status": "ok",
		]
		let parent: [String: Any] = [
			"id": "outer/1", "name": "codemode", "arguments": arguments,
			"status": mutation == "failedParent" ? "error" : "ok",
		]
		var children = mutation == "missingParent" ? [child] : [parent, child]
		if mutation == "collidingChild" { children.append(child) }
		message["nestedCalls"] = ["complete": true, "calls": children]
		records[1]["message"] = message
		var journal = try fixture.journal.split(separator: 10).map {
			try #require(JSONSerialization.jsonObject(with: Data($0)) as? [String: Any])
		}
		var start = try #require(journal[1]["event"] as? [String: Any])
		var started = try #require(start["toolStarted"] as? [String: Any])
		started["id"] = "outer/1/1"; start["toolStarted"] = started
		var end = try #require(journal[2]["event"] as? [String: Any])
		var finished = try #require(end["toolFinished"] as? [String: Any])
		finished["id"] = "outer/1/1"; end["toolFinished"] = finished
		let parentStart: [String: Any] = [
			"toolStarted": [
				"id": "outer/1", "name": "codemode",
				"text": String(
					decoding: try JSONSerialization.data(withJSONObject: arguments), as: UTF8.self),
			]
		]
		let parentEnd: [String: Any] = [
			"toolFinished": [
				"id": "outer/1", "name": "codemode", "text": "Nested script completed",
				"isError": mutation == "failedParent",
			]
		]
		let events =
			mutation == "outsideIntermediate"
			? [journal[0]["event"]!, parentStart, parentEnd, start, end, journal[3]["event"]!]
			: [journal[0]["event"]!, parentStart, start, end, parentEnd, journal[3]["event"]!]
		journal = events.enumerated().map { ["sequence": $0.offset, "event": $0.element] }
		let session = try evidenceJSONL(records), data = try evidenceJSONL(journal)
		if ["missingParent", "collidingChild", "outsideIntermediate"].contains(mutation) {
			#expect(throws: (any Error).self) {
				try ScenarioToolEvidence(session: session, journal: data)
			}
		} else {
			let evidence = try ScenarioToolEvidence(session: session, journal: data)
			let call = try #require(evidence.calls.first { $0.name == "test" })
			#expect(call.succeeded == (mutation != "failedParent"))
			#expect((call.typedResult != nil) == (mutation != "failedParent"))
		}
	}
}

private func evidenceJSONL(_ records: [[String: Any]]) throws -> Data {
	var data = Data()
	for record in records {
		data.append(try JSONSerialization.data(withJSONObject: record, options: [.sortedKeys]))
		data.append(10)
	}
	return data
}
