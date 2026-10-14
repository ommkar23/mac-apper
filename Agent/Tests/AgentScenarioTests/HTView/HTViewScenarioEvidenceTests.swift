// @frontmatter:start
// Exercises HTView authored-Test and Build/Run evidence audits with offline journals, parsed Swift fixtures, and scoped nonexecuted files.
// @frontmatter:end
import Foundation
import Scenario
import Testing

@Test func htViewScenarioEvidenceAcceptsLatestAuthoredTestsOffline() throws {
	let compiler = try SDKCompiler.resolve()
	for nested in [false, true] {
		for names in [["write", "test"], ["write", "test", "edit", "test"]] {
			let fixture = try HTViewScenarioEvidenceFixture()
			defer { fixture.remove() }
			try fixture.writeTests(htViewAuthoredTestSource)
			let records = try orderedEvidenceFixture(
				names: names, nested: nested, path: fixture.testPath)
			let session = try storeAuditFixture(records, project: fixture.project)
			let evidence = try ScenarioToolEvidence(session: session)
			#expect(try evidence.testedSourcePaths(project: fixture.project) == [fixture.testPath])
			try verifyHTViewTesting(session: session, project: fixture.project, compiler: compiler)
		}
	}
}

@Test func htViewScenarioEvidenceRejectsPassingTestBeforeFinalAppEditOffline() throws {
	let compiler = try SDKCompiler.resolve()
	let fixture = try HTViewScenarioEvidenceFixture()
	defer { fixture.remove() }
	try fixture.writeTests(htViewAuthoredTestSource)
	let records = try orderedEvidenceFixture(
		names: ["write", "test", "edit"], nested: false, path: fixture.testPath)
	var messages = try htViewEvidenceRecords(records.session)
	var journal = try htViewEvidenceRecords(records.journal)
	let appPath = "Sources/AppViews/DocumentWebView.swift"
	var message = try #require(messages[4]["message"] as? [String: Any])
	var content = try #require(message["content"] as? [[String: Any]])
	var arguments = try #require(content[0]["arguments"] as? [String: Any])
	arguments["path"] = appPath; content[0]["arguments"] = arguments
	message["content"] = content; messages[4]["message"] = message
	for index in journal.indices {
		var event = try #require(journal[index]["event"] as? [String: Any])
		if var start = event["toolStarted"] as? [String: Any], start["id"] as? String == "call-2" {
			start["text"] = String(
				decoding: try JSONSerialization.data(withJSONObject: arguments), as: UTF8.self)
			event["toolStarted"] = start; journal[index]["event"] = event
		}
	}
	let session = try storeAuditFixture(
		(try htViewEvidenceJSONL(messages), try htViewEvidenceJSONL(journal)), project: fixture.project)
	let evidence = try ScenarioToolEvidence(session: session)
	#expect(try evidence.testedSourcePaths(project: fixture.project) == [fixture.testPath])
	htViewExpectAuditRejection("AppViews edit after Test") {
		try verifyHTViewTesting(session: session, project: fixture.project, compiler: compiler)
	}
}

