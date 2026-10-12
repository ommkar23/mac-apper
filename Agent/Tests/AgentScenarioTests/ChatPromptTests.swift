// @frontmatter:start
// Checks the Chat capabilities prompt requires ordered MCP search/fetch and a fetched-page summary without live calls.
// @frontmatter:end
import Foundation
import Testing

@Test @MainActor func chatCapabilitiesPromptRequiresFetchedContentOffline() throws {
	let prompt = ChatModelCases.capabilitiesPrompt
	let search = try #require(prompt.range(of: "Parallel MCP web_search through codemode"))
	let fetch = try #require(prompt.range(of: "Parallel MCP web_fetch through codemode"))
	#expect(search.lowerBound < fetch.lowerBound)
	#expect(prompt.contains("selected search-result URL"))
	#expect(prompt.contains("Read the fetched page"))
	#expect(prompt.contains("derive the summary from its fetched content"))
	#expect(prompt.contains("not just search snippets or memory"))
	#expect(prompt.contains("Return ONLY JSON with exactly sourceURL and summary fields"))
	#expect(prompt.contains("Never create an app or write files"))
}
