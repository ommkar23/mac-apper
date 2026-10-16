// @frontmatter:start
// Exercises metadata-only naming and identified rejections through signed generated DevTools XPC with gated cleanup.
// @frontmatter:end
import Foundation
import Scenario
import ScenarioTesting
@_spi(Experimental) import Testing

@MainActor private final class SetAppNameCollection: CollectionContext {}

@MainActor private final class SetAppNameCase: CaseContext {
	typealias Fixture = (id: UUID, url: URL)
	let lifecycle = DevToolsScenarioLifecycle()
	let sessionID = UUID()
	var fixtures: [Fixture] = []
	var foreign: Fixture?
	var originalMetadata: [UUID: [String: Any]] = [:]
	var originalFiles: [UUID: [String: Data]] = [:]

	init(_: SetAppNameCollection) {}

	@discardableResult func addProject() throws -> Fixture {
		let projects = try #require(lifecycle.projects)
		// Registration precedes plist creation, so partial setup remains lifecycle-owned.
		let fixture = try projects.create { url in
			let metadata: [String: Any] = [
				"CFBundleName": "Generated App", "CFBundleDisplayName": "Generated App",
				"CFBundleIdentifier": "com.macapper.fixture.\(url.lastPathComponent)",
				"CFBundleExecutable": "ProductionApp", "CFBundleVersion": "7",
				"CFBundleShortVersionString": "1.2.3",
				"FixtureMetadata": ["enabled": true, "count": 17, "labels": ["keep", "原文"]],
			]
			try PropertyListSerialization.data(
				fromPropertyList: metadata, format: .xml, options: 0
			).write(to: url.appendingPathComponent("Info.plist"))
		}
		fixtures.append(fixture)
		originalMetadata[fixture.id] = try metadata(fixture)
		originalFiles[fixture.id] = try files(fixture)
		return fixture
	}

	func metadata(_ fixture: Fixture) throws -> [String: Any] {
		try #require(
			PropertyListSerialization.propertyList(
				from: Data(contentsOf: fixture.url.appendingPathComponent("Info.plist")), format: nil)
				as? [String: Any])
	}

	func files(_ fixture: Fixture) throws -> [String: Data] {
		let entries = try FileManager.default.contentsOfDirectory(
			at: fixture.url, includingPropertiesForKeys: [.isRegularFileKey, .isSymbolicLinkKey])
		var result: [String: Data] = [:]
		for entry in entries {
			let values = try entry.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey])
			try #require(values.isRegularFile == true && values.isSymbolicLink != true)
			result[entry.lastPathComponent] = try Data(contentsOf: entry)
		}
		return result
	}

	func requireMetadataOnly() throws {
		let home = try #require(lifecycle.home)
		let root = home.directory.appendingPathComponent(".mac-apper")
		let entries = try FileManager.default.contentsOfDirectory(atPath: root.path)
		// No production output, preview archive or other provider-created root may appear.
		try #require(Set(entries) == Set(fixtures.map { $0.url.lastPathComponent }))
		for fixture in fixtures {
			var current = try files(fixture)
			var original = try #require(originalFiles[fixture.id])
			try #require(Set(current.keys) == Set(original.keys))
			current.removeValue(forKey: "Info.plist")
			original.removeValue(forKey: "Info.plist")
			try #require(current == original)
			// Exact root inventory also excludes .build, .mac-apper/DevBuild and staging scratch.
		}
	}

	func rename(_ input: String, expected: String) throws {
		let fixture = try #require(fixtures.first)
		let result = try lifecycle.perform(classifyCompletion: SetAppNameAudit.completed) {
			try $0.request(
				"set_app_name", payload: ["projectRoot": fixture.url.path, "name": input],
				projectID: fixture.id, sessionID: sessionID, timeoutSeconds: 30)
		}
		let returned = try #require(result["name"] as? String)
		// Scalar equality avoids Swift String's canonical-equivalence comparison hiding wire changes.
		try #require(Array(returned.unicodeScalars) == Array(expected.unicodeScalars))
		try #require(result["summary"] as? String == "App name set to \(expected).")
		var wanted = try #require(originalMetadata[fixture.id])
		wanted["CFBundleName"] = expected
		wanted["CFBundleDisplayName"] = expected
		let actual = try metadata(fixture)
		try #require(NSDictionary(dictionary: actual).isEqual(to: wanted))
		for key in ["CFBundleName", "CFBundleDisplayName"] {
			let value = try #require(actual[key] as? String)
			try #require(Array(value.unicodeScalars) == Array(expected.unicodeScalars))
		}
		try requireMetadataOnly()
	}

	func reject(_ name: String, root: URL? = nil) throws {
		let fixture = try #require(fixtures.first)
		var before: [UUID: [String: Data]] = [:]
		for project in fixtures { before[project.id] = try files(project) }
		// Only the expected, identified operationFailed envelope confirms controlled rejection.
		try lifecycle.perform {
			try $0.expectRejected(
				"set_app_name", payload: ["projectRoot": (root ?? fixture.url).path, "name": name],
				error: "operationFailed", projectID: fixture.id, sessionID: sessionID,
				timeoutSeconds: 30)
		}
		for project in fixtures { try #require(files(project) == before[project.id]) }
		try requireMetadataOnly()
	}
}

