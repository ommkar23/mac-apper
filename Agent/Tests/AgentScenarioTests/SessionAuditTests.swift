// @frontmatter:start
// Tests runtime-profile and validated existing-directory session scope without model calls.
// @frontmatter:end
import AgentScenarioSupport
import Foundation
import Testing

private func auditFixture() throws -> URL {
	let root = URL(fileURLWithPath: "/private/tmp/session-audit-\(UUID().uuidString)")
	try FileManager.default.createDirectory(
		at: root, withIntermediateDirectories: false, attributes: [.posixPermissions: 0o700])
	return root
}

private func auditData(
	cwd: String, provider: String = "openai-codex", model: String = "gpt-6.1-sol",
	thinking: String = "medium", assistantModel: String = "gpt-6.1-sol"
) throws -> Data {
	let records: [[String: Any]] = [
		["type": "session", "cwd": cwd],
		["type": "model_change", "provider": provider, "modelId": model],
		["type": "thinking_level_change", "thinkingLevel": thinking],
		[
			"type": "message",
			"message": ["role": "user", "content": [["type": "text", "text": "opaque token"]]],
		],
		[
			"type": "message",
			"message": ["role": "assistant", "provider": provider, "model": assistantModel],
		],
	]
	return try records.reduce(into: Data()) { result, record in
		result.append(try JSONSerialization.data(withJSONObject: record)); result.append(10)
	}
}

@Test func sessionAuditRequiresExplicitRequestedProfile() throws {
	let project = try auditFixture()
	defer { try? FileManager.default.removeItem(at: project) }
	let audit = try ScenarioSessionAudit.read(
		auditData(cwd: project.path), expectedProject: project.path)
	#expect(audit.profile == .required)
	#expect(audit.userTexts == ["opaque token"])
	#expect(audit.assistantCount == 1)
	for data in [
		try auditData(cwd: project.path, provider: "openai"),
		try auditData(cwd: project.path, model: "other"),
		try auditData(cwd: project.path, thinking: "high"),
		try auditData(cwd: project.path, assistantModel: "other"),
	] {
		#expect(throws: (any Error).self) {
			try ScenarioSessionAudit.read(data, expectedProject: project.path)
		}
	}
}

@Test func sessionAuditRejectsForeignScopePartialTailAndOversizedData() throws {
	let project = try auditFixture()
	defer { try? FileManager.default.removeItem(at: project) }
	let data = try auditData(cwd: project.path)
	#expect(throws: (any Error).self) {
		try ScenarioSessionAudit.read(data, expectedProject: "/foreign")
	}
	#expect(throws: (any Error).self) {
		try ScenarioSessionAudit.read(Data(data.dropLast()), expectedProject: project.path)
	}
	#expect(throws: (any Error).self) {
		try ScenarioSessionAudit.read(
			Data(repeating: 10, count: 4_194_305), expectedProject: project.path)
	}
}

@Test func sessionAuditAcceptsTrustedOSDirectoryAliases() throws {
	let root = try auditFixture()
	defer { try? FileManager.default.removeItem(at: root) }
	let project = root.appendingPathComponent(".mac-apper/\(UUID().uuidString.lowercased())")
	try FileManager.default.createDirectory(at: project, withIntermediateDirectories: true)
	let alias = "/tmp/\(root.lastPathComponent)/.mac-apper/\(project.lastPathComponent)"
	for (cwd, expected) in [(project.path, alias), (alias, project.path), (alias, alias)] {
		let audit = try ScenarioSessionAudit.read(auditData(cwd: cwd), expectedProject: expected)
		#expect(audit.profile == .required)
	}
	// A second OS alias ensures the implementation is not a /tmp spelling substitution.
	let temporary = FileManager.default.temporaryDirectory
	let other = temporary.appendingPathComponent("session-audit-\(UUID().uuidString)")
	try FileManager.default.createDirectory(at: other, withIntermediateDirectories: false)
	defer { try? FileManager.default.removeItem(at: other) }
	let canonical = "/private" + other.path
	try #require(other.path.hasPrefix("/var/"))
	#expect(
		try ScenarioSessionAudit.read(auditData(cwd: canonical), expectedProject: other.path).profile
			== .required)
	#expect(
		try ScenarioSessionAudit.read(auditData(cwd: other.path), expectedProject: canonical).profile
			== .required)
}

@Test func sessionAuditRejectsUnsafeOrNonexistentDirectoryIdentity() throws {
	let root = try auditFixture()
	defer { try? FileManager.default.removeItem(at: root) }
	let manager = FileManager.default
	let project = root.appendingPathComponent("project")
	let foreign = root.appendingPathComponent("foreign/project")
	try manager.createDirectory(at: project, withIntermediateDirectories: false)
	try manager.createDirectory(at: foreign, withIntermediateDirectories: true)
	try manager.createDirectory(
		at: project.appendingPathComponent("child"), withIntermediateDirectories: false)
	try Data("file".utf8).write(to: root.appendingPathComponent("file"))
	try manager.createSymbolicLink(
		at: root.appendingPathComponent("link"), withDestinationURL: project)
	try manager.createSymbolicLink(
		at: root.appendingPathComponent("ancestor"), withDestinationURL: root)
	try manager.createSymbolicLink(
		at: root.appendingPathComponent("dangling"),
		withDestinationURL: root.appendingPathComponent("missing"))
	let unsafe = [
		foreign.path, project.appendingPathComponent("child").path,
		root.appendingPathComponent("missing").path, root.appendingPathComponent("file").path,
		root.appendingPathComponent("link").path, root.appendingPathComponent("ancestor/project").path,
		root.appendingPathComponent("dangling").path,
		"/tmp/\(root.lastPathComponent)/link", "/tmp/\(root.lastPathComponent)/ancestor/project",
		root.appendingPathComponent("file/child").path,
		"/" + String(repeating: "x", count: 4097),
		root.path + "/foreign/../project", root.path + "/./project", root.path + "//project",
		"relative/project", project.path + "\0", project.path + "\\suffix",
	]
	for path in unsafe {
		for (cwd, expected) in [(path, project.path), (project.path, path)] {
			#expect(throws: SessionAuditError.self) {
				try ScenarioSessionAudit.read(auditData(cwd: cwd), expectedProject: expected)
			}
		}
	}
	// Equal spellings must still validate existence, type, traversal, and links.
	for path in unsafe.dropFirst(2) {
		#expect(throws: SessionAuditError.self) {
			try ScenarioSessionAudit.read(auditData(cwd: path), expectedProject: path)
		}
	}
}
