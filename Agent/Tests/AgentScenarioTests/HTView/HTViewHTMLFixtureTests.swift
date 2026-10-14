// @frontmatter:start
// Checks the fixed HTView HTML fixture and rejects missing style/script markers and external dependencies offline.
// @frontmatter:end
import Foundation
import Testing

// This checks authored test data, not arbitrary HTML or JavaScript semantics.
// Actual computed style and script execution require the independent WebKit helper.
private func htViewFixtureContractHolds(_ html: String) -> Bool {
	guard
		!html.isEmpty,
		html.utf8.count <= 16 * 1024
	else { return false }

	let required = [
		"<!doctype html>", "<html lang=\"en\">", "<meta charset=\"utf-8\">",
		"<title>\(HTViewHTMLFixture.title)</title>", "<style>", "</style>",
		"body { font-family: system-ui, sans-serif; margin: 24px; }",
		"<p id=\"inline-style\" style=\"color: \(HTViewHTMLFixture.expectedColor);\">Inline CSS is visible.</p>",
		"<p id=\"script-status\">script-pending</p>",
		"<button id=\"script-button\" type=\"button\">Update script status</button>",
		"<script>", "</script>", "document.addEventListener('DOMContentLoaded', () => {",
		"const status = document.getElementById('script-status');",
		"status.textContent = '\(HTViewHTMLFixture.scriptMarker)';",
		"document.getElementById('script-button').addEventListener('click', () => {",
		"status.textContent = '\(HTViewHTMLFixture.scriptMarker)-clicked';",
		"</body>", "</html>",
	]
	guard
		required.allSatisfy({ html.contains($0) }),
		["inline-style", "script-status", "script-button"].allSatisfy({
			html.components(separatedBy: "id=\"\($0)\"").count == 2
		}),
		html.components(separatedBy: "<title>").count == 2,
		html.components(separatedBy: "<style>").count == 2,
		html.components(separatedBy: "<script>").count == 2
	else { return false }

	return htViewHasNoExternalDependencies(html)
}

private func htViewHasNoExternalDependencies(_ html: String) -> Bool {
	guard
		html.utf8.count <= 16 * 1024
	else { return false }

	// Reject local dependencies too: the fixture must work with no base URL or server.
	let forbidden = [
		#"(?i)\b(?:src|srcset|href|action|poster|data)\s*="#,
		#"(?i)<\s*(?:link|iframe|object|embed|base)\b"#,
		#"(?i)\bhttps?\s*:|\bfile\s*:|\b(?:ws|wss)\s*:|//"#,
		#"(?i)@import\b|\burl\s*\("#,
		#"(?i)\b(?:fetch|XMLHttpRequest|WebSocket|EventSource|import)\s*\("#,
		#"(?i)http-equiv\s*="#,
	]
	return forbidden.allSatisfy { html.range(of: $0, options: .regularExpression) == nil }
}

@Test func htViewHTMLFixtureContractOffline() {
	#expect(HTViewHTMLFixture.title == "HTView Offline HTML Fixture")
	#expect(HTViewHTMLFixture.scriptMarker == "htview-script-loaded")
	#expect(HTViewHTMLFixture.expectedColor == "rgb(17, 34, 51)")
	#expect(htViewFixtureContractHolds(HTViewHTMLFixture.html))
}

@Test(arguments: [
	"<style>", "body { font-family: system-ui, sans-serif; margin: 24px; }",
	"id=\"inline-style\"", "color: rgb(17, 34, 51);", "<script>",
	"id=\"script-status\"", "id=\"script-button\"", "DOMContentLoaded",
	"status.textContent = 'htview-script-loaded';", "addEventListener('click'",
	"status.textContent = 'htview-script-loaded-clicked';",
])
func htViewHTMLFixtureRejectsMissingMarkersOffline(_ marker: String) {
	#expect(HTViewHTMLFixture.html.contains(marker))
	let mutated = HTViewHTMLFixture.html.replacingOccurrences(of: marker, with: "")
	#expect(!htViewFixtureContractHolds(mutated))
}

@Test(arguments: [
	"<script src=\"https://example.invalid/script.js\"></script>",
	"<img SRC = 'https://example.invalid/image.png'>",
	"<img srcset=\"//example.invalid/image.png 2x\">",
	"<link rel=\"stylesheet\" href=\"styles.css\">",
	"<iframe src=\"http://localhost:8080\"></iframe>",
	"<style>@import 'styles.css';</style>",
	"<style>body { background: url(image.png); }</style>",
	"<script>fetch('relative.json');</script>",
	"<script>new XMLHttpRequest();</script>",
	"<script>new WebSocket('wss://example.invalid');</script>",
	"<script>new EventSource('events');</script>",
	"<script>import('./module.js');</script>",
	"<meta http-equiv=\"refresh\" content=\"0;url=index.html\">",
])
func htViewHTMLFixtureRejectsExternalResourcesOffline(_ resource: String) {
	let mutated = HTViewHTMLFixture.html.replacingOccurrences(
		of: "</head>", with: "\(resource)\n</head>")
	#expect(!htViewHasNoExternalDependencies(mutated))
	#expect(!htViewFixtureContractHolds(mutated))
}

@Test func htViewHTMLFixtureRejectsDuplicateIDsAndOversizeOffline() {
	for id in ["inline-style", "script-status", "script-button"] {
		let mutated = HTViewHTMLFixture.html.replacingOccurrences(
			of: "</body>", with: "<p id=\"\(id)\">Duplicate</p></body>")
		#expect(!htViewFixtureContractHolds(mutated))
	}
	#expect(!htViewFixtureContractHolds(""))
	let oversized = HTViewHTMLFixture.html + String(repeating: " ", count: 16 * 1024)
	#expect(!htViewFixtureContractHolds(oversized))
}
