// @frontmatter:start
// Runs a bounded VisionCLI review of the validated counter preview and checks image identity, model, exact criteria, and conservative visual verdicts.
// @frontmatter:end
import Darwin
import Foundation
import Scenario
import Testing

func counterVisionEnvFile() throws -> URL {
	let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
		.deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
	let path =
		ProcessInfo.processInfo.environment["AGENT_VISION_ENV_FILE"]
		?? root.appendingPathComponent("VisionCLI/.env").path
	try #require(path.hasPrefix("/"), "AGENT_VISION_ENV_FILE must be absolute")
	return URL(fileURLWithPath: path)
}

private struct CounterVisionResult: Decodable {
	struct Check: Decodable { let id: String; let verdict: String; let evidence: String }
	struct Image: Decodable { let width: Int; let height: Int; let sha256: String }
	let version: Int
	let requestID: UUID
	let status: String
	let model: String
	let providerModel: String
	let verdict: String
	let summary: String
	let checks: [Check]
	let image: Image
}

func verifyCounterVision(_ preview: VerifiedCounterPreview) async throws {
	try Task.checkCancellation()
	let environment = ProcessInfo.processInfo.environment
	let binaryPath = try #require(
		environment["AGENT_SCENARIO_VISION_CLI"], "Missing staged VisionCLI")
	let binary = URL(fileURLWithPath: binaryPath)
	let attributes = try binary.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey])
	try #require(attributes.isRegularFile == true && attributes.isSymbolicLink != true)
	try #require(FileManager.default.isExecutableFile(atPath: binary.path))
	let identity = UUID()
	let model = "gemini-3.8-flash"
	let criteria = [
		["id": "count_visible", "description": "A large readable integer count is visibly displayed."],
		[
			"id": "buttons_visible",
			"description": "Labels Increment, Decrement, and Reset are legible in the interface.",
		],
		[
			"id": "layout_usable",
			"description": "The count and controls are fully visible without clipping or overlap.",
		],
	]
	let request = try counterVisionRequest(
		preview, identity: identity, model: model, criteria: criteria)
	let manager = FileManager.default
	let scratch = URL(fileURLWithPath: "/private/tmp").appendingPathComponent(
		"agent-counter-vision-\(UUID().uuidString)")
	try manager.createDirectory(
		at: scratch, withIntermediateDirectories: false, attributes: [.posixPermissions: 0o700])
	defer { try? manager.removeItem(at: scratch) }
	let input = scratch.appendingPathComponent("request.json")
	let output = scratch.appendingPathComponent("response.json")
	let errors = scratch.appendingPathComponent("stderr")
	for (file, data) in [(input, request), (output, Data()), (errors, Data())] {
		try #require(
			manager.createFile(atPath: file.path, contents: data, attributes: [.posixPermissions: 0o600]))
	}
	let stdin = try FileHandle(forReadingFrom: input)
	let stdout = try FileHandle(forWritingTo: output)
	let stderr = try FileHandle(forWritingTo: errors)
	defer { try? stdin.close(); try? stdout.close(); try? stderr.close() }
	let process = Process()
	process.executableURL = binary
	process.arguments = ["verify", "--env-file", try counterVisionEnvFile().path]
	process.environment = environment
	process.standardInput = stdin; process.standardOutput = stdout; process.standardError = stderr
	let finished = DispatchSemaphore(value: 0)
	process.terminationHandler = { _ in finished.signal() }
	try Task.checkCancellation()
	try process.run()
	defer { stopVisionChild(process, finished: finished) }
	let deadline = ContinuousClock.now.advanced(by: .seconds(120))
	while process.isRunning {
		try Task.checkCancellation()
		try #require(ContinuousClock.now < deadline, "VisionCLI evaluation timed out")
		try #require(
			(try output.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? Int.max) <= 65_536,
			"Oversized VisionCLI output")
		try #require(
			(try errors.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? Int.max) <= 8192,
			"Oversized VisionCLI diagnostics")
		try await Task.sleep(for: .milliseconds(100))
	}
	process.waitUntilExit()
	try #require(
		(try errors.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? Int.max) <= 8192,
		"Oversized VisionCLI diagnostics")
	let reader = try FileHandle(forReadingFrom: output)
	defer { try? reader.close() }
	let data = try reader.read(upToCount: 65_537) ?? Data()
	try #require(data.count <= 65_536 && data.last == 10, "Invalid VisionCLI result framing")
	let object = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
	if object["status"] as? String == "error" {
		let error = object["error"] as? [String: Any]
		let code = error?["code"] as? String ?? "unknown"
		let message = error?["message"] as? String ?? "No sanitized diagnostic"
		throw ScenarioFailure.message(
			"VisionCLI operational error (not a visual failure): \(code.prefix(64)); exit \(process.terminationStatus); \(message.prefix(1024))"
		)
	}
	let result = try JSONDecoder().decode(CounterVisionResult.self, from: data)
	try #require(result.version == 1 && result.status == "completed" && result.requestID == identity)
	try #require(
		result.model == model && result.providerModel == model, "Unexpected visual reviewer model")
	try #require(
		result.image.width == preview.width && result.image.height == preview.height
			&& result.image.sha256 == preview.sha256, "Vision reviewed a different image")
	try #require(
		result.checks.map(\.id) == criteria.compactMap { $0["id"] }, "Mismatched visual criteria")
	try #require(
		result.summary.utf8.count <= 2048
			&& !result.summary.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
	for check in result.checks {
		try #require(["pass", "fail", "uncertain"].contains(check.verdict))
		try #require(
			check.evidence.utf8.count <= 2048
				&& !check.evidence.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
	}
	let verdict =
		result.checks.contains { $0.verdict == "fail" }
		? "fail" : result.checks.contains { $0.verdict == "uncertain" } ? "uncertain" : "pass"
	try #require(result.verdict == verdict)
	try #require(
		process.terminationReason == .exit
			&& process.terminationStatus == (verdict == "pass" ? 0 : verdict == "fail" ? 1 : 2))
	print("CREATE_VISION: \(String(decoding: data, as: UTF8.self).trimmingCharacters(in: .newlines))")
	try #require(
		verdict != "uncertain", "Visual review inconclusive; appearance could not be verified")
	try #require(verdict == "pass", "Counter screenshot failed visual criteria")
}

func counterVisionRequest(
	_ preview: VerifiedCounterPreview, identity: UUID, model: String, criteria: [[String: String]]
) throws -> Data {
	let request = try JSONSerialization.data(withJSONObject: [
		"version": 1, "requestID": identity.uuidString, "imagePath": preview.reviewPath.path,
		"model": model,
		"context":
			"Review only the visible appearance of this native macOS counter screenshot. Do not infer button behavior from the image.",
		"criteria": criteria,
	])
	try #require(request.count <= 65_536)
	return request
}

private func stopVisionChild(_ process: Process, finished: DispatchSemaphore) {
	guard
		process.isRunning
	else { return }
	process.terminate()
	if finished.wait(timeout: .now() + 2) == .timedOut && process.isRunning {
		_ = kill(process.processIdentifier, SIGKILL)
		_ = finished.wait(timeout: .now() + 5)
	}
}
