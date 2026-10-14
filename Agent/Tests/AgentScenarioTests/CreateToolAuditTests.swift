// @frontmatter:start
// Exercises migrated direct/nested plan and Preview audits using offline ordered journals and real owned PNG/archive fixtures.
// @frontmatter:end
import AgentMacosClientModel
import CoreGraphics
import Foundation
import Scenario
import ImageIO
import Testing

@Test func createPlanToolAuditOffline() throws {
	let root = try ProjectTemporaryDirectory.appending("mac-apper-plan-evidence-\(UUID().uuidString)")
	try FileManager.default.createDirectory(at: root, withIntermediateDirectories: false)
	defer { try? FileManager.default.removeItem(at: root) }
	let pending: [String: Any] = [
		"id": "implement", "title": "Implement counter", "status": "pending",
	]
	let active: [String: Any] = [
		"id": "implement", "title": "Implement counter", "status": "in_progress",
	]
	let complete: [String: Any] = [
		"id": "implement", "title": "Implement counter", "status": "completed",
	]
	for nested in [false, true] {
		let fixture = try orderedEvidenceFixture(
			names: ["plan", "plan", "write", "plan"], nested: nested, path: "",
			arguments: [
				["action": "add_plan", "tasks": [pending]], ["action": "update_tasks", "tasks": [active]],
				["path": "Sources/AppModel/ApplicationModel.swift"],
				["action": "update_tasks", "tasks": [complete]],
			], results: [["tasks": [pending]], ["tasks": [active]], [:], ["tasks": [complete]]])
		let session = try storeAuditFixture(fixture, project: root)
		let task = try AgentTaskRecord(id: "implement", title: "Implement counter", status: "completed")
		try verifyCreatePlan(session: session, presentedTasks: [task])
		withKnownIssue("Intentional negative fixture: final plan must reach the client unchanged") {
			do { try verifyCreatePlan(session: session, presentedTasks: []) } catch {
				#expect(error is ExpectationFailedError)
			}
		}
		let late = try orderedEvidenceFixture(
			names: ["write", "plan", "plan", "plan"], nested: nested, path: "",
			arguments: [
				["path": "Sources/AppModel/ApplicationModel.swift"], ["action": "add_plan"],
				["action": "update_tasks"], ["action": "update_tasks"],
			], results: [[:], ["tasks": [pending]], ["tasks": [active]], ["tasks": [complete]]])
		let lateSession = try storeAuditFixture(late, project: root)
		withKnownIssue("Intentional negative fixture: implementation before in_progress cannot qualify")
		{
			do { try verifyCreatePlan(session: lateSession, presentedTasks: [task]) } catch {
				#expect(error is ExpectationFailedError)
			}
		}
	}
}

@Test func createPreviewToolAuditOffline() throws {
	let root = try ProjectTemporaryDirectory.appending(
		"mac-apper-preview-evidence-\(UUID().uuidString)")
	let project = root.appendingPathComponent(UUID().uuidString.lowercased())
	try FileManager.default.createDirectory(at: project, withIntermediateDirectories: true)
	defer { try? FileManager.default.removeItem(at: root) }
	try Data("{\"executableTarget\":\"ProductionApp\"}".utf8).write(
		to: project.appendingPathComponent("app-manifest.json"))
	let source = project.appendingPathComponent("Sources/AppViews/ApplicationRoot.swift")
	try FileManager.default.createDirectory(
		at: source.deletingLastPathComponent(), withIntermediateDirectories: true)
	try Data("// Offline scoped source fixture".utf8).write(to: source)
	let bytes = try auditPNG()
	let relative = ".mac-apper/Artifacts/\(UUID().uuidString.lowercased())/render.png"
	let artifact = project.appendingPathComponent(relative)
	try FileManager.default.createDirectory(
		at: artifact.deletingLastPathComponent(), withIntermediateDirectories: true)
	try bytes.write(to: artifact)
	for nested in [false, true] {
		let sessionID = UUID().uuidString.lowercased()
		let review = root.appendingPathComponent(
			"previews/\(project.lastPathComponent)/\(sessionID)/preview-123.png")
		try FileManager.default.createDirectory(
			at: review.deletingLastPathComponent(), withIntermediateDirectories: true)
		try bytes.write(to: review)
		let result: [String: Any] = [
			"status": "rendered", "width": 64, "height": 64,
			"artifact": ["kind": "png", "relativePath": relative, "reviewPath": review.path],
		]
		let fixture = try orderedEvidenceFixture(
			names: ["preview", "run", "preview", "build"], nested: nested, path: "",
			arguments: [
				["viewPath": "Sources/AppViews/ApplicationRoot.swift"], [:],
				[
					"viewPath": "Sources/AppViews/ApplicationRoot.swift",
					"screenSize": ["width": 64, "height": 64],
				], [:],
			],
			results: [
				["status": "error", "summary": "Recoverable render diagnostic"],
				[
					"target": "ProductionApp",
					"relativePath": ".mac-apper/DevBuild/\(UUID().uuidString.lowercased())/ProductionApp.app",
				], result,
				["target": "ProductionApp", "summary": "Built"],
			])
		let session = try storeAuditFixture(fixture, project: project, sessionID: sessionID)
		let verified = try verifyPreview(session: session, project: project)
		#expect(verified.width == 64 && verified.height == 64 && verified.reviewPath == review)
		// Direct and nested text-only Preview qualify without a read call or image forwarding.
		try Data([0]).write(to: review)
		withKnownIssue(
			"Intentional negative fixture: archive bytes must match the independently validated artifact PNG"
		) {
			do { _ = try verifyPreview(session: session, project: project) } catch {
				#expect(error is ExpectationFailedError)
			}
		}
	}
}

func storeAuditFixture(
	_ fixture: (session: Data, journal: Data), project: URL,
	sessionID: String = UUID().uuidString.lowercased()
) throws -> URL {
	let session = project.appendingPathComponent(".pi/sessions/\(sessionID).jsonl")
	let journal = project.appendingPathComponent(".pi/agent-events/\(sessionID).jsonl")
	for file in [session, journal] {
		try FileManager.default.createDirectory(
			at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
	}
	try fixture.session.write(to: session); try fixture.journal.write(to: journal)
	return session
}

func auditPNG(width: Int = 64, height: Int = 64) throws -> Data {
	let pixels = Data(repeating: 255, count: width * height * 4)
	let provider = try #require(CGDataProvider(data: pixels as CFData))
	let image = try #require(
		CGImage(
			width: width, height: height, bitsPerComponent: 8, bitsPerPixel: 32, bytesPerRow: width * 4,
			space: CGColorSpaceCreateDeviceRGB(),
			bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue),
			provider: provider, decode: nil, shouldInterpolate: false, intent: .defaultIntent))
	let data = NSMutableData()
	let destination = try #require(
		CGImageDestinationCreateWithData(data, "public.png" as CFString, 1, nil))
	CGImageDestinationAddImage(destination, image, nil)
	try #require(CGImageDestinationFinalize(destination))
	return data as Data
}
