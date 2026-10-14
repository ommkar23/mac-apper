// @frontmatter:start
// Checks scaffold fixture and command temporary storage without packaged hosts or live calls.
// @frontmatter:end
import Foundation
import Scenario
import Testing

@Test @MainActor func scaffoldTemporaryFixtureRequiresScopedEnvironmentOffline() {
	#expect(!ScaffoldDevToolsFixture.tests.contains("NSTemporaryDirectory()"))
	#expect(
		ScaffoldDevToolsFixture.tests.contains(
			"#require(ProcessInfo.processInfo.environment[\"TMPDIR\"])"))
}

@Test func scaffoldCommandOverridesForeignTemporaryEnvironmentOffline() throws {
	let expected = try ProjectTemporaryDirectory.root().path + "/"
	let output = try scaffoldCommand(
		URL(fileURLWithPath: "/bin/sh"), ["-c", "printf '%s' \"$TMPDIR\""],
		environment: ["TMPDIR": "/must-not-be-used"], timeout: 5, logOutput: false)
	#expect(output == expected)
}