private enum SetAppNameAudit {
	static func completed(_ result: [String: Any]) throws {
		guard
			Set(result.keys) == ["name", "summary"],
			let name = result["name"] as? String,
			!name.isEmpty,
			let summary = result["summary"] as? String,
			!summary.isEmpty
		else { throw ScenarioFailure.message("naming completion uncertain") }
	}
}

@MainActor private func setAppNameCollection() -> ScenarioCollection {
	ScenarioCollection(
		"dev-tools-set-app-name", context: SetAppNameCollection.init,
		setup: [],
		cases: [
			ScenarioCase(
				"set-app-name-canonical", context: SetAppNameCase.init,
				setup: [
					Step("prepare private signed host") { try $0.lifecycle.setup() },
					Step("register primary project and capture baselines") { _ = try $0.addProject() },
				],
				behaviour: [
					Step("sanitize name and preserve unrelated metadata without packaging") {
						try $0.rename("  Pebble / Counter: .app.APP  ", expected: "Pebble Counter")
					},
					Step("roundtrip the full 64-scalar Unicode wire boundary") {
						let name = String(repeating: "😀", count: 64)
						try $0.rename(name, expected: name)
					},
					Step("preserve accepted non-ASCII control scalar") {
						try $0.rename("A\u{0085}B", expected: "A\u{0085}B")
					},
					Step("preserve decomposed Unicode scalars") {
						let name = String(repeating: "e\u{0301}", count: 32)
						try $0.rename(name, expected: name)
					},
					Step("confirm all assertions passed") { $0.lifecycle.passed = true },
				],
				cleanup: [
					CleanupChain(
						"release only after confirmed request and service cleanup",
						steps: [
							Step("stop owned service and apply fixture retention gates") {
								try $0.lifecycle.teardown()
							}
						])
				]),
			ScenarioCase(
				"set-app-name-rejections", context: SetAppNameCase.init,
				setup: [
					Step("prepare private signed host") { try $0.lifecycle.setup() },
					Step("register primary project and capture baselines") { _ = try $0.addProject() },
					Step("register foreign project") { $0.foreign = try $0.addProject() },
				],
				behaviour: [
					Step("reject invalid canonical names without changing metadata bytes") {
						for name in [".hidden", " / : ", String(repeating: "a", count: 65)] {
							try $0.reject(name)
						}
					},
					Step("reject a foreign registered project root without changing either plist") {
						let foreign = try #require($0.foreign)
						try $0.reject("Foreign Name", root: foreign.url)
					},
					Step("confirm all assertions passed") { $0.lifecycle.passed = true },
				],
				cleanup: [
					CleanupChain(
						"release only after confirmed request and service cleanup",
						steps: [
							Step("stop owned service and apply fixture retention gates") {
								try $0.lifecycle.teardown()
							}
						])
				]),
		], cleanup: [])
}

@Test @MainActor func devToolsSetAppNameScenarios() async throws {
	let registry = try ScenarioRegistry([setAppNameCollection()])
	let observer = ScenarioTestingObserver()
	if let selected = ProcessInfo.processInfo.environment["DEV_TOOLS_SCENARIO_CASE"] {
		let report = try await registry.executeCase(selected, observer: observer)
		try report.requireSuccess()
	} else {
		let report = try await registry.executeCollection("dev-tools-set-app-name", observer: observer)
		try report.requireSuccess()
	}
}

// Discovery-free regressions: these do not allocate hosts or call a service.
@MainActor private final class NamingObservationReport {
	var report: ScenarioReport?
}
@Suite @MainActor struct SetAppNameHelperTests {
	@Test func registrationDoesNotAllocateFixtures() throws {
		let registry = try ScenarioRegistry([setAppNameCollection()])
		#expect(registry.collectionNames == ["dev-tools-set-app-name"])
		#expect(registry.caseNames == ["set-app-name-canonical", "set-app-name-rejections"])
		let first = SetAppNameCase(SetAppNameCollection())
		let second = SetAppNameCase(SetAppNameCollection())
		#expect(first.lifecycle !== second.lifecycle)
		for context in [first, second] {
			#expect(context.lifecycle.home == nil && context.lifecycle.host == nil)
			#expect(context.lifecycle.projects == nil && context.fixtures.isEmpty)
			#expect(context.originalMetadata.isEmpty && context.originalFiles.isEmpty)
		}
	}

