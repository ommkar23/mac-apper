// @frontmatter:start
// Tests scoped SwiftPM testing, result diagnostics, scratch cleanup, bounds, cancellation, and factory routing.
// @frontmatter:end
import Foundation
import Testing

@testable import DevToolsApplication

@Test func testControllerRunsPackageTestsAndRemovesOnlyItsScratch() async throws {
	let fixture = try TestFixture()
	defer { fixture.remove() }
	let runner = fixture.controller()
	let result = try await runner.runTests(
		project: fixture.approvedProject(), requestID: fixture.requestID)
	#expect(result.status == "passed" && result.exitCode == 0)
	#expect(result.diagnostics == "fixture tests passed" && !result.outputTruncated)
	let arguments = try String(contentsOf: fixture.capture, encoding: .utf8)
		.split(separator: "\n").map(String.init)
	let scratch = fixture.project.appendingPathComponent(".mac-apper/TestBuild/\(fixture.requestID)")
	#expect(
		arguments == [
			"swift", "test", "--configuration", "debug", "--scratch-path",
			scratch.resolvingSymlinksInPath().path,
		])
	#expect(!FileManager.default.fileExists(atPath: scratch.path))
	#expect(
		!FileManager.default.fileExists(atPath: fixture.project.appendingPathComponent(".build").path))
	#expect(
		FileManager.default.fileExists(
			atPath: fixture.project.appendingPathComponent("Package.swift").path))
}

@Test func testControllerReportsFailuresWithBoundedUTF8Diagnostics() async throws {
	let fixture = try TestFixture()
	defer { fixture.remove() }
	let output = String(repeating: "🙂", count: 2_000) + "\nEXPECTED_ASSERTION_FAILURE"
	let result = try await fixture.controller(output: output, exitCode: "1").runTests(
		project: fixture.approvedProject(), requestID: fixture.requestID)
	#expect(result.status == "failed" && result.exitCode == 1)
	#expect(result.diagnostics.hasSuffix("EXPECTED_ASSERTION_FAILURE"))
	#expect(result.diagnostics.utf8.count <= 4_096 && !result.diagnostics.contains("�"))
	#expect(result.outputTruncated)
	#expect(
		try FileManager.default.contentsOfDirectory(
			atPath: fixture.project.appendingPathComponent(".mac-apper/TestBuild").path
		).isEmpty)
}

@Test func testControllerKeepsCompilerErrorsInsteadOfSwiftBuildCommandDumps() async throws {
	let fixture = try TestFixture()
	defer { fixture.remove() }
	let output =
		"Tests/Checks.swift:4:1: error: EXPECTED_COMPILER_FAILURE\nFailed frontend command:\n/standalone/usr/bin/swift-frontend -frontend "
		+ String(repeating: "-I /long/generated/path ", count: 400)
		+ "\nFailed SwiftDriver command:\n    builtin-SwiftDriver -- /standalone/usr/bin/swiftc "
		+ String(repeating: "-I /long/generated/path ", count: 400) + "\nerror: Build failed\n"
	let result = try await fixture.controller(output: output, exitCode: "1").runTests(
		project: fixture.approvedProject(), requestID: fixture.requestID)
	#expect(result.status == "failed" && result.exitCode == 1)
	#expect(result.diagnostics.contains("EXPECTED_COMPILER_FAILURE"))
	#expect(result.diagnostics.contains("error: Build failed"))
	#expect(!result.diagnostics.contains("-I /long/generated/path"))
	#expect(result.diagnostics.utf8.count <= 4096 && result.outputTruncated)
}

@Test func testControllerBoundsOutputAndTimeoutAndCleansScratch() async throws {
	let fixture = try TestFixture()
	defer { fixture.remove() }
	let overflow = try await fixture.controller(
		output: String(repeating: "x", count: 1_024), limit: 64
	).runTests(
		project: fixture.approvedProject(), requestID: fixture.requestID)
	#expect(overflow.status == "error" && overflow.exitCode == nil && overflow.outputTruncated)
	#expect(overflow.summary.contains("output"))
	try "#!/bin/sh\nwhile :; do :; done\n".write(to: fixture.tool, atomically: true, encoding: .utf8)
	let timeout = try await fixture.controller(timeout: .milliseconds(50)).runTests(
		project: fixture.approvedProject(), requestID: UUID().uuidString)
	#expect(timeout.status == "error" && timeout.exitCode == nil)
	#expect(timeout.summary.contains("deadline"))
	#expect(
		try FileManager.default.contentsOfDirectory(
			atPath: fixture.project.appendingPathComponent(".mac-apper/TestBuild").path
		).isEmpty)
}

