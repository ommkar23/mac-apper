// @frontmatter:start
// Verifies packaged DevTools testing through the generated client with real package passes, assertion/compiler failures, recovery, and scope rejection.
// @frontmatter:end
import Foundation
import Scenario
import ScenarioTesting
import Testing

@MainActor final class DevToolsTestCollection: CollectionContext {
	let lifecycle = DevToolsScenarioLifecycle()
}

@MainActor final class DevToolsTestCase: CaseContext {
	let collection: DevToolsTestCollection
	var project: (id: UUID, url: URL)?
	let sessionID = UUID()

	init(_ collection: DevToolsTestCollection) { self.collection = collection }

	func registerTargets() throws {
		let projects = try #require(collection.lifecycle.projects, "Test project registry unavailable")
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
	}

	func writeModel() throws {
		let root = try #require(project?.url)
		try
			"#if compiler(<6.4)\n#error(\"Swift 6.4 is required\")\n#endif\npublic struct Counter { public let value = 0; public init() {} }\n"
			.write(
				to: root.appendingPathComponent("Sources/AppModel/Counter.swift"), atomically: true,
				encoding: .utf8)
	}

	func writeTests() throws {
		let root = try #require(project?.url)
		try """
		import Foundation
		import Testing
		import AppModel
		@Test func counterInitialValue() throws {
		    #expect(Counter().value == 0)
		    let environment = ProcessInfo.processInfo.environment
		    try #require(environment["HOME"] == \(String(reflecting: try #require(collection.lifecycle.home?.directory.path))))
		    try #require(environment["CFFIXED_USER_HOME"] == environment["HOME"])
		    try #require(environment["TMPDIR"] == \(String(reflecting: try ProjectTemporaryDirectory.root().path + "/")))
		    for name in ["swift", "swiftc"] {
		        try #require(FileManager.default.isExecutableFile(atPath:
		            environment["HOME"]! + "/Library/Developer/Toolchains/swift-6.4.0-RELEASE.xctoolchain/usr/bin/" + name))
		    }
		}
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
		let result = try collection.lifecycle.perform {
			try $0.request(
				"test", payload: ["projectRoot": fixture.url.path], projectID: fixture.id,
				sessionID: sessionID)
		}
		try #require(result["status"] as? String == status)
		let exitCode = try #require(result["exitCode"] as? Int)
		try #require(status == "passed" ? exitCode == 0 : exitCode != 0)
		let diagnostics = try #require(result["diagnostics"] as? String)
		try #require(diagnostics.utf8.count <= 4_096)
		if status == "passed" {
			try #require(diagnostics.contains("counterInitialValue"))
			print("DEVTOOLS_TEST_PRIVATE_HOME_COMPILER_CONFIRMED")
		}
		if let marker {
			try #require(diagnostics.contains(marker), "Missing diagnostic: \(diagnostics)")
		}
		try #require(
			try FileManager.default.contentsOfDirectory(
				atPath: fixture.url.appendingPathComponent(".mac-apper/TestBuild").path
			).isEmpty)
		try #require(
			!FileManager.default.fileExists(atPath: fixture.url.appendingPathComponent(".build").path))
		try #require(
			try Data(contentsOf: fixture.url.appendingPathComponent("Package.swift")) == manifest)
		try #require(
			try Data(contentsOf: fixture.url.appendingPathComponent("Sources/AppModel/Counter.swift"))
				== model)
		try #require(
			try Data(
				contentsOf: fixture.url.appendingPathComponent("Tests/SecondaryTests/SecondaryChecks.swift")
			) == tests)
	}
}

@MainActor func devToolsTestCollection(
	context: @escaping @MainActor () throws -> DevToolsTestCollection = DevToolsTestCollection.init,
	setup: [Step<DevToolsTestCollection>] = [
		Step("prepare private signed generated-client host") { try $0.lifecycle.setup() }
	]
) -> ScenarioCollection {
	ScenarioCollection(
		"dev-tools-test", context: context,
		setup: setup,
		cases: [
			ScenarioCase(
				"test-package", context: DevToolsTestCase.init,
				setup: [
					Step("register project and package targets") { try $0.registerTargets() },
					Step("write compiler-guarded model") { try $0.writeModel() },
					Step("write private-home compiler assertions and passing tests") { try $0.writeTests() },
				],
				behaviour: [
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
						try context.collection.lifecycle.perform {
							try $0.expectRejected(
								"test", payload: ["projectRoot": fixture.url.deletingLastPathComponent().path],
								error: "operationFailed", projectID: fixture.id, sessionID: context.sessionID)
						}
					},
					Step("mark successful completion") { $0.collection.lifecycle.passed = true },
				])
		],
		cleanup: [
			CleanupChain(
				"collection-owned Test lifecycle",
				steps: [
					Step("teardown private host and registered projects") { try $0.lifecycle.teardown() }
				])
		])
}

@Test @MainActor func devToolsTestScenarios() async throws {
	let registry = try ScenarioRegistry([devToolsTestCollection()])
	let report: ScenarioReport
	if let selected = ProcessInfo.processInfo.environment["DEV_TOOLS_SCENARIO_CASE"] {
		report = try await registry.executeCase(selected, observer: ScenarioTestingObserver())
	} else {
		report = try await registry.executeCollection(
			"dev-tools-test", observer: ScenarioTestingObserver())
	}
	try report.requireSuccess()
}
