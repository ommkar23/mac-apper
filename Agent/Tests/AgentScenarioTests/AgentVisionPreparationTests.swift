// @frontmatter:start
// Tests optional Vision preparation selection, path rejection, and failure propagation without builds or credentials.
// @frontmatter:end
import Darwin
import Foundation
import Scenario
import Testing

private struct VisionFixture {
	let root: URL
	let products: URL
	let executable: URL
	init() throws {
		root = try ProjectTemporaryDirectory.appending("agent-vision-test-\(UUID().uuidString)")
		products = root.appendingPathComponent("products")
		executable = products.appendingPathComponent("vision-cli")
		try FileManager.default.createDirectory(at: products, withIntermediateDirectories: true)
		try Data("fixture; never executed".utf8).write(to: executable)
		try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: executable.path)
	}
	func remove() throws { try FileManager.default.removeItem(at: root) }
}

@Test func agentVisionPreparationExplicitProducts() throws {
	let fixture = try VisionFixture()
	defer { try? fixture.remove() }
	var calls: [(URL, [String])] = []
	var envReads = 0
	let config = fixture.root.appendingPathComponent("unread.env")
	let resource = try #require(
		try AgentVisionPreparation.resource(
			includeVision: true, root: fixture.root,
			environment: [
				"AGENT_VISION_PRODUCTS": fixture.products.path,
				"AGENT_SCENARIO_VISION_CLI": "/must/not/reuse",
			],
			envFile: {
				envReads += 1; return config
			}, run: { calls.append(($0, $1)) }))
	#expect(resource.source == fixture.executable)
	#expect(resource.relativePath == "VisionCLI/vision-cli")
	#expect(envReads == 1)
	#expect(calls.count == 1)
	#expect(calls.last?.0 == fixture.executable)
	#expect(calls.last?.1 == ["check-config", "--env-file", config.path])
}

@Test func agentVisionPreparationRejectsInvalidOverrides() throws {
	let fixture = try VisionFixture()
	defer { try? fixture.remove() }
	let manager = FileManager.default
	let link = fixture.root.appendingPathComponent("linked")
	try manager.createSymbolicLink(at: link, withDestinationURL: fixture.products)
	for path in [
		"", "relative", fixture.root.path + "/../products",
		fixture.root.path + "/./products", fixture.root.path + "//products",
		fixture.root.path + "/missing", link.path, link.appendingPathComponent("child").path,
		fixture.executable.path,
	] {
		var calls = 0
		#expect(throws: (any Error).self) {
			try AgentVisionPreparation.resource(
				includeVision: true, root: fixture.root, environment: ["AGENT_VISION_PRODUCTS": path],
				envFile: {
					Issue.record("Invalid override read configuration"); return fixture.root
				},
				run: { _, _ in calls += 1 })
		}
		#expect(calls == 0)
	}
	try manager.removeItem(at: fixture.executable)
	for kind in ["missing", "directory", "fifo", "link", "nonexecutable"] {
		if kind == "directory" {
			try manager.createDirectory(at: fixture.executable, withIntermediateDirectories: false)
		}
		if kind == "fifo" { #expect(mkfifo(fixture.executable.path, 0o700) == 0) }
		if kind == "link" {
			try manager.createSymbolicLink(
				at: fixture.executable, withDestinationURL: URL(fileURLWithPath: "/bin/true"))
		}
		if kind == "nonexecutable" {
			try Data().write(to: fixture.executable)
			try manager.setAttributes([.posixPermissions: 0o600], ofItemAtPath: fixture.executable.path)
		}
		#expect(throws: (any Error).self) {
			try AgentVisionPreparation.resource(
				includeVision: true, root: fixture.root,
				environment: ["AGENT_VISION_PRODUCTS": fixture.products.path],
				envFile: {
					Issue.record("Invalid executable read configuration"); return fixture.root
				},
				run: { _, _ in Issue.record("Invalid executable ran preparation") })
		}
		if kind != "missing" { try manager.removeItem(at: fixture.executable) }
	}
}

@Test func agentVisionPreparationLegacyAndDisabled() throws {
	let root = URL(fileURLWithPath: "/unused-repository")
	var calls: [(URL, [String])] = []
	let config = root.appendingPathComponent("alternate.env")
	let resource = try #require(
		try AgentVisionPreparation.resource(
			includeVision: true, root: root, environment: ["AGENT_SCENARIO_VISION_CLI": "/ignored"],
			envFile: { config }, run: { calls.append(($0, $1)) }))
	#expect(calls.count == 2)
	#expect(calls.first?.0.path == "/usr/bin/xcrun")
	#expect(
		calls.first?.1 == [
			"swift", "build", "--package-path", "/unused-repository/VisionCLI", "-c", "release",
		])
	#expect(resource.source.path == "/unused-repository/VisionCLI/.build/release/vision-cli")
	#expect(calls.last?.0 == resource.source)
	#expect(calls.last?.1 == ["check-config", "--env-file", config.path])
	for value in ["", "relative", "/missing"] {
		let disabled = try AgentVisionPreparation.resource(
			includeVision: false, root: root, environment: ["AGENT_VISION_PRODUCTS": value],
			envFile: {
				Issue.record("Disabled Vision read configuration"); return config
			},
			run: { _, _ in Issue.record("Disabled Vision ran preparation") })
		#expect(disabled == nil)
	}
}

private enum VisionPreparationError: Error { case sentinel }

@Test func agentVisionPreparationPropagatesFailures() throws {
	let fixture = try VisionFixture()
	defer { try? fixture.remove() }
	for explicit in [false, true] {
		let environment = explicit ? ["AGENT_VISION_PRODUCTS": fixture.products.path] : [:]
		for failure in ["build", "config", "check"] where !explicit || failure != "build" {
			var calls = 0
			#expect(throws: VisionPreparationError.sentinel) {
				try AgentVisionPreparation.resource(
					includeVision: true, root: fixture.root, environment: environment,
					envFile: {
						if failure == "config" { throw VisionPreparationError.sentinel }
						return fixture.root.appendingPathComponent("unread.env")
					},
					run: { _, arguments in
						calls += 1
						if failure == "build" || arguments.first == "check-config" {
							throw VisionPreparationError.sentinel
						}
					})
			}
			#expect(
				calls
					== (failure == "config" ? (explicit ? 0 : 1) : (failure == "build" || explicit ? 1 : 2)))
		}
	}
}
