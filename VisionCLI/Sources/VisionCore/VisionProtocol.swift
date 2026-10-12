// @frontmatter:start
// Defines bounded verification requests, per-criterion verdicts, result records, and safe operational errors for the CLI.
// @frontmatter:end
import Foundation

public struct VisionFailure: Error, Sendable {
	public enum Code: String, Codable, Sendable {
		case invalid_request, invalid_image, missing_api_key, invalid_credentials
		case network_error, timeout, http_error, invalid_response, provider_incomplete
	}
	public let code: Code
	public let message: String
	public init(_ code: Code, _ message: String) { self.code = code; self.message = message }
}

public struct Criterion: Codable, Sendable {
	public let id: String
	public let description: String
	public init(id: String, description: String) { self.id = id; self.description = description }
}

public struct VisionRequest: Codable, Sendable {
	public let version: Int
	public let requestID: UUID
	public let imagePath: String
	public let criteria: [Criterion]
	public let context: String?
	public let model: String?
	public var selectedModel: String { model ?? "gemini-3.8-flash" }

	public init(
		requestID: UUID, imagePath: String, criteria: [Criterion], context: String? = nil,
		model: String? = nil
	) {
		version = 1; self.requestID = requestID; self.imagePath = imagePath
		self.criteria = criteria; self.context = context; self.model = model
	}

	public static func decode(_ data: Data) throws -> Self {
		guard
			data.count <= 65_536,
			let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
			Set(object.keys).isSubset(of: [
				"version", "requestID", "imagePath", "criteria", "context", "model",
			]),
			let criteria = object["criteria"] as? [[String: Any]],
			criteria.allSatisfy({ Set($0.keys) == ["id", "description"] }),
			let request = try? JSONDecoder().decode(Self.self, from: data)
		else {
			throw VisionFailure(
				.invalid_request, "Expected a bounded version-1 request with known fields and criteria.")
		}
		try request.validate()
		return request
	}

	public func validate() throws {
		guard
			version == 1,
			imagePath.hasPrefix("/"),
			imagePath.utf8.count <= 4096,
			(1...20).contains(criteria.count),
			Set(criteria.map(\.id)).count == criteria.count,
			selectedModel.utf8.count <= 128,
			selectedModel.range(of: #"^gemini-[a-z0-9.-]+$"#, options: .regularExpression) != nil,
			context == nil || boundedText(context ?? "", limit: 4096),
			criteria.allSatisfy({
				$0.id.utf8.count <= 64
					&& $0.id.range(of: #"^[a-z0-9][a-z0-9_-]*$"#, options: .regularExpression) != nil
					&& boundedText($0.description, limit: 2048)
			})
		else {
			throw VisionFailure(
				.invalid_request,
				"Use an absolute image path, 1–20 unique bounded criteria, and a Gemini model ID.")
		}
	}
}

func boundedText(_ text: String, limit: Int) -> Bool {
	!text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && text.utf8.count <= limit
		&& !text.unicodeScalars.contains {
			$0.value != 10 && CharacterSet.controlCharacters.contains($0)
		}
}

public enum Verdict: String, Codable, Sendable {
	case pass, fail, uncertain
	public var exitCode: Int32 { self == .pass ? 0 : self == .fail ? 1 : 2 }
}

public struct Check: Codable, Sendable {
	public let id: String
	public let verdict: Verdict
	public let evidence: String
}

public struct ImageMetadata: Codable, Sendable {
	public let width: Int
	public let height: Int
	public let sha256: String
}

public struct VerificationResult: Codable, Sendable {
	public let version: Int
	public let requestID: UUID
	public let status: String
	public let model: String
	public let providerModel: String
	public let verdict: Verdict
	public let summary: String
	public let checks: [Check]
	public let image: ImageMetadata
}
