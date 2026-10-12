// @frontmatter:start
// Asserts client-model Chat greetings, MCP news, follow-up, resume, isolation, abort/reuse, and codemode-only capabilities.
// @frontmatter:end
import AgentMacosClient
import AgentMacosClientModel
import AgentScenarioSupport
import Foundation
import Scenario
import Testing

@MainActor enum ChatModelCases {
	static let names = [
		"chat-model-greeting", "country-news-japan", "chat-follow-up", "chat-disconnect-replay",
		"chat-resume", "chat-session-isolation", "chat-abort-reuse", "chat-capabilities",
	]

	static func run(_ name: String, sessions: ChatModelSessions) async throws {
		switch name {
		case "chat-model-greeting": try await greeting(sessions)
		case "country-news-japan": try await countryNews(sessions)
		case "chat-follow-up": try await followUp(sessions)
		case "chat-disconnect-replay": try await disconnectReplay(sessions)
		case "chat-resume": try await resume(sessions)
		case "chat-session-isolation": try await isolation(sessions)
		case "chat-abort-reuse": try await abortReuse(sessions)
		case "chat-capabilities": try await capabilities(sessions)
		default: throw ScenarioFailure.message("unknown Chat case")
		}
		for session in sessions.owned {
			#expect(try session.audit().profile == .required)
			#expect(session.workspace.selectedAgentID == "chat")
			#expect(session.workspace.isChatOnly)
			#expect(session.workspace.state.status == "Completed")
		}
	}

	static func newsPrompt(_ country: String) -> String {
		let today = ISO8601DateFormatter().string(from: Date()).prefix(10)
		return """
			Find five distinct important news stories about \(country) published within the last seven days, as of \(today) UTC.
			You MUST use Parallel MCP web_search through codemode to find current news and web_fetch to read selected search-result URLs.
			Use actual publication dates, never invent them. Select exactly five distinct stories with distinct source URLs.
			Return ONLY JSON, no Markdown fences, commentary, or introduction, with exactly these fields:
			{"country":"\(country)","items":[{"title":"...","publishedDate":"YYYY-MM-DD","summary":"...","sourceURL":"https://..."}]}
			There must be exactly five items. Titles at most 256 UTF-8 bytes; summaries at most 2000 UTF-8 bytes;
			source URLs at most 2048 UTF-8 bytes. All publication dates must be within the requested window. No extra fields.
			"""
	}

