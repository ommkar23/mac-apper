// @frontmatter:start
// Exercises first-request naming correlation and rejection controls with offline journal fixtures.
// @frontmatter:end
import Foundation
import Scenario
import Testing

@Test func createNamingTypedResultOffline() throws {
	for nested in [false, true] {
		let fixture = try orderedEvidenceFixture(
			names: ["set_app_name"], nested: nested, path: "",
			arguments: [["name": "Pebble Counter"]],
			results: [["name": "Pebble Counter", "summary": "App name set to Pebble Counter."]])
		let evidence = try ScenarioToolEvidence(session: fixture.session, journal: fixture.journal)
		let call = try #require(evidence.calls.first { $0.name == "set_app_name" })
		#expect(call.typedResult?["name"] as? String == "Pebble Counter")
	}
}

@Test(arguments: [false, true])
func createNamingEvidenceOffline(nested: Bool) throws {
	let project = try ProjectTemporaryDirectory.appending("naming-audit-\(UUID().uuidString)")
	try FileManager.default.createDirectory(at: project, withIntermediateDirectories: false)
	defer { try? FileManager.default.removeItem(at: project) }
	let source = project.appendingPathComponent("Sources/AppModel/Counter.swift")
	try FileManager.default.createDirectory(
		at: source.deletingLastPathComponent(), withIntermediateDirectories: true)
	try Data("// Offline implementation fixture".utf8).write(to: source)
	#expect(try namingRelativePath(source.path, project: project) == "Sources/AppModel/Counter.swift")
	for mutation in [
		"", "missing", "duplicate", "failed", "wrongName", "missingName", "wrongSummary",
		"wrongDetails", "missingParent", "failedParent", "prematureEdit", "prematureBuild",
		"prematureRun", "failedEarlyEdit", "noImplementation", "scriptOnly", "plistEdit",
		"traversal", "foreignPath", "missingEnd", "incomplete", "missingFile",
	] {
		if !nested && ["missingParent", "failedParent", "incomplete"].contains(mutation) { continue }
		let fixture = try namingFixture(nested: nested, mutation: mutation)
		if mutation.isEmpty {
			let evidence = try ScenarioToolEvidence(session: fixture.session, journal: fixture.journal)
			#expect(
				try verifyCreateNaming(evidence: evidence, project: project, expectedName: "Pebble Counter")
					== "Pebble Counter")
		} else {
			#expect(throws: (any Error).self, "Must reject \(mutation), nested=\(nested)") {
				let evidence = try ScenarioToolEvidence(session: fixture.session, journal: fixture.journal)
				try verifyCreateNaming(evidence: evidence, project: project, expectedName: "Pebble Counter")
			}
		}
	}
}