@Test(arguments: [
	"untouchedStarter", "rewrittenStarter", "commentStringDecoys", "nonTestDecoy",
	"testNameDecoy", "noExpect", "openingOnly", "errorsOnly", "laterEdit", "booleanExitCode",
	"failedRoot", "failedIntermediate", "missingImport", "malformedSource", "oversizedSource",
	"missingSource", "sourceLink", "sourceDirectoryLink",
])
func htViewScenarioEvidenceRejectsInvalidAuthoredTestsOffline(mutation: String) throws {
	let compiler = try SDKCompiler.resolve()
	for nested in [false, true] {
		if mutation == "failedRoot" || mutation == "failedIntermediate", !nested { continue }
		let fixture = try HTViewScenarioEvidenceFixture()
		defer { fixture.remove() }
		var source = htViewAuthoredTestSource
		var names = ["write", "test"]
		var results: [[String: Any]]? = nil
		switch mutation {
		case "untouchedStarter": names = ["test"]; source = htViewStarterTestSource
		case "rewrittenStarter": source = htViewStarterTestSource
		case "commentStringDecoys":
			source = """
				import Testing
				// @Test func loadDocument() { #expect(model.errorMessage == nil) }
				@Test func unrelated() {
				    let text = "model.openDocument(); model.errorMessage; #expect(model.html != nil)"
				    #expect(!text.isEmpty)
				}
				"""
		case "nonTestDecoy":
			source =
				htViewAuthoredTestSource.replacingOccurrences(of: "@Test ", with: "")
				+ "\n@Test func unrelated() { #expect(true) }\n"
		case "testNameDecoy":
			source = "import Testing\n@Test func openDocumentError() { #expect(true) }\n"
		case "noExpect":
			source = htViewAuthoredTestSource.replacingOccurrences(of: "#expect", with: "print")
		case "openingOnly":
			source = "import Testing\n@Test func opening() { #expect(model.documentURL != nil) }\n"
		case "errorsOnly":
			source = "import Testing\n@Test func errors() { #expect(model.errorMessage != nil) }\n"
		case "laterEdit": names.append("edit")
		case "booleanExitCode": results = [[:], ["status": "passed", "exitCode": false]]
		case "missingImport":
			source = htViewAuthoredTestSource.replacingOccurrences(of: "import Testing", with: "")
		case "malformedSource": source = "import Testing\n@Test func broken( {\n"
		case "oversizedSource": source += "\n//" + String(repeating: "x", count: 65_537)
		case "failedRoot", "failedIntermediate", "missingSource", "sourceLink", "sourceDirectoryLink":
			break
		default: throw ScenarioFailure.message("Unknown HTView Test evidence mutation")
		}
		try fixture.writeTests(source)
		let testSource = fixture.project.appendingPathComponent(fixture.testPath)
		if mutation == "missingSource" { try FileManager.default.removeItem(at: testSource) }
		if mutation == "sourceLink" { try fixture.link(testSource) }
		if mutation == "sourceDirectoryLink" {
			try fixture.link(testSource.deletingLastPathComponent())
		}
		var records = try orderedEvidenceFixture(
			names: names, nested: nested, path: fixture.testPath, results: results)
		if mutation == "failedRoot" || mutation == "failedIntermediate" {
			records = try htViewFailAncestor(
				records, index: 1, intermediate: mutation == "failedIntermediate")
		}
		let session = try storeAuditFixture(records, project: fixture.project)
		// Establish valid correlation before the domain rejection; malformed fixtures cannot substitute.
		let evidence = try ScenarioToolEvidence(session: session)
		if ["untouchedStarter", "laterEdit", "booleanExitCode", "failedRoot", "failedIntermediate"]
			.contains(mutation)
		{
			#expect(try evidence.testedSourcePaths(project: fixture.project).isEmpty)
		} else {
			#expect(try evidence.testedSourcePaths(project: fixture.project) == [fixture.testPath])
		}
		htViewExpectAuditRejection("authored tests: \(mutation), nested=\(nested)") {
			try verifyHTViewTesting(session: session, project: fixture.project, compiler: compiler)
		}
	}
}

@Test func htViewScenarioEvidenceAcceptsScopedBuildRunOffline() throws {
	for nested in [false, true] {
		let fixture = try HTViewScenarioEvidenceFixture()
		defer { fixture.remove() }
		// The audit does not prescribe global tool order; Run can precede a successful Build.
		for names in [["build", "run"], ["run", "build"]] {
			let results = names.map { $0 == "build" ? fixture.build : fixture.run }
			let records = try orderedEvidenceFixture(
				names: names, nested: nested, path: "", results: results)
			let session = try storeAuditFixture(records, project: fixture.project)
			let evidence = try ScenarioToolEvidence(session: session)
			#expect(
				try htViewLaunchBinary(evidence: evidence, project: fixture.project) == fixture.binary)
		}
	}
}