	static func greeting(_ sessions: ChatModelSessions) async throws {
		let marker = UUID().uuidString
		let session = try await sessions.create(
			"Do not use tools. Reply ONLY JSON with exactly {\"greeting\":\"Hello\",\"marker\":\"\(marker)\"}."
		)
		let value = try object(try await session.answer(), keys: ["greeting", "marker"])
		#expect(value["greeting"] as? String == "Hello")
		#expect(value["marker"] as? String == marker)
		#expect(try session.audit().userTexts.count == 1)
	}
	static func countryNews(_ sessions: ChatModelSessions) async throws {
		let session = try await sessions.create(newsPrompt("Japan"))
		_ = try CountryNews.validate(
			Data(try await session.answer().utf8), country: "Japan", now: Date())
		#expect(
			try session.successfulTools.isSuperset(of: [
				"codemode", "mcp__parallel__web_search", "mcp__parallel__web_fetch",
			]))
	}
	static func followUp(_ sessions: ChatModelSessions) async throws {
		let session = try await sessions.create(newsPrompt("Japan"))
		let news = try CountryNews.validate(
			Data(try await session.answer().utf8), country: "Japan", now: Date())
		#expect(
			try session.successfulTools.isSuperset(of: [
				"codemode", "mcp__parallel__web_search", "mcp__parallel__web_fetch",
			]))
		let third = news.items[2]
		let answer = try await session.prompt(
			"""
			Expand item 3 from your previous five-item news list, using the same story. Return ONLY JSON with exactly
			{"title":"original title verbatim","sourceURL":"original source URL verbatim","summary":"expanded summary"}.
			Do not choose another story. Make the expanded summary 200-300 words, longer than the original summary.
			""")
		let json = try object(answer, keys: ["title", "sourceURL", "summary"])
		#expect(json["title"] as? String == third.title)
		#expect(json["sourceURL"] as? String == third.sourceURL)
		let summary = try #require(json["summary"] as? String)
		#expect(summary.utf8.count > third.summary.utf8.count + 100 && summary.utf8.count <= 6000)
		#expect(try session.audit().userTexts.count == 2)
	}
	static func resume(_ sessions: ChatModelSessions) async throws {
		let token = UUID().uuidString
		let session = try await sessions.create(
			"Remember my country Japan and private recall marker \(token). Do not use tools. Reply only JSON {\"country\":\"Japan\",\"token\":\"\(token)\"}."
		)
		try checkRecall(try await session.answer(), country: "Japan", token: token)
		let file = try session.file, project = try session.project
		let oldPID = try session.runningPi().pid
		try await session.stop()
		await session.workspace.openSession(file, in: project)
		#expect(session.workspace.sessionFile == file)
		#expect(!session.workspace.messages.isEmpty)
		#expect(!session.workspace.connected)
		try checkRecall(
			try await session.prompt(
				"What country and private recall marker did I ask you to remember? Return only JSON with country and token fields. Do not search or guess."
			), country: "Japan", token: token)
		#expect(try session.file == file)
		#expect(try session.runningPi().pid != oldPID)
	}
	static func isolation(_ sessions: ChatModelSessions) async throws {
		let firstToken = UUID().uuidString, secondToken = UUID().uuidString
		func prompt(_ country: String, _ token: String) -> String {
			"Search current news about \(country), extract a selected search result, and return only JSON with exactly country, token, title, sourceURL, summary. country must be \(country) and token must be \(token). Include one story and a short summary. Use both Parallel MCP web_search and web_fetch through codemode. No commentary or introduction."
		}
		let a = try await sessions.create(prompt("Japan", firstToken))
		let b = try await sessions.create(prompt("France", secondToken))
		#expect(try a.id != b.id)
		#expect(try a.runningPi().pid != b.runningPi().pid)
		// Both model submissions are active before waiting for either answer.
		for (session, country, token, foreign) in [
			(a, "Japan", firstToken, secondToken), (b, "France", secondToken, firstToken),
		] {
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
		// Bind the existing production client's envelope to A and ask for B: real service scope rejection.
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
	}
	static func abortReuse(_ sessions: ChatModelSessions) async throws {
		let session = try await sessions.create(
			"Search current Japan news, then extract ten different result URLs one at a time. Read every source before producing a detailed report. Use Parallel MCP tools through codemode, do not answer from memory."
		)
		try await session.waitUntilActive()
		let id = try session.id, pid = try session.runningPi().pid,
			stamp = try session.processIdentity(pid)
		try await session.runtime.abort()
		try await session.wait(timeout: 30) { !session.workspace.busy }
		let token = UUID().uuidString
		try checkRecall(
			try await session.prompt(
				"Do not use tools. Return only JSON {\"country\":\"Japan\",\"token\":\"\(token)\"}."),
			country: "Japan", token: token)
		#expect(try session.id == id)
		#expect(try session.processIdentity(pid) == stamp)
	}
	static let capabilitiesPrompt = """
		Use Parallel MCP web_search through codemode to find the official Example Domain website.
		Then use Parallel MCP web_fetch through codemode on the selected search-result URL.
		Read the fetched page and derive the summary from its fetched content, not just search snippets or memory.
		Return ONLY JSON with exactly sourceURL and summary fields, no Markdown, commentary, or introduction.
		Never create an app or write files.
		"""

	static func capabilities(_ sessions: ChatModelSessions) async throws {
		let root = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".mac-apper")
		let before = try uuidProjects(root)
		let session = try await sessions.create(capabilitiesPrompt)
		let args = try session.runningPi().arguments
		#expect(args.range(of: #"--tools codemode(?:\s|$)"#, options: .regularExpression) != nil)
		#expect(args.contains("AgentExtensions/parallel-codemode.ts"))
		#expect(!args.contains("Web.app"))
		for flag in ["--no-context-files", "--no-skills", "--no-prompt-templates"] {
			#expect(args.contains(flag))
		}
		let json = try object(try await session.answer(), keys: ["sourceURL", "summary"])
		#expect(validURL(json["sourceURL"] as? String ?? ""))
		#expect(
			!(json["summary"] as? String ?? "").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
		#expect(
			try session.successfulTools.isSuperset(of: [
				"codemode", "mcp__parallel__web_search", "mcp__parallel__web_fetch",
			]))
		#expect(try uuidProjects(root) == before)
		for name in ["Package.swift", "app-manifest.json", "Sources"] {
			#expect(
				!FileManager.default.fileExists(
					atPath: try session.project.appendingPathComponent(name).path))
		}
	}

	static func object(_ text: String, keys: Set<String>) throws -> [String: Any] {
		guard
			text.utf8.count <= 60_000,
			let object = try JSONSerialization.jsonObject(with: Data(text.utf8)) as? [String: Any],
			Set(object.keys) == keys
		else { throw ScenarioFailure.message("invalid structured model reply") }
		return object
	}
	static func checkRecall(_ text: String, country: String, token: String) throws {
		let json = try object(text, keys: ["country", "token"])
		#expect(json["country"] as? String == country && json["token"] as? String == token)
	}
	static func validURL(_ text: String) -> Bool {
		guard
			text.utf8.count <= 2048,
			let url = URLComponents(string: text),
			url.scheme == "https" || url.scheme == "http",
			let host = url.host,
			!host.isEmpty,
			url.user == nil,
			url.password == nil
		else { return false }
		return true
	}
	static func uuidProjects(_ root: URL) throws -> Set<String> {
		Set(
			try FileManager.default.contentsOfDirectory(atPath: root.path).filter {
				UUID(uuidString: $0) != nil
			})
	}
	static func serviceIdentifier() throws -> String {
		let plist = Bundle.main.bundleURL.appendingPathComponent(
			"Contents/XPCServices/AgentXPCService.xpc/Contents/Info.plist")
		guard
			let info = try PropertyListSerialization.propertyList(
				from: Data(contentsOf: plist), format: nil) as? [String: Any],
			let id = info["CFBundleIdentifier"] as? String,
			id.hasPrefix("com.macapper.scenario.")
		else {
			throw ScenarioFailure.message("Chat scenarios must run inside an isolated signed test host")
		}
		return id
	}
	static func eventContains(_ event: AgentServiceEvent, text: String) -> Bool {
		switch event {
		case .textDelta(let value), .notification(let value), .extensionError(let value):
			return value.contains(text)
		case .toolStarted(_, _, let value), .toolUpdated(_, _, let value),
			.toolFinished(_, _, let value, _):
			return value.contains(text)
		default: return false
		}
	}
}
