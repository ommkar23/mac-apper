// @frontmatter:start
// Tests BuildController SwiftPM product selection, cancellation, and build isolation.
// @frontmatter:end
import Foundation
import Testing

@testable import DevToolsApplication

@Test func buildUsesOnlyTheManifestExecutableTargetAndNeverPackages() async throws {
	let fixture = try BuildFixture()
	defer { fixture.remove() }

	let runner = BuildController(
		projects: ProjectResolver(projectsRoot: fixture.root), gate: DevToolsOperationGate(),
		xcrunURL: fixture.tool, outputLimitBytes: 4_096,
		environment: ["DEVTOOLS_CAPTURE": fixture.capture.path])
	let result = try await runner.build(
		project: try await fixture.approvedProject(), requestID: fixture.requestID)

	let arguments = try String(contentsOf: fixture.capture, encoding: .utf8)
		.split(separator: "\n").map(String.init)
	#expect(
		arguments == [
			"swift", "build", "--product", "ProductionApp", "--configuration", "debug", "--scratch-path",
			result.buildDirectory.path,
		])
	#expect(result.target == "ProductionApp")
	#expect(result.buildDirectory.path.contains(".mac-apper/Build/\(fixture.requestID)"))
	#expect(
		!FileManager.default.fileExists(
			atPath: fixture.root.appendingPathComponent("dist/Production.app").path))
	#expect(
		!arguments.contains(where: { ["package", "codesign", "open", "lsregister"].contains($0) }))
}

@Test func buildPreservesValidUppercaseRequestIdentity() async throws {
	let fixture = try BuildFixture()
	defer { fixture.remove() }
	let requestID = fixture.requestID.uppercased()
	let runner = BuildController(
		projects: ProjectResolver(projectsRoot: fixture.root), gate: DevToolsOperationGate(),
		xcrunURL: fixture.tool,
		environment: ["DEVTOOLS_CAPTURE": fixture.capture.path])
	let result = try await runner.build(project: fixture.approvedProject(), requestID: requestID)
	#expect(result.buildDirectory.lastPathComponent == requestID)
}

@Test func cancellingBuildTerminatesTheOwnedCompilerProcess() async throws {
	let fixture = try BuildFixture()
	defer { fixture.remove() }
	let started = fixture.root.appendingPathComponent("started")
	let stopped = fixture.root.appendingPathComponent("stopped")
	try """
	#!/bin/sh
	trap 'printf stopped > "$DEVTOOLS_STOPPED"; exit 0' INT TERM
	printf started > "$DEVTOOLS_STARTED"
	while :; do :; done
	""".write(to: fixture.tool, atomically: true, encoding: .utf8)
	let runner = BuildController(
		projects: ProjectResolver(projectsRoot: fixture.root), gate: DevToolsOperationGate(),
		xcrunURL: fixture.tool, outputLimitBytes: 4_096,
		environment: ["DEVTOOLS_STARTED": started.path, "DEVTOOLS_STOPPED": stopped.path])

	let task = Task {
		try await runner.build(
			project: try await fixture.approvedProject(), requestID: fixture.requestID)
	}
	let deadline = ContinuousClock.now.advanced(by: .seconds(5))
	while !FileManager.default.fileExists(atPath: started.path), ContinuousClock.now < deadline {
		try await Task.sleep(for: .milliseconds(10))
	}
	// Cancellation is tested only after the fixture has installed its TERM handler.
	let wasReady = FileManager.default.fileExists(atPath: started.path)
	task.cancel()
	await #expect(throws: CancellationError.self) { try await task.value }
	#expect(wasReady)
	#expect(FileManager.default.fileExists(atPath: stopped.path))
}

@Test func cancellingBuildCleansResistantDescendantAfterLeaderExit() async throws {
	let fixture = try BuildFixture()
	defer { fixture.remove() }
	let childFile = fixture.root.appendingPathComponent("child")
	try """
	#!/bin/sh
	trap 'exit 0' TERM
	/bin/sh -c 'trap "" TERM; printf "%s" "$$" > "$DEVTOOLS_CHILD.tmp"; /bin/mv "$DEVTOOLS_CHILD.tmp" "$DEVTOOLS_CHILD"; while :; do /bin/sleep 1; done' &
	wait
	""".write(to: fixture.tool, atomically: true, encoding: .utf8)
	let runner = BuildController(
		projects: ProjectResolver(projectsRoot: fixture.root), gate: DevToolsOperationGate(),
		xcrunURL: fixture.tool,
		environment: ["DEVTOOLS_CHILD": childFile.path])
	let task = Task {
		try await runner.build(project: fixture.approvedProject(), requestID: fixture.requestID)
	}
	let deadline = ContinuousClock.now.advanced(by: .seconds(5))
	while !FileManager.default.fileExists(atPath: childFile.path), ContinuousClock.now < deadline {
		try await Task.sleep(for: .milliseconds(10))
	}
	let childValue = (try? String(contentsOf: childFile, encoding: .utf8)).flatMap(Int32.init)
	task.cancel()
	await #expect(throws: CancellationError.self) { try await task.value }
	let child = try #require(childValue)
	defer { if kill(child, 0) == 0 { kill(child, SIGKILL) } }
	let stopDeadline = ContinuousClock.now.advanced(by: .seconds(2))
	while kill(child, 0) == 0, ContinuousClock.now < stopDeadline {
		try await Task.sleep(for: .milliseconds(10))
	}
	#expect(kill(child, 0) == -1, "Cancellation must clean the descendant, not just its leader")
}

private struct BuildFixture {
	let root: URL
	let projectID: String
	let sessionID = UUID().uuidString
	let requestID = UUID().uuidString.lowercased()
	let tool: URL
	let capture: URL

	init() throws {
		root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
		try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
		projectID = UUID().uuidString.lowercased()
		let projectRoot = root.appendingPathComponent(projectID)
		try FileManager.default.createDirectory(at: projectRoot, withIntermediateDirectories: true)
		try Data(
			"""
			{"schemaVersion":1,"appID":"\(projectID)","executableTarget":"ProductionApp","previewTarget":"PreviewApp","devServiceID":"com.macapper.generated.\(projectID)"}
			""".utf8
		).write(to: projectRoot.appendingPathComponent("app-manifest.json"))
		try "// swift-tools-version: 6.0\n".write(
			to: projectRoot.appendingPathComponent("Package.swift"), atomically: true,
			encoding: .utf8)
		capture = root.appendingPathComponent("arguments.txt")
		tool = root.appendingPathComponent("fixture-xcrun")
		try "#!/bin/sh\nprintf '%s\\n' \"$@\" > \"$DEVTOOLS_CAPTURE\"\n".write(
			to: tool, atomically: true, encoding: .utf8)
		try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: tool.path)
	}

	func approvedProject() async throws -> ResolvedProject {
		let registry = ProjectResolver(projectsRoot: root)
		return try await registry.lookup(
			projectRoot: root.appendingPathComponent(projectID).path,
			projectID: projectID, sessionID: sessionID)
	}

	func remove() { try? FileManager.default.removeItem(at: root) }
}
