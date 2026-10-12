// @frontmatter:start
// Validates rendered PNG artifacts and represents text, render, or failure tool results.
// @frontmatter:end
import Foundation

public struct RenderArtifact: Sendable {
	public let url: URL
	public let png: Data
	public let record: PreviewRecord
	public init(url: URL, png: Data, record: PreviewRecord) throws {
		guard
			record.kind == "render_completed",
			record.path == "render.png",
			UUID(uuidString: record.runID) != nil,
			!record.buildID.isEmpty,
			let width = record.width,
			let height = record.height,
			(1...6144).contains(width),
			(1...6144).contains(height),
			width * height <= 8_000_000,
			png.count <= 2_097_152,
			png.count > 8,
			png.starts(with: [137, 80, 78, 71, 13, 10, 26, 10])
		else { throw PreviewError.invalidResult }
		self.url = url
		self.png = png
		self.record = record
	}
}
public enum ToolExecutionResult: Sendable, ExpressibleByStringLiteral {
	case success(String)
	case rendered(RenderArtifact)
	case failure(String)
	public init(stringLiteral value: String) { self = .success(value) }
	public var artifact: RenderArtifact? {
		if case .rendered(let artifact) = self { artifact } else { nil }
	}
	public var text: String {
		switch self {
		case .success(let text): return text
		case .failure(let text): return "Tool failed: " + text
		case .rendered(let artifact):
			return String(decoding: (try? JSONEncoder().encode(artifact.record)) ?? Data(), as: UTF8.self)
		}
	}
}
