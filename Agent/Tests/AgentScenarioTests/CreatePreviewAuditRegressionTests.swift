// @frontmatter:start
// Tests path-only Preview evidence against offline typed metadata, PNG, scoped path, and cleanup mutations.
// @frontmatter:end
import CryptoKit
import Foundation
import Scenario
import Testing

@Test func createPreviewDefaultCanvasTextOnlyOffline() throws {
	for nested in [false, true] {
		let fixture = try PreviewAuditFixture(width: 640, height: 480)
		defer { fixture.remove() }
		let session = try fixture.store(nested: nested, arguments: ["viewPath": fixture.viewPath])
		let result = try verifyPreview(session: session, project: fixture.project)
		#expect(result.width == 640 && result.height == 480)
		#expect(result.reviewPath == fixture.review)
		#expect(
			result.sha256 == SHA256.hash(data: fixture.bytes).map { String(format: "%02x", $0) }.joined())
	}
}

@Test(arguments: [
	"status", "missingArtifact", "kind", "fractionalDimension", "canvasMismatch", "invalidCanvas",
	"booleanCanvas", "defaultMismatch", "invalidPNG", "truncatedPNG", "pngDimensionMismatch",
	"oversizedPNG", "relativeTraversal", "artifactLink", "artifactDirectoryLink", "missingSource",
	"sourceLink", "sourceDirectoryLink", "sourceTraversal", "archiveProject", "archiveSession",
	"archiveTraversal", "archiveLink", "archiveDirectoryLink", "archiveAncestorLink", "archiveAlias",
	"clientLink", "clientTraversal", "archiveBytes", "missingArchive",
	"missingBuild", "wrongBuild", "missingRun", "wrongRun", "scratch", "scratchLink", "errorOnly",
])
func createPreviewRejectsInvalidPathEvidenceOffline(mutation: String) throws {
	for nested in [false, true] {
		let fixture = try PreviewAuditFixture(
			width: mutation == "invalidCanvas" ? 640 : 64,
			height: mutation == "invalidCanvas" ? 480 : 64)
		defer { fixture.remove() }
		var project = fixture.project
		var result = fixture.result
		var arguments: [String: Any] = [
			"viewPath": fixture.viewPath, "screenSize": ["width": 64, "height": 64],
		]
		var artifact = try #require(result["artifact"] as? [String: Any])
		var names = ["preview", "build", "run"]
		var build: [String: Any] = ["target": "ProductionApp", "summary": "Built"]
		var run = fixture.run
		switch mutation {
		case "status": result["status"] = "error"
		case "missingArtifact": result.removeValue(forKey: "artifact")
		case "kind": artifact["kind"] = "jpeg"
		case "fractionalDimension": result["width"] = 64.5
		case "canvasMismatch": arguments["screenSize"] = ["width": 65, "height": 64]
		case "invalidCanvas": arguments["screenSize"] = "invalid"
		case "booleanCanvas": arguments["screenSize"] = ["width": true, "height": 64]
		case "defaultMismatch": arguments.removeValue(forKey: "screenSize")
		case "invalidPNG": try fixture.replacePNG(Data([0, 1, 2]))
		case "truncatedPNG": try fixture.replacePNG(Data(fixture.bytes.dropLast(12)))
		case "pngDimensionMismatch": try fixture.replacePNG(auditPNG(width: 65))
		case "oversizedPNG": try fixture.replacePNG(Data(repeating: 0, count: 2_097_153))
		case "relativeTraversal": artifact["relativePath"] = ".mac-apper/Artifacts/../render.png"
		case "artifactLink": try fixture.link(fixture.artifact)
		case "artifactDirectoryLink": try fixture.link(fixture.artifact.deletingLastPathComponent())
		case "missingSource": try FileManager.default.removeItem(at: fixture.source)
		case "sourceLink": try fixture.link(fixture.source)
		case "sourceDirectoryLink": try fixture.link(fixture.source.deletingLastPathComponent())
		case "sourceTraversal": arguments["viewPath"] = "Sources/AppViews/../ApplicationRoot.swift"
		case "archiveProject":
			artifact["reviewPath"] = fixture.review.path.replacingOccurrences(
				of: fixture.project.lastPathComponent, with: UUID().uuidString.lowercased())
		case "archiveSession":
			artifact["reviewPath"] = fixture.review.path.replacingOccurrences(
				of: fixture.sessionID, with: UUID().uuidString.lowercased())
		case "archiveAlias":
			artifact["reviewPath"] = "/System/Volumes/Data" + fixture.review.path
		case "archiveAncestorLink":
			try fixture.link(fixture.root.appendingPathComponent("previews"))
		case "clientLink":
			project = fixture.root.appendingPathComponent("client-link")
			try FileManager.default.createSymbolicLink(at: project, withDestinationURL: fixture.project)
		case "clientTraversal":
			project = URL(
				fileURLWithPath: fixture.project.path + "/../" + fixture.project.lastPathComponent)
		case "archiveTraversal":
			artifact["reviewPath"] =
				fixture.review.deletingLastPathComponent().path + "/../\(fixture.sessionID)/preview-123.png"
		case "archiveLink": try fixture.link(fixture.review)
		case "archiveDirectoryLink": try fixture.link(fixture.review.deletingLastPathComponent())
		case "archiveBytes":
			try Data(repeating: 0, count: fixture.bytes.count).write(to: fixture.review)
		case "missingArchive": try FileManager.default.removeItem(at: fixture.review)
		case "missingBuild": names[1] = "read"
		case "wrongBuild": build["target"] = "AnotherApp"
		case "missingRun": names[2] = "read"
		case "wrongRun": run["target"] = "AnotherApp"
		case "scratch", "scratchLink":
			let scratch = fixture.project.appendingPathComponent(".mac-apper/PreviewBuild")
			try FileManager.default.createDirectory(at: scratch, withIntermediateDirectories: true)
			if mutation == "scratch" {
				try Data([0]).write(to: scratch.appendingPathComponent("leftover"))
			} else {
				try fixture.link(scratch)
			}
		case "errorOnly": result = ["status": "error", "summary": "Render failed"]
		default: Issue.record("Unknown mutation")
		}
		if mutation == "archiveProject" || mutation == "archiveSession" {
			let foreign = URL(fileURLWithPath: try #require(artifact["reviewPath"] as? String))
			try FileManager.default.createDirectory(
				at: foreign.deletingLastPathComponent(), withIntermediateDirectories: true)
			try fixture.bytes.write(to: foreign)
		}
		if mutation != "missingArtifact" && mutation != "errorOnly" { result["artifact"] = artifact }
		let session = try fixture.store(
			nested: nested, arguments: arguments, names: names, results: [result, build, run])
		var rejected = false
		withKnownIssue("Intentional invalid Preview fixture: \(mutation)", isIntermittent: true) {
			do { _ = try verifyPreview(session: session, project: project) } catch {
				rejected = true
			}
		}
		#expect(rejected, "Invalid evidence accepted: \(mutation), nested=\(nested)")
	}
}

@Test func createPreviewCanonicalArchiveWithAliasClientOffline() throws {
	for nested in [false, true] {
		let fixture = try PreviewAuditFixture()
		defer { fixture.remove() }
		let session = try fixture.store(
			nested: nested,
			arguments: ["viewPath": fixture.viewPath, "screenSize": ["width": 64, "height": 64]])
		let clientProject = URL(fileURLWithPath: "/System/Volumes/Data" + fixture.project.path)
		#expect(clientProject.path != fixture.project.path)
		let preview = try verifyPreview(session: session, project: clientProject)
		#expect(preview.reviewPath.path == fixture.review.path)
		let request = try counterVisionRequest(
			preview, identity: UUID(), model: "gemini-3.8-flash",
			criteria: [["id": "offline", "description": "No reviewer invoked"]])
		let object = try #require(JSONSerialization.jsonObject(with: request) as? [String: Any])
		#expect(object["imagePath"] as? String == fixture.review.path)
	}
}

private struct PreviewAuditFixture {
	let root: URL
	let project: URL
	let sessionID = UUID().uuidString.lowercased()
	let viewPath = "Sources/AppViews/ApplicationRoot.swift"
	let relative = ".mac-apper/Artifacts/\(UUID().uuidString.lowercased())/render.png"
	let bytes: Data
	let width: Int
	let height: Int
	var source: URL { project.appendingPathComponent(viewPath) }
	var artifact: URL { project.appendingPathComponent(relative) }
	var review: URL {
		root.appendingPathComponent(
			"previews/\(project.lastPathComponent)/\(sessionID)/preview-123.png")
	}
	var result: [String: Any] {
		[
			"status": "rendered", "width": width, "height": height,
			"artifact": ["kind": "png", "relativePath": relative, "reviewPath": review.path],
		]
	}
	var run: [String: Any] {
		[
			"target": "ProductionApp",
			"relativePath": ".mac-apper/DevBuild/\(UUID().uuidString.lowercased())/ProductionApp.app",
		]
	}
	init(width: Int = 64, height: Int = 64) throws {
		root = try ProjectTemporaryDirectory.appending("mac-apper-preview-audit-\(UUID().uuidString)")
		project = root.appendingPathComponent(UUID().uuidString.lowercased())
		self.width = width; self.height = height
		bytes = try auditPNG(width: width, height: height)
		for file in [source, artifact, review] {
			try FileManager.default.createDirectory(
				at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
		}
		try Data("// Scoped offline source".utf8).write(to: source)
		try Data("{\"executableTarget\":\"ProductionApp\"}".utf8).write(
			to: project.appendingPathComponent("app-manifest.json"))
		try replacePNG(bytes)
	}
	func replacePNG(_ data: Data) throws {
		try data.write(to: artifact); try data.write(to: review)
	}
	func link(_ url: URL) throws {
		let target = root.appendingPathComponent("link-target-\(UUID().uuidString)")
		try FileManager.default.moveItem(at: url, to: target)
		try FileManager.default.createSymbolicLink(at: url, withDestinationURL: target)
	}
	func store(
		nested: Bool, arguments: [String: Any], names: [String] = ["preview", "build", "run"],
		results: [[String: Any]]? = nil
	) throws -> URL {
		let evidence = try orderedEvidenceFixture(
			names: names, nested: nested, path: "", arguments: [arguments, [:], [:]],
			results: results ?? [result, ["target": "ProductionApp", "summary": "Built"], run])
		return try storeAuditFixture(evidence, project: project, sessionID: sessionID)
	}
	func remove() { try? FileManager.default.removeItem(at: root) }
}