@Test func testControllerCancellationStopsItsProcessAndRemovesScratch() async throws {
	let fixture = try TestFixture()
	defer { fixture.remove() }
	let started = fixture.root.appendingPathComponent("started")
	let stopped = fixture.root.appendingPathComponent("stopped")
	try """
	#!/bin/sh
	trap 'printf stopped > "$TEST_STOPPED"; exit 0' INT TERM
	printf started > "$TEST_STARTED"
	while :; do :; done
	""".write(to: fixture.tool, atomically: true, encoding: .utf8)
	let runner = TestController(
		projects: ProjectResolver(projectsRoot: fixture.root), gate: DevToolsOperationGate(),
		xcrunURL: fixture.tool,
		environment: ["TEST_STARTED": started.path, "TEST_STOPPED": stopped.path])
	let project = try await fixture.approvedProject()
	let task = Task { try await runner.runTests(project: project, requestID: fixture.requestID) }
	let deadline = ContinuousClock.now.advanced(by: .seconds(5))
	while !FileManager.default.fileExists(atPath: started.path), ContinuousClock.now < deadline {
		try await Task.sleep(for: .milliseconds(10))
	}
	let ready = FileManager.default.fileExists(atPath: started.path)
	task.cancel()
	await #expect(throws: CancellationError.self) { try await task.value }
	#expect(ready && FileManager.default.fileExists(atPath: stopped.path))
	#expect(
		!FileManager.default.fileExists(
			atPath: fixture.project.appendingPathComponent(".mac-apper/TestBuild/\(fixture.requestID)")
				.path))
}

@Test func testControllerRejectsForeignScopeAndPreservesExistingScratch() async throws {
	let fixture = try TestFixture()
	defer { fixture.remove() }
	let factory = ControllerFactory(projectsRoot: fixture.root, xcrunURL: fixture.tool)
	await #expect(throws: (any Error).self) {
		_ = try await factory.controllers().test.handle(
			UUID(uuidString: fixture.projectID)!, UUID(), TestRequest(projectRoot: fixture.root.path))
	}
	let scratch = fixture.project.appendingPathComponent(".mac-apper/TestBuild/\(fixture.requestID)")
	try FileManager.default.createDirectory(at: scratch, withIntermediateDirectories: true)
	let sentinel = scratch.appendingPathComponent("keep")
	try Data().write(to: sentinel)
	await #expect(throws: (any Error).self) {
		_ = try await fixture.controller().runTests(
			project: fixture.approvedProject(), requestID: fixture.requestID)
	}
	#expect(FileManager.default.fileExists(atPath: sentinel.path))
	await #expect(throws: (any Error).self) {
		_ = try await fixture.controller().runTests(
			project: fixture.approvedProject(), requestID: "../foreign")
	}
}

@Test func testControllerRejectsLinkedScratchAndReportsMissingTool() async throws {
	let fixture = try TestFixture()
	defer { fixture.remove() }
	let runner = TestController(
		projects: ProjectResolver(projectsRoot: fixture.root), gate: DevToolsOperationGate(),
		xcrunURL: fixture.root.appendingPathComponent("missing-tool"))
	let result = try await runner.runTests(
		project: fixture.approvedProject(), requestID: fixture.requestID)
	#expect(result.status == "error" && result.exitCode == nil)
	let scratchRoot = fixture.project.appendingPathComponent(".mac-apper/TestBuild")
	try FileManager.default.removeItem(at: scratchRoot)
	try FileManager.default.createSymbolicLink(at: scratchRoot, withDestinationURL: fixture.root)
	await #expect(throws: (any Error).self) {
		_ = try await fixture.controller().runTests(
			project: fixture.approvedProject(), requestID: fixture.requestID)
	}
	#expect(
		!FileManager.default.fileExists(
			atPath: fixture.root.appendingPathComponent(fixture.requestID).path))
}

