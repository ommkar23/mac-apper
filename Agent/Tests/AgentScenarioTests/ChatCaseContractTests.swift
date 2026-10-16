// @frontmatter:start
// Checks actual Chat phase inventories, preserved prompts, assertion boundaries and replay ownership offline without starting sessions.
// @frontmatter:end
import Foundation
import Scenario
import Testing

@Suite @MainActor struct ChatCaseContractTests {
	private let directory = URL(fileURLWithPath: #filePath).deletingLastPathComponent()

	private func source(_ file: String) throws -> String {
		try String(contentsOf: directory.appendingPathComponent(file), encoding: .utf8)
	}

	private func compact(_ text: String) -> String {
		text.filter { !$0.isWhitespace }
	}

	private func ordered(_ source: String, _ fragments: [String]) throws {
		var remaining = compact(source)[...]
		for fragment in fragments {
			let range = try #require(
				remaining.range(of: compact(fragment)), "missing or out-of-order contract: \(fragment)")
			remaining = remaining[range.upperBound...]
		}
	}

	@Test func casesHaveReadableDeclarations() throws {
		for file in [
			"ChatConversationTests.swift", "ChatSessionTests.swift", "ChatCapabilitiesTests.swift",
			"ChatReplayTests.swift",
		] {
			#expect(FileManager.default.fileExists(atPath: directory.appendingPathComponent(file).path))
		}
	}

