// @frontmatter:start
// Tests factory-created build/plan routing and explicit preview failures for missing factories or invalid scope.
// @frontmatter:end
import Foundation
import Scenario
import Testing

@testable import DevToolsApplication

@Test func typedBuildAndPlanResolveProjectWithoutRegistration() async throws {
	let root = try ProjectTemporaryDirectory.root().appendingPathComponent(UUID().uuidString)
	try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
	defer { try? FileManager.default.removeItem(at: root) }
	let projectID = UUID().uuidString.lowercased()
	let project = root.appendingPathComponent(projectID)
	try FileManager.default.createDirectory(at: project, withIntermediateDirectories: true)
	try "// swift-tools-version: 6.0\n".write(
		to: project.appendingPathComponent("Package.swift"), atomically: true, encoding: .utf8)
	try Data(
		"{\"schemaVersion\":1,\"appID\":\"\(projectID)\",\"executableTarget\":\"ProductionApp\",\"previewTarget\":\"PreviewApp\",\"devServiceID\":\"com.macapper.generated.\(projectID)\"}"
			.utf8
	).write(to: project.appendingPathComponent("app-manifest.json"))
	let capture = root.appendingPathComponent("arguments.txt")
	let tool = root.appendingPathComponent("fixture-xcrun")
	try "#!/bin/sh\nprintf '%s\\n' \"$@\" > \"$DEVTOOLS_CAPTURE\"\n".write(
		to: tool, atomically: true, encoding: .utf8)
	try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: tool.path)
	let factory = ControllerFactory(
		projectsRoot: root, xcrunURL: tool,
		environment: ["DEVTOOLS_CAPTURE": capture.path])
	let identity = UUID(uuidString: projectID)!
	let built = try await factory.controllers().build.handle(
		identity, UUID(), BuildRequest(projectRoot: project.path))
	#expect(built.target == "ProductionApp")
	#expect(try String(contentsOf: capture, encoding: .utf8).contains("--product"))
	let requestID = UUID()
	let request = try JSONSerialization.data(withJSONObject: [
		"version": 1, "requestID": requestID.uuidString, "projectID": projectID,
		"sessionID": UUID().uuidString, "command": "build",
		"payload": try JSONEncoder().encode(BuildRequest(projectRoot: project.path))
			.base64EncodedString(),
	])
	let router = OpenXPCGeneratedService(controllers: factory.controllers())
	let reply = await withCheckedContinuation { continuation in
		router.execute(request) { continuation.resume(returning: $0) }
	}
	let envelope = try #require(JSONSerialization.jsonObject(with: reply) as? [String: Any])
	#expect(envelope["requestID"] as? String == requestID.uuidString)
	#expect(envelope["success"] as? Bool == true)
	let encoded = try #require(envelope["payload"] as? String)
	let payload = try #require(Data(base64Encoded: encoded))
	#expect(try JSONDecoder().decode(BuildResult.self, from: payload).target == "ProductionApp")
	let planned = try await factory.controllers().plan.handle(
		identity, UUID(),
		PlanRequest(projectRoot: project.path, action: "add_plan", tasks: nil, ids: nil))
	#expect(planned.tasks.isEmpty)
	await #expect(throws: (any Error).self) {
		_ = try await factory.controllers().plan.handle(
			identity, UUID(),
			PlanRequest(projectRoot: root.path, action: "get_tasks", tasks: nil, ids: nil))
	}
}

@Test func typedDevToolsPreviewRejectsMissingPreviewCodeAndInvalidScope() async throws {
	let root = try ProjectTemporaryDirectory.root().appendingPathComponent(UUID().uuidString)
	try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
	defer { try? FileManager.default.removeItem(at: root) }
	let projectID = UUID().uuidString.lowercased()
	let project = root.appendingPathComponent(projectID)
	try FileManager.default.createDirectory(
		at: project.appendingPathComponent("Sources/AppViews"), withIntermediateDirectories: true)
	try "// swift-tools-version: 6.0\n".write(
		to: project.appendingPathComponent("Package.swift"), atomically: true, encoding: .utf8)
	try Data(
		"{\"schemaVersion\":1,\"appID\":\"\(projectID)\",\"executableTarget\":\"ProductionApp\",\"previewTarget\":\"PreviewApp\",\"devServiceID\":\"com.macapper.generated.\(projectID)\"}"
			.utf8
	).write(to: project.appendingPathComponent("app-manifest.json"))
	try "import SwiftUI\n".write(
		to: project.appendingPathComponent("Sources/AppViews/Example.swift"),
		atomically: true, encoding: .utf8)
	try """
	// swift-tools-version: 6.0
	import PackageDescription
	let package = Package(name: "MissingPreview", platforms: [.macOS(.v14)], targets: [.target(name: "AppViews")])
	""".write(to: project.appendingPathComponent("Package.swift"), atomically: true, encoding: .utf8)
	let factory = ControllerFactory(projectsRoot: root)
	let request = try PreviewRequest(
		projectRoot: project.path, viewPath: "Sources/AppViews/Example.swift", screenSize: nil)
	let response = try await factory.controllers().preview.handle(
		UUID(uuidString: projectID)!, UUID(), request)
	#expect(response.status == "error")
	#expect(response.summary.contains("missing_preview"))
	#expect(response.artifact == nil)
	await #expect(throws: (any Error).self) {
		_ = try await factory.controllers().preview.handle(
			UUID(uuidString: projectID)!, UUID(),
			PreviewRequest(
				projectRoot: root.path, viewPath: "Sources/AppViews/Example.swift", screenSize: nil))
	}
}
