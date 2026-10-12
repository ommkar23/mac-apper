// @frontmatter:start
// Parses and validates bounded UI verification fixture arguments and JSON data.
// @frontmatter:end
import Foundation

public struct UIVerificationFixture: Decodable, Sendable {
	public let idea: String
	public let showPreview: Bool
	public let selectedFile: String
	enum CodingKeys: String, CodingKey {
		case idea
		case showPreview = "show_preview"
		case selectedFile = "selected_file"
	}
	public static func filename(arguments: [String]) throws -> String {
		if arguments.isEmpty { return "ui-live.json" }
		guard
			arguments.count == 2,
			arguments[0] == "--fixture",
			arguments[1].hasSuffix(".json")
		else { throw SessionError.invalidRequest }
		return arguments[1]
	}
	public static func decode(_ data: Data) throws -> Self {
		guard
			data.count <= 32_768,
			let object = try JSONSerialization.jsonObject(with: data) as? [String: Any],
			Set(object.keys) == ["idea", "show_preview", "selected_file"]
		else { throw SessionError.invalidRequest }
		let fixture = try JSONDecoder().decode(Self.self, from: data)
		guard
			!fixture.idea.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
			fixture.idea.utf8.count <= 16_384,
			!fixture.selectedFile.isEmpty,
			fixture.selectedFile.utf8.count <= 1_024,
			!fixture.selectedFile.contains("\0"),
			!fixture.selectedFile.contains("\\"),
			fixture.selectedFile.split(separator: "/", omittingEmptySubsequences: false).allSatisfy({
				!$0.isEmpty && !$0.hasPrefix(".")
			})
		else { throw SessionError.invalidRequest }
		return fixture
	}
}
