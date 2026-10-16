// @frontmatter:start
// Declares stopped-session resume, concurrent Chat isolation and same-process abort/reuse phases through production XPC.
// @frontmatter:end
import AgentMacosClient
import AgentMacosClientModel
import Foundation
import Scenario
import Testing

@MainActor private final class ResumeContext: ChatCaseContext {
	let token = UUID().uuidString
	var session: ChatModelSession?
	var file: URL?
	var project: URL?
	var oldPID: String?
}

@MainActor private final class IsolationContext: ChatCaseContext {
	let firstToken = UUID().uuidString
	let secondToken = UUID().uuidString
	var first: ChatModelSession?
	var second: ChatModelSession?
}

@MainActor private final class AbortReuseContext: ChatCaseContext {
	let token = UUID().uuidString
	var session: ChatModelSession?
	var id: UUID?
	var pid: String?
	var stamp: String?
}

extension ChatModelCases {
	static func resumeCase() -> ScenarioCase<ChatCollection> {
		makeCase(
			"chat-resume", context: ResumeContext.init,
			setup: [
				step("submit owned private-marker request") { c in
					let token = c.token
					c.session = try await c.sessions.create(
						"Remember my country Japan and private recall marker \(token). Do not use tools. Reply only JSON {\"country\":\"Japan\",\"token\":\"\(token)\"}."
					)
				}
			],
			behaviour: [
				step("verify initial private recall") { c in
					let session = try #require(c.session)
					try checkRecall(try await session.answer(), country: "Japan", token: c.token)
				},
				step("capture saved conversation and original Pi PID") { c in
					let session = try #require(c.session)
					c.file = try session.file
					c.project = try session.project
					c.oldPID = try session.runningPi().pid
				},
				step("stop original Pi session") { c in
					try await #require(c.session).stop()
				},
				step("open saved conversation disconnected") { c in
					let session = try #require(c.session)
					let file = try #require(c.file), project = try #require(c.project)
					await session.workspace.openSession(file, in: project)
					#expect(session.workspace.sessionFile == file)
					#expect(!session.workspace.messages.isEmpty)
					#expect(!session.workspace.connected)
				},
				step("submit saved-conversation recall question") { c in
					let session = try #require(c.session)
					try await session.submit(
						"What country and private recall marker did I ask you to remember? Return only JSON with country and token fields. Do not search or guess."
					)
				},
				step("verify resumed recall and same file with new Pi") { c in
					let session = try #require(c.session)
					let file = try #require(c.file), oldPID = try #require(c.oldPID)
					try checkRecall(try await session.answer(), country: "Japan", token: c.token)
					#expect(try session.file == file)
					#expect(try session.runningPi().pid != oldPID)
				},
			])
	}

	static func isolationCase() -> ScenarioCase<ChatCollection> {
		makeCase(
			"chat-session-isolation", context: IsolationContext.init,
			setup: [
				step("submit Japan isolation request without awaiting answer") { c in
					c.first = try await c.sessions.create(isolationPrompt("Japan", c.firstToken))
				},
				step("submit France isolation request before either answer") { c in
					c.second = try await c.sessions.create(isolationPrompt("France", c.secondToken))
				},
			],
			behaviour: [
				step("verify distinct concurrent sessions and Pi processes") { c in
					let a = try #require(c.first), b = try #require(c.second)
					#expect(try a.id != b.id)
					#expect(try a.runningPi().pid != b.runningPi().pid)
				},
				step("verify Japan response and exclude France marker everywhere") { c in
					try await checkIsolatedReply(
						try #require(c.first), country: "Japan", token: c.firstToken, foreign: c.secondToken)
				},
				step("verify France response and exclude Japan marker everywhere") { c in
					try await checkIsolatedReply(
						try #require(c.second), country: "France", token: c.secondToken, foreign: c.firstToken)
				},
				step("reject foreign-session history through scoped production adapter") { c in
					let a = try #require(c.first), b = try #require(c.second)
					let scope = try a.id, service = try serviceIdentifier()
					let restricted = AgentServiceXPCAdapter(makeClient: { project, _ in
						OpenXPCGeneratedClient(projectID: project, sessionID: scope, serviceName: service)
					})
					do {
						_ = try await restricted.history(
							.init(sessionID: try b.id.uuidString.lowercased(), cursor: 0),
							projectPath: try a.project.path)
						Issue.record("Agent accepted a foreign-session history request")
					} catch OpenXPCGeneratedFailure.remoteFailure {}
				},
			])
	}

	private static func isolationPrompt(_ country: String, _ token: String) -> String {
		"Search current news about \(country), extract a selected search result, and return only JSON with exactly country, token, title, sourceURL, summary. country must be \(country) and token must be \(token). Include one story and a short summary. Use both Parallel MCP web_search and web_fetch through codemode. No commentary or introduction."
	}

	private static func checkIsolatedReply(
		_ session: ChatModelSession, country: String, token: String, foreign: String
	) async throws {
		let answer = try await session.answer()
		let json = try object(answer, keys: ["country", "token", "title", "sourceURL", "summary"])
		#expect(json["country"] as? String == country && json["token"] as? String == token)
		#expect(!(json["title"] as? String ?? "").isEmpty)
		#expect(!(json["summary"] as? String ?? "").isEmpty)
		#expect(validURL(json["sourceURL"] as? String ?? ""))
		#expect(
			try session.successfulTools.isSuperset(of: [
				"codemode", "mcp__parallel__web_search", "mcp__parallel__web_fetch",
			]))
		#expect(!session.workspace.messages.contains(where: { $0.text.contains(foreign) }))
		let audit = try session.audit()
		#expect(audit.userTexts.contains(where: { $0.contains(token) }))
		#expect(!audit.userTexts.contains(where: { $0.contains(foreign) }))
		let journal = try await session.allHistory()
		#expect(!journal.contains(where: { eventContains($0.event, text: foreign) }))
	}

	static func abortReuseCase() -> ScenarioCase<ChatCollection> {
		makeCase(
			"chat-abort-reuse", context: AbortReuseContext.init,
			setup: [
				step("submit owned long-running news request") { c in
					c.session = try await c.sessions.create(
						"Search current Japan news, then extract ten different result URLs one at a time. Read every source before producing a detailed report. Use Parallel MCP tools through codemode, do not answer from memory."
					)
				}
			],
			behaviour: [
				step("await active work and capture pre-abort identity") { c in
					let session = try #require(c.session)
					try await session.waitUntilActive()
					c.id = try session.id
					let pid = try session.runningPi().pid
					c.pid = pid
					c.stamp = try session.processIdentity(pid)
				},
				step("abort without stopping Pi and await nonbusy state") { c in
					let session = try #require(c.session)
					try await session.runtime.abort()
					try await session.wait(timeout: 30) { !session.workspace.busy }
				},
				step("submit no-tool reuse request") { c in
					let session = try #require(c.session), token = c.token
					try await session.submit(
						"Do not use tools. Return only JSON {\"country\":\"Japan\",\"token\":\"\(token)\"}.")
				},
				step("verify recall on same session and same Pi process") { c in
					let session = try #require(c.session)
					let id = try #require(c.id), pid = try #require(c.pid), stamp = try #require(c.stamp)
					try checkRecall(try await session.answer(), country: "Japan", token: c.token)
					#expect(try session.id == id)
					#expect(try session.processIdentity(pid) == stamp)
				},
			])
	}
}
