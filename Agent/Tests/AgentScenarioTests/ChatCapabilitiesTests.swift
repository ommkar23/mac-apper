// @frontmatter:start
// Declares codemode-only Chat launch, fetched-page evidence and no-scaffold checks with a pre-submission project baseline.
// @frontmatter:end
import Foundation
import Scenario
import Testing

@MainActor private final class CapabilitiesContext: ChatCaseContext {
	let root = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".mac-apper")
	var before: Set<String>?
	var session: ChatModelSession?
}

extension ChatModelCases {
	static func capabilitiesCase() -> ScenarioCase<ChatCollection> {
		makeCase(
			"chat-capabilities", context: CapabilitiesContext.init,
			setup: [
				step("capture UUID-project baseline before submission") { c in
					c.before = try uuidProjects(c.root)
				},
				step("submit owned fetched-page capabilities request") { c in
					c.session = try await c.sessions.create(capabilitiesPrompt)
				},
			],
			behaviour: [
				step("verify captured codemode-only launch arguments") { c in
					let session = try #require(c.session)
					let args = try session.runningPi().arguments
					#expect(args.range(of: #"--tools codemode(?:\s|$)"#, options: .regularExpression) != nil)
					#expect(args.contains("AgentExtensions/parallel-codemode.ts"))
					#expect(!args.contains("Web.app"))
					for flag in ["--no-context-files", "--no-skills", "--no-prompt-templates"] {
						#expect(args.contains(flag))
					}
				},
				step("validate bounded fetched-page response") { c in
					let session = try #require(c.session)
					let json = try object(try await session.answer(), keys: ["sourceURL", "summary"])
					#expect(validURL(json["sourceURL"] as? String ?? ""))
					#expect(
						!(json["summary"] as? String ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
							.isEmpty)
				},
				step("verify actual capabilities search and fetch evidence") { c in
					let session = try #require(c.session)
					#expect(
						try session.successfulTools.isSuperset(of: [
							"codemode", "mcp__parallel__web_search", "mcp__parallel__web_fetch",
						]))
				},
				step("verify no UUID projects or app scaffold were created") { c in
					let before = try #require(c.before)
					let session = try #require(c.session)
					#expect(try uuidProjects(c.root) == before)
					for name in ["Package.swift", "app-manifest.json", "Sources"] {
						#expect(
							!FileManager.default.fileExists(
								atPath: try session.project.appendingPathComponent(name).path))
					}
				},
			])
	}
}
