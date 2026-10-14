// @frontmatter:start
// Tests bounded review requests, conservative verdict aggregation, provider JSON validation, and private credential loading without live API calls.
// @frontmatter:end
import Foundation
import Scenario
import ImageIO
import Testing
@testable import VisionCore

private let identity = UUID()
private let criteria = [
	Criterion(id: "count", description: "A large count is visible."),
	Criterion(id: "controls", description: "All three controls are visible."),
]

@Test func requestRejectsUnknownFieldsDuplicateCriteriaAndInvalidModels() throws {
	let valid: [String: Any] = [
		"version": 1, "requestID": identity.uuidString, "imagePath": "/tmp/image.png",
		"criteria": [["id": "count", "description": "Count visible"]],
	]
	let decoded = try VisionRequest.decode(JSONSerialization.data(withJSONObject: valid))
	#expect(decoded.selectedModel == "gemini-3.8-flash")
	for changes: [String: Any] in [
		["version": 2], ["apiKey": "must not be accepted"], ["model": "../bad"],
		["model": "gemini-3.8-flash\n"], ["criteria": []],
		["criteria": [["id": "count", "description": "One"], ["id": "count", "description": "Two"]]],
		["criteria": [["id": "count", "description": "One", "extra": true]]],
	] {
		var bad = valid
		for (key, value) in changes { bad[key] = value }
		#expect(throws: (any Error).self) {
			try VisionRequest.decode(JSONSerialization.data(withJSONObject: bad))
		}
	}
}

private func reply(_ verdicts: [String], status: String = "completed") throws -> HTTPReply {
	let review: [String: Any] = [
		"summary": "Review complete.",
		"checks": zip(criteria, verdicts).map {
			["id": $0.0.id, "verdict": $0.1, "evidence": "Visible evidence for \($0.0.id)."]
		},
	]
	let text = String(decoding: try JSONSerialization.data(withJSONObject: review), as: UTF8.self)
	return HTTPReply(
		status: 200,
		data: try JSONSerialization.data(withJSONObject: [
			"status": status, "model": "gemini-3.8-flash",
			"steps": [["type": "model_output", "content": [["type": "text", "text": text]]]],
		]))
}

private actor Stub: HTTPTransport {
	let reply: HTTPReply
	var captured: URLRequest?
	init(_ reply: HTTPReply) { self.reply = reply }
	func send(_ request: URLRequest) async throws -> HTTPReply { captured = request; return reply }
}

@Test func clientBuildsStatelessImageRequestAndAggregatesWithoutTrustingAnOverallModelVerdict()
	async throws
{
	let request = VisionRequest(requestID: identity, imagePath: "/tmp/image.png", criteria: criteria)
	let image = LoadedImage(
		data: Data([1, 2, 3]), mimeType: "image/png", width: 1, height: 1, sha256: "fixture")
	for (statuses, expected) in [
		(["pass", "pass"], Verdict.pass), (["pass", "uncertain"], .uncertain),
		(["uncertain", "fail"], .fail),
	] {
		let stub = Stub(try reply(statuses))
		let result = try await GeminiClient(apiKey: "test-key", transport: stub).verify(
			request, image: image)
		#expect(result.verdict == expected)
		#expect(result.requestID == identity)
		let captured = try #require(await stub.captured)
		#expect(
			captured.url?.absoluteString
				== "https://generativelanguage.googleapis.com/v1beta/interactions")
		#expect(captured.value(forHTTPHeaderField: "x-goog-api-key") == "test-key")
		let bodyData = try #require(captured.httpBody)
		let body = try #require(JSONSerialization.jsonObject(with: bodyData) as? [String: Any])
		#expect(body["store"] as? Bool == false)
		#expect(body["stream"] as? Bool == false)
		#expect(body["tools"] == nil)
		let parts = try #require(body["input"] as? [[String: Any]])
		#expect(parts.last?["data"] as? String == image.data.base64EncodedString())
		#expect(body["response_format"] != nil)
	}
}

@Test func clientRejectsIncompleteUnknownOrMissingCriterionResults() async throws {
	let request = VisionRequest(requestID: identity, imagePath: "/tmp/image.png", criteria: criteria)
	let image = LoadedImage(
		data: Data([1]), mimeType: "image/png", width: 1, height: 1, sha256: "fixture")
	var malformed = try #require(
		JSONSerialization.jsonObject(with: try reply(["pass", "pass"]).data) as? [String: Any])
	malformed["errors"] = ["message": "malformed provider error"]
	let malformedError = HTTPReply(
		status: 200, data: try JSONSerialization.data(withJSONObject: malformed))
	for response in [
		try reply(["pass", "pass"], status: "incomplete"), try reply(["pass"]),
		try reply(["pass", "maybe"]), HTTPReply(status: 429, data: Data("secret provider body".utf8)),
		malformedError,
	] {
		await #expect(throws: (any Error).self) {
			try await GeminiClient(apiKey: "test-key", transport: Stub(response)).verify(
				request, image: image)
		}
	}
}

@Test func credentialsPreferEnvironmentAndRejectWorldReadableFiles() throws {
	let root = try ProjectTemporaryDirectory.root().appendingPathComponent(UUID().uuidString)
	try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
	defer { try? FileManager.default.removeItem(at: root) }
	let file = root.appendingPathComponent(".env")
	try Data("GEMINI_API_KEY=file-key\n".utf8).write(to: file)
	try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: file.path)
	#expect(
		try Credentials.load(environment: ["GEMINI_API_KEY": "env-key"], file: file).value == "env-key")
	#expect(try Credentials.load(environment: [:], file: file).value == "file-key")
	#expect(throws: (any Error).self) {
		try Credentials.load(environment: ["GEMINI_API_KEY": "env-key\n"], file: nil)
	}
	try FileManager.default.setAttributes([.posixPermissions: 0o644], ofItemAtPath: file.path)
	#expect(throws: (any Error).self) { try Credentials.load(environment: [:], file: file) }
}
