// @frontmatter:start
// Tests app name sanitation, rejection of invalid names, and opaque rename commands.
// @frontmatter:end
import Foundation
import Testing

@testable import AgentApplication

@Test func appNameSanitizesUserInputForDisplayAndPackaging() throws {
	#expect(try AppName.sanitize("  Tiny   Calculator.app  ") == "Tiny Calculator")
	#expect(try AppName.sanitize("Paper/Reader: Focus\\Mode") == "Paper Reader Focus Mode")
	#expect(try AppName.sanitize("Dot\u{0000} Notes") == "Dot Notes")
}

@Test func appNameRejectsEmptyHiddenAndOverlongNames() {
	for value in ["", "   ", ".app", ".", "..", String(repeating: "a", count: 65)] {
		#expect(throws: AppNameError.self) { try AppName.sanitize(value) }
	}
}

@Test func appNameCreatesAnOpaqueRenameCommand() throws {
	let command = try AppName.renameCommand(for: "Paper & Notes")
	#expect(command.hasPrefix("/mac-apper-rename "))
	let encoded = String(command.dropFirst("/mac-apper-rename ".count))
	#expect(
		Data(base64Encoded: encoded).map { String(decoding: $0, as: UTF8.self) } == "Paper & Notes")
}
