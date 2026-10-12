// @frontmatter:start
// Sanitizes app names and encodes or decodes rename commands and notifications.
// @frontmatter:end
import Foundation

public enum AppNameError: Error, Equatable, Sendable, LocalizedError {
	case invalid

	public var errorDescription: String? {
		"Enter a name between 1 and 64 characters. File-path characters and a trailing .app are cleaned automatically."
	}
}

public enum AppName {
	public static func sanitize(_ input: String) throws -> String {
		let withoutControls = input.unicodeScalars.map { scalar -> Character in
			if CharacterSet.controlCharacters.contains(scalar) { return " " }
			if scalar == "/" || scalar == ":" || scalar == "\\" { return " " }
			return Character(scalar)
		}
		var name = String(withoutControls)
			.split(whereSeparator: { $0.isWhitespace })
			.joined(separator: " ")
		while name.lowercased().hasSuffix(".app") {
			name.removeLast(4)
			name = name.trimmingCharacters(in: .whitespacesAndNewlines)
		}
		guard
			!name.isEmpty,
			name != ".",
			name != "..",
			!name.hasPrefix("."),
			name.count <= 64
		else { throw AppNameError.invalid }
		return name
	}

	public static func renameCommand(for input: String) throws -> String {
		let name = try sanitize(input)
		return "/mac-apper-rename " + Data(name.utf8).base64EncodedString()
	}

	public static func decodeNotification(_ message: String) -> String? {
		let marker = "MAC_APPER_RENAMED:"
		guard
			message.hasPrefix(marker),
			let data = Data(base64Encoded: String(message.dropFirst(marker.count))),
			let raw = String(data: data, encoding: .utf8)
		else { return nil }
		return try? sanitize(raw)
	}
}