	@Test func unknownSelectorsRejectBeforeAcquisition() async throws {
		let registry = try ScenarioRegistry([setAppNameCollection()])
		await #expect(throws: ScenarioFailure.self) {
			try await registry.executeCase("set-app-name-unknown", observer: ScenarioTestingObserver())
		}
		await #expect(throws: ScenarioFailure.self) {
			try await registry.executeCollection(
				"set-app-name-unknown", observer: ScenarioTestingObserver())
		}
	}

	@Test func observedFailureSkipsSuccessMarkerAndRetainsStoppedFixtures() async throws {
		let context = SetAppNameCase(SetAppNameCollection())
		var cleanupRan = false
		let collection = ScenarioCollection(
			"offline-naming-observation", context: SetAppNameCollection.init,
			setup: [],
			cases: [
				ScenarioCase(
					"offline-naming-failure", context: { _ in context },
					setup: [
						Step("prepare private fixtures without starting a host") { context in
							// Stop before host preparation; only private test-owned fixtures exist.
							#expect(throws: (any Error).self) {
								try context.lifecycle.setup(beforeHost: { throw ScenarioFailure.message("offline") }
								)
							}
							_ = try context.addProject()
						}
					],
					behaviour: [
						Step("observe a nonthrowing assertion failure") { _ in
							let actual = "rejected"
							#expect(actual == "accepted", "intentional naming observation fixture")
						},
						Step("confirm all assertions passed") { $0.lifecycle.passed = true },
					],
					cleanup: [
						CleanupChain(
							"release through existing lifecycle gates",
							steps: [
								Step("stop and retain failed fixtures") {
									cleanupRan = true
									try $0.lifecycle.teardown()
								}
							])
					])
			], cleanup: [])
		let registry = try ScenarioRegistry([collection])
		let test = try #require(Test.current)
		// Suppress only the deliberate negative fixture after the inner observer sees it.
		let outer = IssueHandlingTrait.compactMapIssues { issue in
			issue.comments.contains { $0.rawValue == "intentional naming observation fixture" }
				? nil : issue
		}
		let result = NamingObservationReport()
		try await outer.provideScope(for: test, testCase: Test.Case.current) { @MainActor in
			result.report = try await registry.executeCase(
				"offline-naming-failure", observer: ScenarioTestingObserver())
		}
		let report = try #require(result.report)
		#expect(throws: ScenarioExecutionFailure.self) { try report.requireSuccess() }
		#expect(report.bodyProblems.contains { $0.origin == .assertion })
		#expect(report.cleanupProblems.isEmpty)
		#expect(
			report.steps.contains {
				$0.identity.step == "confirm all assertions passed"
					&& $0.skipReason == .priorBehaviourFailure
			})
		#expect(cleanupRan)
		#expect(!context.lifecycle.passed)
		#expect(context.lifecycle.serviceStopped)
		let home = try #require(context.lifecycle.home)
		let project = try #require(context.fixtures.first)
		#expect(FileManager.default.fileExists(atPath: home.directory.path))
		#expect(FileManager.default.fileExists(atPath: project.url.path))
		// Remove only this stopped regression fixture after checking failure retention.
		context.lifecycle.passed = true
		try context.lifecycle.teardown()
		#expect(!FileManager.default.fileExists(atPath: home.directory.path))
	}

	@Test func uncertainCompletionRetainsRequestState() throws {
		for result: [String: Any] in [[:], ["name": "Valid"], ["name": 1, "summary": "done"]] {
			let state = DevToolsScenarioLifecycle.RequestState()
			#expect(throws: (any Error).self) {
				try state.perform(classifyCompletion: SetAppNameAudit.completed, capture: {}) { result }
			}
			#expect(throws: (any Error).self) { try state.requireRequestAllowed() }
			#expect(throws: (any Error).self) { try state.stop {} }
		}
		let state = DevToolsScenarioLifecycle.RequestState()
		_ = try state.perform(classifyCompletion: SetAppNameAudit.completed, capture: {}) {
			["name": "Valid", "summary": "App name set to Valid."] as [String: Any]
		}
		try state.stop {}
		#expect(state.serviceStopped)
	}
}