@Test(arguments: [
	"missingBuild", "missingRun", "buildTarget", "runTarget", "emptyBuildSummary",
	"absoluteRun", "traversalRun", "invalidBuildID", "wrongApp", "emptyComponent",
	"backslash", "nul", "executableLink", "executableDirectoryLink", "manifestLink",
	"failedRoot", "failedIntermediate",
])
func htViewScenarioEvidenceRejectsInvalidBuildRunOffline(mutation: String) throws {
	for nested in [false, true] {
		if mutation == "failedRoot" || mutation == "failedIntermediate", !nested { continue }
		let fixture = try HTViewScenarioEvidenceFixture()
		defer { fixture.remove() }
		var names = ["build", "run"]
		var build = fixture.build, run = fixture.run
		switch mutation {
		case "missingBuild": names[0] = "read"
		case "missingRun": names[1] = "read"
		case "buildTarget": build["target"] = "AnotherApp"
		case "runTarget": run["target"] = "AnotherApp"
		case "emptyBuildSummary": build["summary"] = ""
		case "absoluteRun":
			run["relativePath"] = fixture.project.appendingPathComponent(fixture.runPath).path
		case "traversalRun": run["relativePath"] = ".mac-apper/DevBuild/../HTViewApp.app"
		case "invalidBuildID": run["relativePath"] = ".mac-apper/DevBuild/not-a-uuid/HTViewApp.app"
		case "wrongApp": run["relativePath"] = ".mac-apper/DevBuild/\(fixture.buildID)/AnotherApp.app"
		case "emptyComponent":
			run["relativePath"] = fixture.runPath.replacingOccurrences(
				of: "DevBuild/", with: "DevBuild//")
		case "backslash": run["relativePath"] = fixture.runPath + "\\escape"
		case "nul": run["relativePath"] = fixture.runPath + "\0"
		case "executableLink": try fixture.link(fixture.binary)
		case "executableDirectoryLink": try fixture.link(fixture.binary.deletingLastPathComponent())
		case "manifestLink":
			try fixture.link(fixture.project.appendingPathComponent("app-manifest.json"))
		case "failedRoot", "failedIntermediate": break
		default: throw ScenarioFailure.message("Unknown HTView Build/Run evidence mutation")
		}
		var records = try orderedEvidenceFixture(
			names: names, nested: nested, path: "", results: [build, run])
		if mutation == "failedRoot" || mutation == "failedIntermediate" {
			records = try htViewFailAncestor(
				records, index: 1, intermediate: mutation == "failedIntermediate")
		}
		let session = try storeAuditFixture(records, project: fixture.project)
		let evidence = try ScenarioToolEvidence(session: session)
		if mutation == "failedRoot" || mutation == "failedIntermediate" {
			#expect(evidence.calls.first { $0.name == "run" }?.succeeded == false)
		}
		htViewExpectAuditRejection("Build/Run: \(mutation), nested=\(nested)") {
			_ = try htViewLaunchBinary(evidence: evidence, project: fixture.project)
		}
	}
}

private struct HTViewScenarioEvidenceFixture {
	let root: URL
	let project: URL
	let buildID = UUID().uuidString.lowercased()
	let testPath = "Tests/AppModelTests/DocumentBehavior.swift"
	var runPath: String { ".mac-apper/DevBuild/\(buildID)/HTViewApp.app" }
	var binary: URL { project.appendingPathComponent(runPath + "/Contents/MacOS/HTViewApp") }
	var build: [String: Any] { ["target": "HTViewApp", "summary": "Built offline fixture"] }
	var run: [String: Any] { ["target": "HTViewApp", "relativePath": runPath] }

	init() throws {
		root = try ProjectTemporaryDirectory.appending("mac-apper-htview-evidence-\(UUID().uuidString)")
		project = root.appendingPathComponent(UUID().uuidString.lowercased())
		try FileManager.default.createDirectory(
			at: root, withIntermediateDirectories: false, attributes: [.posixPermissions: 0o700])
		do {
			try FileManager.default.createDirectory(at: project, withIntermediateDirectories: false)
			try Data(#"{"executableTarget":"HTViewApp"}"#.utf8).write(
				to: project.appendingPathComponent("app-manifest.json"))
			try FileManager.default.createDirectory(
				at: binary.deletingLastPathComponent(), withIntermediateDirectories: true)
			// A regular file validates metadata only. It is never compiled, made executable or launched.
			try Data("offline executable placeholder".utf8).write(to: binary)
		} catch {
			try? FileManager.default.removeItem(at: root)
			throw error
		}
	}