private func namingFixture(nested: Bool, mutation: String) throws -> (session: Data, journal: Data)
{
	var names = ["set_app_name", "write", "build", "run"]
	if mutation == "missing" { names.removeFirst() }
	if mutation == "duplicate" { names.insert("set_app_name", at: 1) }
	if mutation == "prematureEdit" || mutation == "failedEarlyEdit" { names.insert("edit", at: 0) }
	if mutation == "prematureBuild" { names.insert("build", at: 0) }
	if mutation == "prematureRun" { names.insert("run", at: 0) }
	if mutation == "noImplementation" || mutation == "scriptOnly" {
		names.removeAll { $0 == "write" }
	}
	var result: [String: Any] = [
		"name": "Pebble Counter", "summary": "App name set to Pebble Counter.",
	]
	if mutation == "wrongName" { result["name"] = "Generated App" }
	if mutation == "missingName" { result.removeValue(forKey: "name") }
	if mutation == "wrongSummary" { result["summary"] = 42 }
	let path =
		mutation == "plistEdit"
		? "Info.plist"
		: mutation == "traversal"
			? "Sources/../Info.plist"
			: mutation == "foreignPath"
				? "/foreign/Sources/Counter.swift"
				: mutation == "missingFile" ? "Sources/Missing.swift" : "Sources/AppModel/Counter.swift"
	let fixture = try orderedEvidenceFixture(
		names: names, nested: nested, path: path,
		arguments: names.map { $0 == "set_app_name" ? ["name": "Pebble Counter"] : ["path": path] },
		results: names.map { $0 == "set_app_name" ? result : [:] })
	var session = try namingRecords(fixture.session), journal = try namingRecords(fixture.journal)
	if ["failed", "failedParent", "failedEarlyEdit"].contains(mutation) {
		// Mutate actual matched transport status, not just the parent's printed script.
		let target = mutation == "failedEarlyEdit" ? "edit" : "set_app_name"
		for index in journal.indices {
			var event = try #require(journal[index]["event"] as? [String: Any])
			if var finish = event["toolFinished"] as? [String: Any],
				finish["name"] as? String == (mutation == "failedParent" ? "codemode" : target)
			{
				finish["isError"] = true; event["toolFinished"] = finish; journal[index]["event"] = event
			}
		}
		for index in session.indices {
			var message = try #require(session[index]["message"] as? [String: Any])
			if message["role"] as? String != "toolResult" { continue }
			if nested && mutation != "failedParent" {
				var metadata = try #require(message["nestedCalls"] as? [String: Any])
				var children = try #require(metadata["calls"] as? [[String: Any]])
				if children[0]["name"] as? String == target { children[0]["status"] = "error" }
				metadata["calls"] = children; message["nestedCalls"] = metadata
			} else if nested || message["toolName"] as? String == target {
				message["isError"] = true
			}
			session[index]["message"] = message
		}
	}
	if ["missingParent", "incomplete", "wrongDetails", "scriptOnly"].contains(mutation) {
		var message = try #require(session[1]["message"] as? [String: Any])
		if mutation == "wrongDetails" {
			if nested {
				// A forged outer script never replaces the actual child result.
				message["nestedCalls"] = ["complete": true, "calls": []]
			} else {
				message["details"] = ["result": ["name": "Other"]]
			}
		} else if mutation == "scriptOnly" {
			message["content"] = [["type": "text", "text": "set_app_name succeeded: Pebble Counter"]]
		} else {
			message["nestedCalls"] = [
				"complete": mutation != "incomplete",
				"calls": [
					[
						"id": "call-0/1/1", "name": "set_app_name", "arguments": ["name": "Pebble Counter"],
						"status": "ok",
					]
				],
			]
		}
		session[1]["message"] = message
	}
	if mutation == "missingEnd" {
		journal.removeAll {
			($0["event"] as? [String: Any])?["toolFinished"].map {
				($0 as? [String: Any])?["name"] as? String == "set_app_name"
			} ?? false
		}
		journal = journal.enumerated().map { ["sequence": $0.offset, "event": $0.element["event"]!] }
	}
	return (try namingJSONL(session), try namingJSONL(journal))
}

private func namingRecords(_ data: Data) throws -> [[String: Any]] {
	try data.split(separator: 10).map {
		try #require(JSONSerialization.jsonObject(with: Data($0)) as? [String: Any])
	}
}

private func namingJSONL(_ records: [[String: Any]]) throws -> Data {
	var data = Data()
	for record in records {
		data.append(try JSONSerialization.data(withJSONObject: record)); data.append(10)
	}
	return data
}

@Test func createNamingFinalMetadataOffline() throws {
	let project = try ProjectTemporaryDirectory.appending("naming-plist-\(UUID().uuidString)")
	try FileManager.default.createDirectory(at: project, withIntermediateDirectories: false)
	defer { try? FileManager.default.removeItem(at: project) }
	let plist = project.appendingPathComponent("Info.plist")
	for name in ["Pebble Counter", "Generated App", "Other"] {
		try PropertyListSerialization.data(
			fromPropertyList: ["CFBundleName": name, "CFBundleDisplayName": name], format: .xml,
			options: 0
		).write(to: plist)
		if name == "Pebble Counter" {
			try verifyNamingPlist(plist, expectedName: name)
		} else {
			#expect(throws: (any Error).self) {
				try verifyNamingPlist(plist, expectedName: "Pebble Counter")
			}
		}
	}
	let linked = project.appendingPathComponent("Sources")
	try FileManager.default.createSymbolicLink(at: linked, withDestinationURL: project)
	#expect(throws: (any Error).self) {
		try namingRelativePath("Sources/Counter.swift", project: project)
	}
	#expect(throws: (any Error).self) {
		try verifyNamingPlist(
			linked.appendingPathComponent("Info.plist"), expectedName: "Pebble Counter")
	}
	try verifyNoNativeNamingNotification(
		journal: namingJSONL([["event": ["toolFinished": ["name": "run", "text": "launched"]]]]))
	#expect(throws: (any Error).self) {
		try verifyNoNativeNamingNotification(
			journal: namingJSONL([["event": ["notification": ["_0": "MAC_APPER_RENAMED:Pebble Counter"]]]]
			))
	}
}
