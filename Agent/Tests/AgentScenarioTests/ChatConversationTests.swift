// @frontmatter:start
// Declares Chat greeting, bounded Japan news and same-story follow-up phases through the production client model.
// @frontmatter:end
import AgentScenarioSupport
import Foundation
import Scenario
import Testing

@MainActor private final class GreetingContext: ChatCaseContext {
	let marker = UUID().uuidString
	var session: ChatModelSession?
	var reply: [String: Any] = [:]
}

@MainActor private final class NewsContext: ChatCaseContext {
	var session: ChatModelSession?
}

@MainActor private final class FollowUpContext: ChatCaseContext {
	var session: ChatModelSession?
	var news: CountryNews?
	var third: CountryNews.Item?
	var reply: [String: Any] = [:]
}

extension ChatModelCases {
	static func greetingCase() -> ScenarioCase<ChatCollection> {
		makeCase(
			"chat-model-greeting", context: GreetingContext.init,
			setup: [
				step("submit owned greeting request") { c in
					let marker = c.marker
					c.session = try await c.sessions.create(
						"Do not use tools. Reply ONLY JSON with exactly {\"greeting\":\"Hello\",\"marker\":\"\(marker)\"}."
					)
				}
			],
			behaviour: [
				step("await bounded structured greeting") { c in
					let session = try #require(c.session)
					c.reply = try object(try await session.answer(), keys: ["greeting", "marker"])
				},
				step("verify greeting and opaque marker") { c in
					#expect(c.reply["greeting"] as? String == "Hello")
					#expect(c.reply["marker"] as? String == c.marker)
				},
				step("verify one greeting user request") { c in
					let session = try #require(c.session)
					#expect(try session.audit().userTexts.count == 1)
				},
			])
	}

	static func countryNewsCase() -> ScenarioCase<ChatCollection> {
		makeCase(
			"country-news-japan", context: NewsContext.init,
			setup: [
				step("submit owned Japan news request") { c in
					c.session = try await c.sessions.create(newsPrompt("Japan"))
				}
			],
			behaviour: [
				step("validate five bounded recent Japan stories") { c in
					let session = try #require(c.session)
					_ = try CountryNews.validate(
						Data(try await session.answer().utf8), country: "Japan", now: Date())
				},
				step("verify actual news search and fetch evidence") { c in
					let session = try #require(c.session)
					#expect(
						try session.successfulTools.isSuperset(of: [
							"codemode", "mcp__parallel__web_search", "mcp__parallel__web_fetch",
						]))
				},
			])
	}

	static func followUpCase() -> ScenarioCase<ChatCollection> {
		makeCase(
			"chat-follow-up", context: FollowUpContext.init,
			setup: [
				step("submit owned initial Japan news request") { c in
					c.session = try await c.sessions.create(newsPrompt("Japan"))
				}
			],
			behaviour: [
				step("validate initial five bounded stories") { c in
					let session = try #require(c.session)
					c.news = try CountryNews.validate(
						Data(try await session.answer().utf8), country: "Japan", now: Date())
				},
				step("verify initial search and fetch evidence") { c in
					let session = try #require(c.session)
					#expect(
						try session.successfulTools.isSuperset(of: [
							"codemode", "mcp__parallel__web_search", "mcp__parallel__web_fetch",
						]))
				},
				step("retain the validated third story") { c in
					let news = try #require(c.news)
					c.third = news.items[2]
				},
				step("submit unchanged third-story expansion request") { c in
					let session = try #require(c.session)
					try await session.submit(
						"""
						Expand item 3 from your previous five-item news list, using the same story. Return ONLY JSON with exactly
						{"title":"original title verbatim","sourceURL":"original source URL verbatim","summary":"expanded summary"}.
						Do not choose another story. Make the expanded summary 200-300 words, longer than the original summary.
						""")
				},
				step("await bounded structured expansion") { c in
					let session = try #require(c.session)
					c.reply = try object(try await session.answer(), keys: ["title", "sourceURL", "summary"])
				},
				step("verify unchanged third-story identity") { c in
					let third = try #require(c.third)
					#expect(c.reply["title"] as? String == third.title)
					#expect(c.reply["sourceURL"] as? String == third.sourceURL)
				},
				step("verify expanded summary growth and bound") { c in
					let third = try #require(c.third)
					let summary = try #require(c.reply["summary"] as? String)
					#expect(summary.utf8.count > third.summary.utf8.count + 100 && summary.utf8.count <= 6000)
				},
				step("verify two follow-up user requests") { c in
					let session = try #require(c.session)
					#expect(try session.audit().userTexts.count == 2)
				},
			])
	}
}
