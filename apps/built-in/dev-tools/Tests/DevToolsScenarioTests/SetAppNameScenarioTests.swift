// @frontmatter:start
// Exercises metadata-only naming and identified rejections through signed generated DevTools XPC with gated cleanup.
// @frontmatter:end
import Foundation
import Scenario
import Testing

@MainActor private final class SetAppNameCollection: CollectionContext {}

@MainActor private final class SetAppNameCase: CaseContext {
	typealias Fixture = (id: UUID, url: URL)
	let lifecycle = DevToolsScenarioLifecycle()
	let sessionID = UUID()
	var fixtures: [Fixture] = []
	var originalMetadata: [UUID: [String: Any]] = [:]
	var originalFiles: [UUID: [String: Data]] = [:]

	init(_: SetAppNameCollection) {}

	func setup() throws {
		try lifecycle.setup()
		_ = try addProject()
	}

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
		cases: [
			ScenarioCase(
				"set-app-name-canonical", context: SetAppNameCase.init,
				setup: { try $0.setup() },
				steps: [
					Step("sanitize name and preserve unrelated metadata without packaging") {
						try $0.rename("  Pebble / Counter: .app.APP  ", expected: "Pebble Counter")
					},
					Step("roundtrip the full 64-scalar Unicode wire boundary") {
						let name = String(repeating: "😀", count: 64)
						try $0.rename(name, expected: name)
					},
					Step("preserve accepted non-ASCII control and decomposed scalars") {
						try $0.rename("A\u{0085}B", expected: "A\u{0085}B")
						let name = String(repeating: "e\u{0301}", count: 32)
						try $0.rename(name, expected: name)
					},
					Step("confirm all assertions passed") { $0.lifecycle.passed = true },
				], teardown: { try $0.lifecycle.teardown() }),
			ScenarioCase(
				"set-app-name-rejections", context: SetAppNameCase.init,
				setup: { try $0.setup() },
				steps: [
					Step("reject invalid canonical names without changing metadata bytes") {
						for name in [".hidden", " / : ", String(repeating: "a", count: 65)] {
							try $0.reject(name)
						}
					},
					Step("reject a foreign registered project root without changing either plist") {
						let foreign = try $0.addProject()
						try $0.reject("Foreign Name", root: foreign.url)
					},
					Step("confirm all assertions passed") { $0.lifecycle.passed = true },
				], teardown: { try $0.lifecycle.teardown() }),
		])
}

@Test @MainActor func devToolsSetAppNameScenarios() async throws {
	let registry = try ScenarioRegistry([setAppNameCollection()])
	if let selected = ProcessInfo.processInfo.environment["DEV_TOOLS_SCENARIO_CASE"] {
		try await registry.runCase(selected)
	} else {
		try await registry.runCollection("dev-tools-set-app-name")
	}
}

// Discovery-free regressions: these do not allocate hosts or call a service.
@Suite @MainActor struct SetAppNameScenarioHelperTests {
	@Test func registrationDoesNotAllocateFixtures() throws {
		let registry = try ScenarioRegistry([setAppNameCollection()])
		#expect(registry.collectionNames == ["dev-tools-set-app-name"])
		#expect(registry.caseNames == ["set-app-name-canonical", "set-app-name-rejections"])
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
