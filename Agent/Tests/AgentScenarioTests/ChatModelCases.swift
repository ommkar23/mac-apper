// @frontmatter:start
// Supplies shared Chat selectors, prompts, response checks and production service discovery.
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

	static let capabilitiesPrompt = """
		Use Parallel MCP web_search through codemode to find the official Example Domain website.
		Then use Parallel MCP web_fetch through codemode on the selected search-result URL.
		Read the fetched page and derive the summary from its fetched content, not just search snippets or memory.
		Return ONLY JSON with exactly sourceURL and summary fields, no Markdown, commentary, or introduction.
		Never create an app or write files.
		"""

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
