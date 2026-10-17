// @frontmatter:start
// Checks Create Plan scope-only policy and fail-closed lifecycle acknowledgements without starting sessions.
// @frontmatter:end
import AgentScenarioSupport
import Foundation
import Scenario
import Testing

@Suite @MainActor struct CreatePlanContractTests {
	@Test func actualPlanFactoryRetainsScopeOnlyPolicyAndUnconfirmedCleanup() throws {
		let collection = createCounterCollection(requirePlan: true)
		let registry = try ScenarioRegistry([collection])
		#expect(registry.collectionNames == ["agent-create"])
		#expect(registry.caseNames == ["create-counter-plan"])
		let text = try String(
			contentsOf: URL(fileURLWithPath: #filePath).deletingLastPathComponent()
				.appendingPathComponent("CreateCounterTests.swift"), encoding: .utf8)
		let scopeStart = try #require(text.range(of: "func auditPlanSessionScope("))
		let outcomeStart = try #require(text.range(of: "struct PlanCleanupOutcome"))
		let scope = String(text[scopeStart.lowerBound..<outcomeStart.lowerBound])
		for forbidden in [
			"ScenarioSessionAudit", "--tools", "/bin/ps", "ownedPi", "model", "thinking", "extension",
		] {
			#expect(!scope.contains(forbidden))
		}
		for required in [
			"ScenarioDirectoryIdentity.read(parent.path)",
			"ScenarioDirectoryIdentity.read(project.appendingPathComponent(\".pi/sessions\").path)",
			"O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC",
			"O_RDONLY | O_NOFOLLOW | O_NONBLOCK | O_CLOEXEC",
			"info.st_mode & S_IFMT == S_IFREG", "info.st_size > 0", "info.st_size <= 4_194_304",
			"read(upToCount: 65_537)", "newline <= 65_536", "header[\"type\"] as? String == \"session\"",
			"ScenarioDirectoryIdentity.read(cwd) == ScenarioDirectoryIdentity.read(project.path)",
		] { #expect(scope.contains(required)) }
		#expect(text.contains("var cleanupConfirmed: Bool { false }"))
		let start = try #require(text.range(of: "private func cleanupPlan()"))
		let end = try #require(text.range(of: "override func cleanupResources()"))
		let cleanup = String(text[start.lowerBound..<end.lowerBound])
		#expect(cleanup.contains("let outcome = await finishPlanLifecycle("))
		#expect(cleanup.contains("try auditPlanSessionScope(file: file, project: project)"))
		#expect(cleanup.contains("outcome.cleanupConfirmed"))
		#expect(cleanup.contains("Pi/descendant quiescence not confirmed"))
		for forbidden in [
			"/bin/ps", "ownedPi", ".reap(", "removeItem", "CreateScenarioIsolation.archive",
			"CreateScenarioIsolation.confirmation",
		] {
			#expect(!cleanup.contains(forbidden))
		}
	}
}

@Test func createPlanInterfacePolicyOffline() throws {
	let text = try String(
		contentsOf: URL(fileURLWithPath: #filePath).deletingLastPathComponent()
			.appendingPathComponent("CreateCounterTests.swift"), encoding: .utf8)
	let source = String(
		text.prefix(upTo: try #require(text.range(of: "private func command(")).lowerBound))
	#expect(source.contains("if !requirePlan, capturedArguments == nil"))
	#expect(source.contains("if requirePlan {\n\t\t\ttry await cleanupPlan()\n\t\t\treturn"))
	#expect(
		source.contains(
			"if requirePlan {\n\t\t\ttry auditPlanSessionScope(file: file, project: project)\n\t\t} else {"
		))
	let cleanup = String(
		source.suffix(from: try #require(source.range(of: "private func cleanupPlan()")).lowerBound))
	let planOnly = cleanup.prefix(
		upTo: try #require(cleanup.range(of: "\n\toverride func cleanupResources()")).lowerBound)
	for forbidden in [
		"/bin/ps", "ownedPi", ".reap(", "removeItem", "CreateScenarioIsolation.confirmation",
	] {
		#expect(!planOnly.contains(forbidden))
	}
}

@Test func createPlanInterfaceScopeOffline() throws {
	let root = try ProjectTemporaryDirectory.appending("plan-scope-offline-\(UUID().uuidString)")
	try FileManager.default.createDirectory(
		at: root, withIntermediateDirectories: false, attributes: [.posixPermissions: 0o700])
	defer { try? FileManager.default.removeItem(at: root) }
	let project = root.appendingPathComponent("project")
	let sessions = project.appendingPathComponent(".pi/sessions")
	try FileManager.default.createDirectory(at: sessions, withIntermediateDirectories: true)
	let file = sessions.appendingPathComponent("session.jsonl")
	func header(_ cwd: String) throws -> Data {
		var data = try JSONSerialization.data(withJSONObject: ["type": "session", "cwd": cwd])
		data.append(10)
		// Deliberately no model/thinking/extension metadata: this is scope, not runtime policy.
		return data
	}
	try header(project.path).write(to: file)
	try auditPlanSessionScope(file: file, project: project)
	try header(root.path).write(to: file)
	#expect(throws: (any Error).self) { try auditPlanSessionScope(file: file, project: project) }
	try header(project.path + "/../project").write(to: file)
	#expect(throws: (any Error).self) { try auditPlanSessionScope(file: file, project: project) }
	let link = root.appendingPathComponent("linked-project")
	try FileManager.default.createSymbolicLink(at: link, withDestinationURL: project)
	try header(link.path).write(to: file)
	#expect(throws: (any Error).self) { try auditPlanSessionScope(file: file, project: project) }
	try header(project.path).write(to: file)
	#expect(throws: (any Error).self) { try auditPlanSessionScope(file: file, project: link) }
	let linkedParent = project.appendingPathComponent("linked-sessions")
	try FileManager.default.createSymbolicLink(at: linkedParent, withDestinationURL: sessions)
	#expect(throws: (any Error).self) {
		try auditPlanSessionScope(
			file: linkedParent.appendingPathComponent(file.lastPathComponent), project: project)
	}
	let linkedFile = sessions.appendingPathComponent("linked.jsonl")
	try FileManager.default.createSymbolicLink(at: linkedFile, withDestinationURL: file)
	#expect(throws: (any Error).self) {
		try auditPlanSessionScope(file: linkedFile, project: project)
	}
	let outside = root.appendingPathComponent("outside.jsonl")
	try header(project.path).write(to: outside)
	#expect(throws: (any Error).self) { try auditPlanSessionScope(file: outside, project: project) }
	for invalid in ["{}\n", "{\"type\":\"message\",\"cwd\":\"/\"}\n", "not-json\n", "{}"] {
		try Data(invalid.utf8).write(to: file)
		#expect(throws: (any Error).self) { try auditPlanSessionScope(file: file, project: project) }
	}
	try Data(repeating: 120, count: 65_537).write(to: file)
	#expect(throws: (any Error).self) { try auditPlanSessionScope(file: file, project: project) }
	try Data(repeating: 120, count: 4_194_305).write(to: file)
	#expect(throws: (any Error).self) { try auditPlanSessionScope(file: file, project: project) }
}

@Test @MainActor func createPlanInterfaceCleanupOffline() async {
	var attempts: [String] = []
	let failed = await finishPlanLifecycle(
		attach: {
			attempts.append("attach"); throw ScenarioFailure.message("scope rejected")
		},
		stop: {
			attempts.append("stop"); return false
		},
		shutdown: {
			attempts.append("shutdown"); return false
		},
		completeSubmission: { attempts.append("submission") })
	#expect(attempts == ["attach", "stop", "shutdown", "submission"])
	#expect(failed.failures.count == 3)
	#expect(!failed.cleanupConfirmed)
	attempts = []
	let acknowledged = await finishPlanLifecycle(
		attach: { attempts.append("attach") },
		stop: {
			attempts.append("stop"); return true
		},
		shutdown: {
			attempts.append("shutdown"); return true
		},
		completeSubmission: { attempts.append("submission") })
	#expect(attempts == ["attach", "stop", "shutdown", "submission"])
	#expect(acknowledged.failures.isEmpty)
	#expect(!acknowledged.cleanupConfirmed, "Stop/detach acknowledgements do not prove quiescence")
}
