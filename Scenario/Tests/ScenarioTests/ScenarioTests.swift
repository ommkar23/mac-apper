// @frontmatter:start
// Tests scenario context sharing, selected execution, and teardown after failure.
// @frontmatter:end
import Foundation
import Scenario
import Testing

@MainActor private final class Shared: CollectionContext {
	var log: [String] = []
}

@MainActor private final class Local: CaseContext {
	let shared: Shared
	init(_ shared: Shared) { self.shared = shared }
}

@Test @MainActor func collectionAndSelectedCaseUseTheSameContextsAndTeardown() async throws {
	let shared = Shared()
	let collection = ScenarioCollection(
		"example", context: { shared }, setup: { $0.log.append("collection setup") },
		teardown: { $0.log.append("collection teardown") },
		cases: [
			ScenarioCase(
				"first", context: Local.init, setup: { $0.shared.log.append("case setup") },
				steps: [
					Step("one") { $0.shared.log.append("one") },
					Step("two") { $0.shared.log.append("two") },
				], teardown: { $0.shared.log.append("case teardown") }),
			ScenarioCase(
				"second", context: Local.init,
				steps: [Step("second") { $0.shared.log.append("second") }]),
		])
	let registry = try ScenarioRegistry([collection])
	try await registry.runCase("first")
	#expect(
		shared.log == [
			"collection setup", "case setup", "one", "two", "case teardown", "collection teardown",
		])
}

@Test @MainActor func failureRunsCaseAndCollectionTeardownButSkipsFollowingSteps() async throws {
	let shared = Shared()
	let collection = ScenarioCollection(
		"example", context: { shared }, teardown: { $0.log.append("collection teardown") },
		cases: [
			ScenarioCase(
				"fails", context: Local.init,
				steps: [
					Step("fail") { _ in throw ScenarioFailure.message("failed") },
					Step("skipped") { $0.shared.log.append("skipped") },
				], teardown: { $0.shared.log.append("case teardown") })
		])
	let registry = try ScenarioRegistry([collection])
	await #expect(throws: (any Error).self) {
		try await registry.runCollection("example")
	}
	#expect(shared.log == ["case teardown", "collection teardown"])
}

@Test @MainActor func partiallyFailedSetupStillRunsApplicableTeardown() async throws {
	let shared = Shared()
	let collection = ScenarioCollection(
		"example", context: { shared }, setup: { $0.log.append("collection setup") },
		teardown: { $0.log.append("collection teardown") },
		cases: [
			ScenarioCase(
				"fails", context: Local.init,
				setup: { context in
					context.shared.log.append("case setup")
					throw ScenarioFailure.message("case setup failed")
				}, steps: [Step("skipped") { $0.shared.log.append("unexpected") }],
				teardown: { $0.shared.log.append("case teardown") }),
			ScenarioCase(
				"continues", context: Local.init,
				steps: [Step("runs") { $0.shared.log.append("next case") }]),
		])
	let registry = try ScenarioRegistry([collection])
	await #expect(throws: (any Error).self) {
		try await registry.runCollection("example")
	}
	#expect(
		shared.log == [
			"collection setup", "case setup", "case teardown", "next case", "collection teardown",
		])
}

@Test @MainActor func failedCaseDoesNotPreventNextCase() async throws {
	let shared = Shared()
	let collection = ScenarioCollection(
		"example", context: { shared },
		cases: [
			ScenarioCase(
				"fails", context: Local.init,
				steps: [
					Step("fail") { _ in throw ScenarioFailure.message("failed") }
				]),
			ScenarioCase(
				"continues", context: Local.init,
				steps: [
					Step("continue") { $0.shared.log.append("next case ran") }
				]),
		])
	let registry = try ScenarioRegistry([collection])
	await #expect(throws: (any Error).self) {
		try await registry.runCollection("example")
	}
	#expect(shared.log == ["next case ran"])
}

@Test @MainActor func registryListsCollectionsAndCasesWithoutRunningHooks() throws {
	let shared = Shared()
	let registry = try ScenarioRegistry([
		ScenarioCollection(
			"dev-tools", context: { shared }, setup: { $0.log.append("built") },
			cases: [
				ScenarioCase("dev-tools-plan", context: Local.init, steps: [])
			]),
		ScenarioCollection(
			"web", context: { shared },
			cases: [
				ScenarioCase("web-boundary", context: Local.init, steps: [])
			]),
	])
	#expect(registry.collectionNames == ["dev-tools", "web"])
	#expect(registry.caseNames == ["dev-tools-plan", "web-boundary"])
	#expect(shared.log.isEmpty)
}

@Test func packagedHostRejectsUnsafeNamesBeforeStaging() throws {
	let executable = URL(fileURLWithPath: "/usr/bin/true")
	let plist = URL(fileURLWithPath: "/tmp/unused.plist")
	#expect(throws: (any Error).self) {
		_ = try XPCHostDefinition(
			appName: "../Other.app", clientExecutable: executable, serviceExecutable: executable,
			appPlist: plist, servicePlist: plist)
	}
}

@Test @MainActor func packagedHostRejectsRequestsBeforeSetup() throws {
	let executable = URL(fileURLWithPath: "/usr/bin/true")
	let plist = URL(fileURLWithPath: "/tmp/unused.plist")
	let host = PackagedXPCHost(
		try XPCHostDefinition(
			appName: "ExampleScenario", clientExecutable: executable, serviceExecutable: executable,
			appPlist: plist, servicePlist: plist))
	#expect(throws: (any Error).self) {
		_ = try host.request("search", payload: ["queries": ["example"]])
	}
	try host.remove()
}

@Test func packagedClientRejectsSilentExitOne() {
	#expect(throws: (any Error).self) {
		_ = try XPCClientAdapter().call(
			URL(fileURLWithPath: "/usr/bin/false"), request: Data("{}".utf8))
	}
}

@Test func packagedClientRejectsUnboundedTimeout() {
	#expect(throws: (any Error).self) {
		_ = try XPCClientAdapter().call(
			URL(fileURLWithPath: "/usr/bin/true"), request: Data("{}".utf8),
			timeoutSeconds: 361)
	}
}

@Test func reusableScenarioPackageHasNoMacApperTargets() throws {
	let package = URL(fileURLWithPath: #filePath)
		.deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
	let manifest = try String(
		contentsOf: package.appendingPathComponent("Package.swift"), encoding: .utf8)
	#expect(!manifest.contains(".package(path: \"../Agent\")"))
	#expect(!manifest.contains("AgentXPCScenarioRunner"))
	#expect(!manifest.contains("DirectAgentXPCScenario"))
	#expect(!manifest.contains("SetupProviderScenario"))
	#expect(!manifest.contains("CleanupProviderScenario"))
	#expect(!manifest.contains("ScenarioPlugin"))
	#expect(
		!FileManager.default.fileExists(
			atPath: package.appendingPathComponent("Plugins/ScenarioPlugin").path))
}

@Test @MainActor func rejectsUnknownAndDuplicateCaseNames() async throws {
	let duplicate = ScenarioCollection(
		"example", context: Shared.init,
		cases: [
			ScenarioCase("same", context: Local.init, steps: []),
			ScenarioCase("same", context: Local.init, steps: []),
		])
	#expect(throws: (any Error).self) { _ = try ScenarioRegistry([duplicate]) }
	let registry = try ScenarioRegistry([
		ScenarioCollection("example", context: Shared.init, cases: [])
	])
	await #expect(throws: (any Error).self) { try await registry.runCase("absent") }
	await #expect(throws: (any Error).self) { try await registry.runCollection("absent") }
}