	@Test func actualFactoriesExposeAllMeaningfulPhasesWithoutAcquisition() throws {
		let cases = [
			ChatModelCases.greetingCase(), ChatModelCases.countryNewsCase(),
			ChatModelCases.followUpCase(),
			ChatModelCases.disconnectReplayCase(), ChatModelCases.resumeCase(),
			ChatModelCases.isolationCase(),
			ChatModelCases.abortReuseCase(), ChatModelCases.capabilitiesCase(),
		]
		let expected: [[String]] = [
			[
				"submit owned greeting request", "await bounded structured greeting",
				"verify greeting and opaque marker", "verify one greeting user request",
			],
			[
				"submit owned Japan news request", "validate five bounded recent Japan stories",
				"verify actual news search and fetch evidence",
			],
			[
				"submit owned initial Japan news request", "validate initial five bounded stories",
				"verify initial search and fetch evidence", "retain the validated third story",
				"submit unchanged third-story expansion request", "await bounded structured expansion",
				"verify unchanged third-story identity", "verify expanded summary growth and bound",
				"verify two follow-up user requests",
			],
			[
				"submit owned sequential-fetch replay request",
				"await active work and capture original replay identity",
				"detach workspace without stopping Pi and capture cursor",
				"await detached journal advancement within 120 seconds",
				"own production replay runtime and subscriber before waiting",
				"await completed replay and verify original process continuity",
				"compare first contiguous journal and replay transcript before reopening",
				"retain subscriber and reopen original workspace",
				"submit original recall question after first replay comparison", "verify recalled marker",
				"compare later push on the same subscriber with the complete journal",
			],
			[
				"submit owned private-marker request", "verify initial private recall",
				"capture saved conversation and original Pi PID", "stop original Pi session",
				"open saved conversation disconnected", "submit saved-conversation recall question",
				"verify resumed recall and same file with new Pi",
			],
			[
				"submit Japan isolation request without awaiting answer",
				"submit France isolation request before either answer",
				"verify distinct concurrent sessions and Pi processes",
				"verify Japan response and exclude France marker everywhere",
				"verify France response and exclude Japan marker everywhere",
				"reject foreign-session history through scoped production adapter",
			],
			[
				"submit owned long-running news request",
				"await active work and capture pre-abort identity",
				"abort without stopping Pi and await nonbusy state", "submit no-tool reuse request",
				"verify recall on same session and same Pi process",
			],
			[
				"capture UUID-project baseline before submission",
				"submit owned fetched-page capabilities request",
				"verify captured codemode-only launch arguments", "validate bounded fetched-page response",
				"verify actual capabilities search and fetch evidence",
				"verify no UUID projects or app scaffold were created",
			],
		]
		#expect(cases.map(\.name) == ChatModelCases.names)
		for (testCase, steps) in zip(cases, expected) {
			// Introspect declarations only. Never execute a live closure to discover its phases.
			let actual = try #require(
				Mirror(reflecting: testCase).children.first { $0.label == "declarations" }?.value
					as? [String])
			#expect(
				actual == ["start absolute Chat case budget"] + steps + [
					"audit completed Chat presentation", "release Chat resources",
					"close auxiliary resources then clean every owned session",
				])
		}
	}

	@Test func originalConversationPromptsAndBoundedAssertionsRemain() throws {
		let text = try source("ChatConversationTests.swift")
		#expect(
			text.contains(
				#"Do not use tools. Reply ONLY JSON with exactly {\"greeting\":\"Hello\",\"marker\":\"\(marker)\"}."#
			))
		try ordered(
			text,
			[
				"keys: [\"greeting\", \"marker\"]", "c.reply[\"greeting\"] as? String == \"Hello\"",
				"c.reply[\"marker\"] as? String == c.marker", "session.audit().userTexts.count == 1",
				"static func countryNewsCase", "CountryNews.validate(",
				"session.successfulTools.isSuperset",
				"static func followUpCase", "c.news = try CountryNews.validate(",
				"session.successfulTools.isSuperset",
				"c.third = news.items[2]", "try await session.submit(",
				"Expand item 3 from your previous five-item news list, using the same story. Return ONLY JSON with exactly",
				#"{"title":"original title verbatim","sourceURL":"original source URL verbatim","summary":"expanded summary"}."#,
				"Do not choose another story. Make the expanded summary 200-300 words, longer than the original summary.",
				"keys: [\"title\", \"sourceURL\", \"summary\"]",
				"c.reply[\"title\"] as? String == third.title",
				"c.reply[\"sourceURL\"] as? String == third.sourceURL",
				"summary.utf8.count > third.summary.utf8.count + 100 && summary.utf8.count <= 6000",
				"session.audit().userTexts.count == 2",
			])
		#expect(text.components(separatedBy: "newsPrompt(\"Japan\")").count == 3)
		#expect(
			text.components(separatedBy: "\"mcp__parallel__web_search\", \"mcp__parallel__web_fetch\"")
				.count == 3)
	}

	@Test func originalSessionPromptsAndOrderingRemain() throws {
		let text = try source("ChatSessionTests.swift")
		for prompt in [
			#"Remember my country Japan and private recall marker \(token). Do not use tools. Reply only JSON {\"country\":\"Japan\",\"token\":\"\(token)\"}."#,
			"What country and private recall marker did I ask you to remember? Return only JSON with country and token fields. Do not search or guess.",
			#"Search current news about \(country), extract a selected search result, and return only JSON with exactly country, token, title, sourceURL, summary. country must be \(country) and token must be \(token). Include one story and a short summary. Use both Parallel MCP web_search and web_fetch through codemode. No commentary or introduction."#,
			"Search current Japan news, then extract ten different result URLs one at a time. Read every source before producing a detailed report. Use Parallel MCP tools through codemode, do not answer from memory.",
			#"Do not use tools. Return only JSON {\"country\":\"Japan\",\"token\":\"\(token)\"}."#,
		] { #expect(text.contains(prompt)) }
		try ordered(
			text,
			[
				"c.oldPID = try session.runningPi().pid", ".stop()",
				"await session.workspace.openSession(file, in: project)", "!session.workspace.connected",
				"session.file == file", "session.runningPi().pid != oldPID",
			])
		try ordered(
			text,
			[
				"c.first = try await c.sessions.create", "c.second = try await c.sessions.create",
				"a.id != b.id", "a.runningPi().pid != b.runningPi().pid",
				"checkIsolatedReply(try #require(c.first)", "checkIsolatedReply(try #require(c.second)",
				"OpenXPCGeneratedClient(projectID: project, sessionID: scope, serviceName: service)",
				"sessionID: try b.id.uuidString.lowercased()", "projectPath: try a.project.path",
				"catch OpenXPCGeneratedFailure.remoteFailure {}",
			])
		try ordered(
			text,
			[
				"try await session.waitUntilActive()", "c.id = try session.id",
				"c.stamp = try session.processIdentity(pid)", "try await session.runtime.abort()",
				"session.wait(timeout: 30)", "try await session.submit(", "session.id == id",
				"session.processIdentity(pid) == stamp",
			])
		for assertion in [
			"session.workspace.sessionFile == file", "!session.workspace.messages.isEmpty",
			"keys: [\"country\", \"token\", \"title\", \"sourceURL\", \"summary\"]",
			"json[\"country\"] as? String == country && json[\"token\"] as? String == token",
			"!(json[\"title\"] as? String ?? \"\").isEmpty",
			"!(json[\"summary\"] as? String ?? \"\").isEmpty",
			"validURL(json[\"sourceURL\"] as? String ?? \"\")", "session.successfulTools.isSuperset",
			"!session.workspace.messages.contains(where: { $0.text.contains(foreign) })",
			"audit.userTexts.contains(where: { $0.contains(token) })",
			"!audit.userTexts.contains(where: { $0.contains(foreign) })",
			"!journal.contains(where: { eventContains($0.event, text: foreign) })",
		] { #expect(compact(text).contains(compact(assertion))) }
		#expect(!text.contains("catch {}"))
	}

	@Test func capabilitiesCaptureBaselineBeforeSubmissionAndRetainEveryCheck() throws {
		let text = try source("ChatCapabilitiesTests.swift")
		try ordered(
			text,
			[
				"c.before = try uuidProjects(c.root)", "c.sessions.create(capabilitiesPrompt)",
				"session.runningPi().arguments",
				"object(try await session.answer(), keys: [\"sourceURL\", \"summary\"])",
				"session.successfulTools.isSuperset", "uuidProjects(c.root) == before",
			])
		for fragment in [
			#"--tools codemode(?:\s|$)"#, "AgentExtensions/parallel-codemode.ts",
			"!args.contains(\"Web.app\")",
			"--no-context-files", "--no-skills", "--no-prompt-templates", "args.contains(flag)",
			"validURL(json[\"sourceURL\"] as? String ?? \"\")",
			".trimmingCharacters(in: .whitespacesAndNewlines).isEmpty",
			"\"codemode\", \"mcp__parallel__web_search\", \"mcp__parallel__web_fetch\"",
			"[\"Package.swift\", \"app-manifest.json\", \"Sources\"]", "!FileManager.default.fileExists(",
		] { #expect(compact(text).contains(compact(fragment))) }
	}

	@Test func replayOwnsResourcesAndComparesBeforeReopeningOnSameSubscriber() throws {
		let text = try source("ChatReplayTests.swift")
		#expect(
			text.contains(
				#"Use Parallel MCP web_search through codemode to find current Japan news. Use web_fetch on three different result URLs sequentially. Read all three. Remember recall marker \(token). Then return only JSON with token and summary. No commentary or introduction."#
			))
		#expect(
			text.contains(
				"Return only JSON with country Japan and the token containing the recall marker I gave in my previous request. Do not repeat the news or use tools."
			))
		try ordered(
			text,
			[
				"try #require(session.workspace.busy)", "try #require(await session.workspace.shutdown())",
				"#expect(!session.workspace.connected)",
				"c.detachedCursor = try await session.allHistory().count", ".seconds(120)",
				"Task.checkCancellation()", "ContinuousClock.now < deadline",
				"Task.sleep(for: .milliseconds(100))",
				"let runtime = AgentXPCRuntime(transport: AgentServiceXPCAdapter())", "c.ownCleanup {",
				"await runtime.detach()", "#expect(detached)", "try await runtime.start(",
				"replayHistory: true", "let replay = ModelReplay(stream)",
				"c.ownCleanup { await replay.close() }", "c.replay = replay",
				"replay.state.status == \"Completed\"", "let firstJournal = try await session.allHistory()",
				"session.wait(timeout: 10)", "replay.events == firstJournal.map", "replay.state.transcript",
				"replay.state.liveDetails", "session.successfulTools.isSuperset",
				"c.countBeforePush = replay.events.count",
				"await session.workspace.openSession(file, in: project)",
				"try #require(session.workspace.connected)", "session.workspace.sessionFile == file",
				"session.processIdentity(pid) == stamp", "try await session.submit(",
				"let completeJournal = try await session.allHistory()", "session.wait(timeout: 10)",
				"replay.events.count > countBeforePush", "replay.events == completeJournal.map",
			])
		for fragment in [
			"events.count < 8192", "events.append(event); state.accept(event)", "await task?.value",
			"firstJournal.map(\\.sequence) == Array(0..<firstJournal.count)",
			"completeJournal.map(\\.sequence) == Array(0..<completeJournal.count)",
			"if case .textDelta(let text) = event.event { return text }; return nil",
			"replay.failed || replay.events.count >= firstJournal.count", "try #require(!replay.failed)",
			"replay.failed || replay.events.count >= completeJournal.count", "#expect(!replay.failed)",
		] { #expect(compact(text).contains(compact(fragment))) }
		#expect(text.components(separatedBy: "ModelReplay(stream)").count == 2)
		#expect(text.components(separatedBy: "session.processIdentity(pid) == stamp").count == 3)
		for mapping in [
			".response(id: id, command: command, success: success, error: error)", ".textDelta(text)",
			".tasksUpdated(tasks)",
			".toolStarted(id: id, name: name, argumentsJSON: text)",
			".toolUpdated(id: id, name: name, text: text)",
			".toolFinished(id: id, name: name, text: text, isError: error)", ".notification(text)",
			".extensionError(text)", "case .settled: return .settled",
		] { #expect(text.contains(mapping)) }
	}
}