	func writeTests(_ source: String) throws {
		let file = project.appendingPathComponent(testPath)
		try FileManager.default.createDirectory(
			at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
		try source.write(to: file, atomically: true, encoding: .utf8)
	}

	func link(_ file: URL) throws {
		let destination = root.appendingPathComponent("link-target-\(UUID().uuidString)")
		try FileManager.default.moveItem(at: file, to: destination)
		try FileManager.default.createSymbolicLink(at: file, withDestinationURL: destination)
	}

	func remove() { try? FileManager.default.removeItem(at: root) }
}

private func htViewExpectAuditRejection(_ reason: String, body: () throws -> Void) {
	var rejected = false
	withKnownIssue("Intentional invalid HTView evidence: \(reason)", isIntermittent: true) {
		do { try body() } catch { rejected = true }
	}
	#expect(rejected, "Invalid HTView evidence accepted: \(reason)")
}

// Mutate matching records together, so a successful child has a genuinely failed ancestor.
private func htViewFailAncestor(
	_ fixture: (session: Data, journal: Data), index: Int, intermediate: Bool
) throws -> (session: Data, journal: Data) {
	let rootID = "call-\(index)", childID = rootID + "/1"
	var messages = try htViewEvidenceRecords(fixture.session)
	var journal = try htViewEvidenceRecords(fixture.journal)
	let messageIndex = index * 2 + 1
	var message = try #require(messages[messageIndex]["message"] as? [String: Any])
	if intermediate {
		var nested = try #require(message["nestedCalls"] as? [String: Any])
		var child = try #require((nested["calls"] as? [[String: Any]])?.first)
		child["id"] = childID + "/1"
		let arguments: [String: Any] = ["code": "offline intermediate"]
		nested["calls"] = [
			["id": childID, "name": "codemode", "arguments": arguments, "status": "error"], child,
		]
		message["nestedCalls"] = nested
		let startIndex = try #require(
			journal.firstIndex {
				(($0["event"] as? [String: Any])?["toolStarted"] as? [String: Any])?["id"] as? String
					== childID
			})
		let endIndex = try #require(
			journal.firstIndex {
				(($0["event"] as? [String: Any])?["toolFinished"] as? [String: Any])?["id"] as? String
					== childID
			})
		for (position, key) in [(startIndex, "toolStarted"), (endIndex, "toolFinished")] {
			var event = try #require(journal[position]["event"] as? [String: Any])
			var lifecycle = try #require(event[key] as? [String: Any])
			lifecycle["id"] = childID + "/1"; event[key] = lifecycle; journal[position]["event"] = event
		}
		journal.insert(
			[
				"event": [
					"toolFinished": [
						"id": childID, "name": "codemode", "text": "Intermediate failed", "isError": true,
					]
				]
			], at: endIndex + 1)
		journal.insert(
			[
				"event": [
					"toolStarted": [
						"id": childID, "name": "codemode",
						"text": String(
							decoding: try JSONSerialization.data(withJSONObject: arguments), as: UTF8.self),
					]
				]
			], at: startIndex)
	} else {
		message["isError"] = true
		for index in journal.indices {
			var event = try #require(journal[index]["event"] as? [String: Any])
			if var end = event["toolFinished"] as? [String: Any], end["id"] as? String == rootID {
				end["isError"] = true; event["toolFinished"] = end; journal[index]["event"] = event
			}
		}
	}
	messages[messageIndex]["message"] = message
	journal = journal.enumerated().map { ["sequence": $0.offset, "event": $0.element["event"]!] }
	return (try htViewEvidenceJSONL(messages), try htViewEvidenceJSONL(journal))
}

private func htViewEvidenceRecords(_ data: Data) throws -> [[String: Any]] {
	try data.split(separator: 10).map {
		try #require(JSONSerialization.jsonObject(with: Data($0)) as? [String: Any])
	}
}

private func htViewEvidenceJSONL(_ records: [[String: Any]]) throws -> Data {
	var data = Data()
	for record in records {
		data.append(try JSONSerialization.data(withJSONObject: record, options: [.sortedKeys]))
		data.append(10)
	}
	return data
}

// Compiler parse fixtures are never typechecked or executed as app tests.
private let htViewAuthoredTestSource = """
	import Testing
	import AppModel
	@Test @MainActor func documentOpeningAndRecovery() {
	    let model = ApplicationModel()
	    model.openDocument(URL(fileURLWithPath: "/missing.html"))
	    #expect(model.errorMessage != nil)
	    model.openDocument(URL(fileURLWithPath: "/local.html"))
	    #expect(model.documentURL != nil)
	    #expect(model.errorMessage == nil)
	}
	"""

// Current scaffold initialization and animation checks contain no HTView behavior.
private let htViewStarterTestSource = """
	import Testing
	import AppModel
	@Test @MainActor func normalInitialization() {
	    let model = ApplicationModel()
	    #expect(model.title == "Your app")
	}
	@Test func animationDecision() {
	    let intent = AnimationIntent.transition(trigger: .contentChanged, reduceMotion: false)
	    #expect(intent.phase(at: 0.1)?.curve == .easeInOut)
	    #expect(intent.phase(at: 1) == nil)
	    #expect(AnimationIntent.transition(trigger: .contentChanged, reduceMotion: true).phases.isEmpty)
	}
	"""
