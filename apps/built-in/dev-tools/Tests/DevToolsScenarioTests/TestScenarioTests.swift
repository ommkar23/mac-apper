// @frontmatter:start
// Verifies packaged DevTools testing through the generated client with real package passes, assertion/compiler failures, recovery, and scope rejection.
// @frontmatter:end
import Foundation
import Scenario
import Testing

@MainActor private final class DevToolsTestCollection: CollectionContext {
	let host: PackagedXPCHost
	init() throws { host = try DevToolsScenarioInputs.host() }
}

@MainActor private final class DevToolsTestCase: CaseContext {
	let collection: DevToolsTestCollection
	let projects = DevToolsScenarioProjects()
	var project: (id: UUID, url: URL)?
	let sessionID = UUID()

	init(_ collection: DevToolsTestCollection) { self.collection = collection }

	func setup() throws {
		project = try projects.create()
		let root = try #require(project?.url)
		try """
		// swift-tools-version: 6.0
		import PackageDescription
		let package = Package(name: "TestFixture", platforms: [.macOS(.v14)],
		dependencies: [.package(url: "https://github.com/swiftlang/swift-testing.git", exact: "6.2.3")], targets: [
		    .target(name: "AppModel"),
		    .testTarget(name: "AppModelTests", dependencies: ["AppModel", .product(name: "Testing", package: "swift-testing")]),
		    .testTarget(name: "SecondaryTests", dependencies: [.product(name: "Testing", package: "swift-testing")])
		])
		""".write(to: root.appendingPathComponent("Package.swift"), atomically: true, encoding: .utf8)
		for path in ["Sources/AppModel", "Tests/AppModelTests", "Tests/SecondaryTests"] {
			try FileManager.default.createDirectory(
				at: root.appendingPathComponent(path), withIntermediateDirectories: true)
		}
		try
			"#if compiler(<6.4)\n#error(\"Swift 6.4 is required\")\n#endif\npublic struct Counter { public let value = 0; public init() {} }\n"
			.write(
				to: root.appendingPathComponent("Sources/AppModel/Counter.swift"), atomically: true,
				encoding: .utf8)
		try """
		import Testing
		import AppModel
		@Test func counterInitialValue() { #expect(Counter().value == 0) }
		""".write(
			to: root.appendingPathComponent("Tests/AppModelTests/CounterChecks.swift"), atomically: true,
			encoding: .utf8)
		try secondary("#expect(true)")
	}

	func secondary(_ body: String) throws {
		let root = try #require(project?.url)
		try """
		import Testing
		@Test func secondaryTarget() {
		    \(body)
		}
		""".write(
			to: root.appendingPathComponent("Tests/SecondaryTests/SecondaryChecks.swift"),
			atomically: true, encoding: .utf8)
	}

	func check(status: String, marker: String? = nil) throws {
		let fixture = try #require(project)
		let manifest = try Data(contentsOf: fixture.url.appendingPathComponent("Package.swift"))
		let model = try Data(
			contentsOf: fixture.url.appendingPathComponent("Sources/AppModel/Counter.swift"))
		let tests = try Data(
			contentsOf: fixture.url.appendingPathComponent("Tests/SecondaryTests/SecondaryChecks.swift"))
		let result = try collection.host.request(
			"test", payload: ["projectRoot": fixture.url.path], projectID: fixture.id,
			sessionID: sessionID)
		#expect(result["status"] as? String == status)
		let exitCode = try #require(result["exitCode"] as? Int)
		#expect(status == "passed" ? exitCode == 0 : exitCode != 0)
		let diagnostics = try #require(result["diagnostics"] as? String)
		#expect(diagnostics.utf8.count <= 4_096)
		if let marker { #expect(diagnostics.contains(marker), "Missing diagnostic: \(diagnostics)") }
		#expect(
			try FileManager.default.contentsOfDirectory(
				atPath: fixture.url.appendingPathComponent(".mac-apper/TestBuild").path
			).isEmpty)
		#expect(
			!FileManager.default.fileExists(atPath: fixture.url.appendingPathComponent(".build").path))
		#expect(try Data(contentsOf: fixture.url.appendingPathComponent("Package.swift")) == manifest)
		#expect(
			try Data(contentsOf: fixture.url.appendingPathComponent("Sources/AppModel/Counter.swift"))
				== model)
		#expect(
			try Data(
				contentsOf: fixture.url.appendingPathComponent("Tests/SecondaryTests/SecondaryChecks.swift")
			) == tests)
	}
}

@Test @MainActor func devToolsTestScenarios() async throws {
	let collection = ScenarioCollection(
		"dev-tools-test", context: DevToolsTestCollection.init,
		setup: { try $0.host.prepare() }, teardown: { try $0.host.remove() },
		cases: [
			ScenarioCase(
				"test-package", context: DevToolsTestCase.init,
				setup: { try $0.setup() },
				steps: [
					Step("pass real tests in both package test targets") {
						try $0.check(status: "passed", marker: "secondaryTarget")
					},
					Step("report assertion failures in the second target") { context in
						try context.secondary("#expect(false, \"EXPECTED_ASSERTION_FAILURE\")")
						try context.check(status: "failed", marker: "EXPECTED_ASSERTION_FAILURE")
					},
					Step("report test compilation failure") { context in
						try context.secondary("#error(\"EXPECTED_COMPILATION_FAILURE\")")
						try context.check(status: "failed", marker: "EXPECTED_COMPILATION_FAILURE")
					},
					Step("recover after repairing tests") { context in
						try context.secondary("#expect(true)")
						try context.check(status: "passed", marker: "secondaryTarget")
					},
					Step("reject foreign project scope") { context in
						let fixture = try #require(context.project)
						try context.collection.host.expectRejected(
							"test", payload: ["projectRoot": fixture.url.deletingLastPathComponent().path],
							error: "operationFailed", projectID: fixture.id, sessionID: context.sessionID)
					},
				], teardown: { try $0.projects.remove() })
		])
	let registry = try ScenarioRegistry([collection])
	if let selected = ProcessInfo.processInfo.environment["DEV_TOOLS_SCENARIO_CASE"] {
		try await registry.runCase(selected)
	} else {
		try await registry.runCollection("dev-tools-test")
	}
}
