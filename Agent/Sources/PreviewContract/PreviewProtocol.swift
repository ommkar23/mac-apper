// @frontmatter:start
// Validates bounded preview records and enforces preview lifecycle transitions.
// @frontmatter:end
import Foundation

public enum PreviewError: Error { case invalidConfiguration, invalidTransition, invalidResult }
public struct PreviewRecord: Codable, Sendable {
	public let kind: String
	public let runID: String
	public let buildID: String
	public var path: String?
	public var appearance: String?
	public var width: Int?
	public var height: Int?
	public var message: String?
	public static func decode(_ bytes: Data) throws -> Self {
		guard
			bytes.count <= 8192,
			let object = try JSONSerialization.jsonObject(with: bytes) as? [String: Any],
			Set(object.keys).isSubset(of: [
				"kind", "runID", "buildID", "path", "appearance", "width", "height", "message",
			]),
			["kind", "runID", "buildID"].allSatisfy({ object[$0] != nil })
		else { throw PreviewError.invalidResult }
		let record = try JSONDecoder().decode(Self.self, from: bytes)
		guard
			UUID(uuidString: record.runID) != nil,
			record.buildID.utf8.count == 64,
			record.buildID.utf8.allSatisfy({ (48...57).contains($0) || (97...102).contains($0) }),
			["model_ready", "render_completed", "render_failed"].contains(record.kind)
		else { throw PreviewError.invalidResult }
		if record.kind == "render_failed" {
			guard
				let message = record.message,
				message.utf8.count <= 2000
			else { throw PreviewError.invalidResult }
		} else {
			guard
				let width = record.width,
				let height = record.height,
				(1...6144).contains(width),
				(1...6144).contains(height),
				width * height <= 8_000_000,
				["light", "dark"].contains(record.appearance ?? ""),
				record.message == nil,
				record.path == (record.kind == "render_completed" ? "render.png" : nil)
			else { throw PreviewError.invalidResult }
		}
		return record
	}
	public init(
		kind: String, runID: String, buildID: String, path: String? = nil, appearance: String? = nil,
		width: Int? = nil, height: Int? = nil, message: String? = nil
	) {
		self.kind = kind
		self.runID = runID
		self.buildID = buildID
		self.path = path
		self.appearance = appearance
		self.width = width
		self.height = height
		self.message = message
	}
}
public struct PreviewLifecycle: Sendable {
	public enum Phase: String, Sendable { case preparing, ready, rendering, completed, failed }
	public private(set) var phase: Phase = .preparing
	public let runID: String
	public let buildID: String
	public init(runID: String, buildID: String) {
		self.runID = runID
		self.buildID = buildID
	}
	public mutating func beginRender() throws {
		guard
			phase == .ready
		else { throw PreviewError.invalidTransition }
		phase = .rendering
	}
	public mutating func accept(_ record: PreviewRecord) throws {
		guard
			record.runID == runID,
			record.buildID == buildID
		else { throw PreviewError.invalidResult }
		switch (phase, record.kind) {
		case (.preparing, "model_ready"): phase = .ready
		case (.rendering, "render_completed"): phase = .completed
		case (.preparing, "render_failed"), (.ready, "render_failed"), (.rendering, "render_failed"):
			phase = .failed
		default: throw PreviewError.invalidTransition
		}
	}
}
