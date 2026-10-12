// @frontmatter:start
// Validates the bounded manifest that selects a generated project's SwiftPM app targets.
// @frontmatter:end
import Foundation

public enum ProjectValidationError: Error, Sendable {
	case oversized, unsupportedVersion, invalidManifest, invalidPath, invalidIdentifier, malformed
}

public struct ProjectManifest: Codable, Sendable {
	public let schemaVersion: Int
	public let appID: String
	public let executableTarget: String
	public let previewTarget: String
	public let devServiceID: String

	public static func decode(_ data: Data) throws -> Self {
		guard
			data.count <= 16_384
		else { throw ProjectValidationError.oversized }
		guard
			let object = try JSONSerialization.jsonObject(with: data) as? [String: Any],
			Set(object.keys) == [
				"schemaVersion", "appID", "executableTarget", "previewTarget", "devServiceID",
			]
		else { throw ProjectValidationError.malformed }
		let value = try JSONDecoder().decode(Self.self, from: data)
		guard
			value.schemaVersion == 1
		else { throw ProjectValidationError.unsupportedVersion }
		guard
			value.appID.utf8.count == 36,
			UUID(uuidString: value.appID) != nil,
			value.devServiceID == "com.macapper.generated." + value.appID.lowercased(),
			validTarget(value.executableTarget),
			validTarget(value.previewTarget),
			value.executableTarget != value.previewTarget
		else { throw ProjectValidationError.invalidManifest }
		return value
	}

	private static func validTarget(_ target: String) -> Bool {
		target.range(of: "^[A-Za-z][A-Za-z0-9_]{0,63}$", options: .regularExpression) != nil
	}
}
