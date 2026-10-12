// @frontmatter:start
// Tests preview record decoding against unknown fields and invalid dimensions.
// @frontmatter:end
import Foundation
import Testing

@testable import AgentApplication

@Test func protocolRecordRejectsUnknownFieldsAndBounds() throws {
	let record = PreviewRecord(
		kind: "model_ready", runID: UUID().uuidString, buildID: String(repeating: "a", count: 64),
		appearance: "dark", width: 640, height: 480)
	let bytes = try JSONEncoder().encode(record)
	#expect(try PreviewRecord.decode(bytes).kind == "model_ready")
	var object = try #require(
		try JSONSerialization.jsonObject(with: bytes) as? [String: Any])
	object["command"] = "bad"
	#expect(throws: (any Error).self) {
		try PreviewRecord.decode(JSONSerialization.data(withJSONObject: object))
	}
	object.removeValue(forKey: "command")
	object["width"] = Int.max
	#expect(throws: (any Error).self) {
		try PreviewRecord.decode(JSONSerialization.data(withJSONObject: object))
	}
}