@Test func testControllerReportsRequiredToolchainAndCleansScratchBeforeLaunch() async throws {
	let fixture = try TestFixture()
	defer { fixture.remove() }
	let manager = FileManager.default
	let bin = fixture.root.appendingPathComponent("standalone-bin")
	try manager.createDirectory(at: bin, withIntermediateDirectories: false)
	let manifest = fixture.project.appendingPathComponent("Package.swift")
	let original = try Data(contentsOf: manifest)
	let existingBuild = fixture.project.appendingPathComponent(".build")
	try manager.createDirectory(at: existingBuild, withIntermediateDirectories: false)
	let sentinel = existingBuild.appendingPathComponent("keep")
	try Data("keep".utf8).write(to: sentinel)
	for missing in ["swift", "swiftc"] {
		let present = bin.appendingPathComponent(missing == "swift" ? "swiftc" : "swift")
		try manager.copyItem(at: URL(fileURLWithPath: "/usr/bin/true"), to: present)
		defer { try? manager.removeItem(at: present) }
		let runner = TestController(
			projects: ProjectResolver(projectsRoot: fixture.root), gate: DevToolsOperationGate(),
			toolchainBin: bin)
		let result = try await runner.runTests(
			project: fixture.approvedProject(), requestID: fixture.requestID)
		#expect(result.status == "error" && result.exitCode == nil)
		#expect(result.summary.contains("standalone Swift 6.4.0"))
		#expect(result.summary.contains(bin.appendingPathComponent(missing).path))
		#expect(
			!manager.fileExists(
				atPath: fixture.project.appendingPathComponent(
					".mac-apper/TestBuild/\(fixture.requestID)"
				).path))
		#expect(try Data(contentsOf: manifest) == original)
		#expect(try Data(contentsOf: sentinel) == Data("keep".utf8))
	}
}

@Test func typedTestControllerRoutesThroughGeneratedDispatcher() async throws {
	let fixture = try TestFixture()
	defer { fixture.remove() }
	let factory = ControllerFactory(
		projectsRoot: fixture.root, xcrunURL: fixture.tool,
		environment: ["TEST_CAPTURE": fixture.capture.path, "TEST_OUTPUT": "passed", "TEST_EXIT": "0"])
	let router = OpenXPCGeneratedService(controllers: factory.controllers())
	let requestID = UUID()
	let request = try JSONSerialization.data(withJSONObject: [
		"version": 1, "requestID": requestID.uuidString, "projectID": fixture.projectID,
		"sessionID": UUID().uuidString, "command": "test",
		"payload": try JSONEncoder().encode(TestRequest(projectRoot: fixture.project.path))
			.base64EncodedString(),
	])
	let reply = await withCheckedContinuation { continuation in
		router.execute(request) { continuation.resume(returning: $0) }
	}
	let envelope = try #require(JSONSerialization.jsonObject(with: reply) as? [String: Any])
	#expect(envelope["success"] as? Bool == true)
	#expect(envelope["requestID"] as? String == requestID.uuidString)
	let encoded = try #require(envelope["payload"] as? String)
	let payload = try #require(Data(base64Encoded: encoded))
	let result = try JSONDecoder().decode(TestResult.self, from: payload)
	#expect(result.status == "passed" && result.exitCode == 0)
}

private struct TestFixture {
	let root: URL
	let projectID = UUID().uuidString.lowercased()
	let requestID = UUID().uuidString.lowercased()
	let tool: URL
	let capture: URL
	var project: URL { root.appendingPathComponent(projectID) }

	init() throws {
		root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
		tool = root.appendingPathComponent("xcrun-fixture")
		capture = root.appendingPathComponent("arguments")
		try FileManager.default.createDirectory(at: project, withIntermediateDirectories: true)
		try "// swift-tools-version: 6.0\n".write(
			to: project.appendingPathComponent("Package.swift"), atomically: true, encoding: .utf8)
		try Data(
			"""
			{"schemaVersion":1,"appID":"\(projectID)","executableTarget":"ProductionApp","previewTarget":"PreviewApp","devServiceID":"com.macapper.generated.\(projectID)"}
			""".utf8
		).write(to: project.appendingPathComponent("app-manifest.json"))
		try """
		#!/bin/sh
		printf '%s\\n' "$@" > "$TEST_CAPTURE"
		printf '%s' "$TEST_OUTPUT"
		exit "$TEST_EXIT"
		""".write(to: tool, atomically: true, encoding: .utf8)
		try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: tool.path)
	}
	func controller(
		output: String = "fixture tests passed", exitCode: String = "0", limit: Int = 65_536,
		timeout: Duration = .seconds(180)
	) -> TestController {
		TestController(
			projects: ProjectResolver(projectsRoot: root), gate: DevToolsOperationGate(), xcrunURL: tool,
			outputLimitBytes: limit,
			environment: ["TEST_CAPTURE": capture.path, "TEST_OUTPUT": output, "TEST_EXIT": exitCode],
			timeout: timeout)
	}
	func approvedProject() async throws -> ResolvedProject {
		try await ProjectResolver(projectsRoot: root).lookup(
			projectRoot: project.path, projectID: projectID, sessionID: UUID().uuidString)
	}
	func remove() { try? FileManager.default.removeItem(at: root) }
}
