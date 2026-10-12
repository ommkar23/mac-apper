// @frontmatter:start
// Tests project resolution, SwiftPM package presence, and scoped path rejection.
// @frontmatter:end
import Foundation
import Testing

@testable import DevToolsApplication

@Test func scopedProjectRequestsRequireAnExistingNonlinkedSwiftPackage() async throws {
	let base = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
	try FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
	defer { try? FileManager.default.removeItem(at: base) }
	let projectID = UUID().uuidString.lowercased()
	let sessionID = UUID().uuidString.lowercased()
	let project = base.appendingPathComponent(projectID)
	try FileManager.default.createDirectory(at: project, withIntermediateDirectories: true)
	try Data(
		"{\"schemaVersion\":1,\"appID\":\"\(projectID)\",\"executableTarget\":\"ProductionApp\",\"previewTarget\":\"PreviewApp\",\"devServiceID\":\"com.macapper.generated.\(projectID)\"}"
			.utf8
	)
	.write(to: project.appendingPathComponent("app-manifest.json"))
	let registry = ProjectResolver(projectsRoot: base)
	await #expect(throws: (any Error).self) {
		try await registry.lookup(projectRoot: project.path, projectID: projectID, sessionID: sessionID)
	}
	let manifest = project.appendingPathComponent("Package.swift")
	try "// swift-tools-version: 6.0\n".write(to: manifest, atomically: true, encoding: .utf8)
	let result = try await registry.lookup(
		projectRoot: project.path, projectID: projectID, sessionID: sessionID)
	#expect(result.manifest.appID == projectID)
	await #expect(throws: (any Error).self) {
		try await registry.lookup(
			projectRoot: project.path + "/../" + projectID,
			projectID: projectID, sessionID: sessionID)
	}
	await #expect(throws: (any Error).self) {
		try await registry.lookup(projectRoot: base.path, projectID: projectID, sessionID: sessionID)
	}
	try FileManager.default.removeItem(at: manifest)
	try FileManager.default.createSymbolicLink(
		at: manifest, withDestinationURL: base.appendingPathComponent("foreign.swift"))
	await #expect(throws: (any Error).self) {
		try await registry.lookup(projectRoot: project.path, projectID: projectID, sessionID: sessionID)
	}
}
