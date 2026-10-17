// @frontmatter:start
// Declares Create's outer signed-host phases with injectable operations and explicit inner-cleanup retention gates.
// @frontmatter:end
import Foundation
import Scenario
import ScenarioTesting
import Testing

struct CreateHostResult {
	let status: Int32
	let output: String
}

// Closures keep synthetic fixtures independent of real home, credential and hosting operations.
@MainActor struct CreateHostOperations {
	let prepareHome: () throws -> Void
	let prepareHost: (Bool) throws -> Void
	let validateCredential: () throws -> Void
	let invoke: () throws -> CreateHostResult?
	let stopAgent: () throws -> Void
	let stopDevTools: () throws -> Void
	let removeHost: () throws -> Void
	let finishHost: (Bool, Bool, () throws -> Void, () throws -> Void) throws -> Bool
	let removeUnstartedHome: () throws -> Void
}

@MainActor final class CreateHostContext: CollectionContext {
	let testName: String
	let includeVision: Bool
	let keepProject: Bool
	let operations: CreateHostOperations
	private(set) var homePrepared = false
	private(set) var hostPrepared = false
	private(set) var invocationStarted = false
	private(set) var result: CreateHostResult?
	private(set) var passed = false
	var bodySucceeded = false

	init(testName: String, includeVision: Bool, keepProject: Bool, operations: CreateHostOperations) {
		self.testName = testName
		self.includeVision = includeVision
		self.keepProject = keepProject
		self.operations = operations
	}

	func prepareHome() throws {
		try operations.prepareHome()
		homePrepared = true
	}
	func prepareHost() throws {
		try operations.prepareHost(includeVision)
		hostPrepared = true
	}
	func invoke() throws {
		// A thrown or missing runTest result cannot prove that no inner process started.
		invocationStarted = true
		result = try operations.invoke()
		guard
			result != nil
		else { throw ScenarioFailure.message("Missing Create hosted invocation result") }
	}
	func validate() throws {
		guard
			let result,
			result.output.contains("Test \(testName)() started."),
			result.status == 0,
			result.output.contains("Test \(testName)() passed")
		else { throw ScenarioFailure.message("Selected Create test did not start and pass") }
		passed = true
	}
	func cleanup(bodySucceeded: Bool) throws {
		guard
			homePrepared
		else { return }
		guard
			hostPrepared
		else {
			guard
				!invocationStarted
			else { throw ScenarioFailure.message("Uncertain Create host preparation; retain home") }
			try operations.removeUnstartedHome()
			return
		}
		let confirmed =
			!invocationStarted || result?.output.contains(CreateScenarioIsolation.confirmation) == true
		guard
			confirmed
		else {
			throw ScenarioFailure.message("Create inner cleanup unconfirmed; retain signed host/home")
		}
		_ = try operations.finishHost(
			confirmed, passed && bodySucceeded && !keepProject,
			{
				try self.operations.stopAgent()
				try self.operations.stopDevTools()
			}, operations.removeHost)
	}
}

@MainActor func createHostCollection(_ context: CreateHostContext) -> ScenarioCollection {
	ScenarioCollection(
		"agent-create-host", context: { context },
		setup: [
			Step("prepare and own isolated Create home") { try $0.prepareHome() },
			Step("prepare and own signed Agent and DevTools host") { try $0.prepareHost() },
			Step("validate staged credential lifetime") { try $0.operations.validateCredential() },
		],
		cases: [
			ScenarioCase(
				"create-host-invocation", context: { _ in CreateHostInvocation() },
				behaviour: [
					Step("execute selected hosted Create case") { _ in try context.invoke() },
					Step("validate selected test started and passed") { _ in try context.validate() },
				])
		],
		cleanup: [
			CleanupChain(
				"finish Create host under inner ownership gates",
				eligibility: { local, state in
					local.bodySucceeded = state.report.bodyProblems.isEmpty && !state.report.cancelled
					return .run
				},
				steps: [
					Step("confirm inner cleanup, reap Agent then DevTools, scrub and retain or remove") {
						try $0.cleanup(bodySucceeded: $0.bodySucceeded)
					}
				])
		])
}

@MainActor private final class CreateHostInvocation: CaseContext {}

@MainActor private final class CreatePreparedHost {
	var home: IsolatedScenarioHome?
	var host: PackagedTestHost?

	func operations(testName: String, includeVision: Bool) -> CreateHostOperations {
		CreateHostOperations(
			prepareHome: { self.home = try CreateScenarioIsolation.prepareHome() },
			prepareHost: { vision in
				let home = try #require(self.home)
				self.host = try AgentChatScenarioInputs.prepareHost(
					includeDevTools: true, includeVision: vision, isolatedHome: home)
			},
			validateCredential: {
				let home = try #require(self.home)
				let host = try #require(self.host)
				let app = try #require(host.app)
				print("CREATE_ISOLATED_HOST_HOME: host=\(app.path) home=\(home.directory.path)")
				_ = try CreateScenarioIsolation.credentialSnapshot(
					try #require(
						(JSONSerialization.jsonObject(
							with: Data(contentsOf: home.directory.appendingPathComponent(".pi/agent/auth.json")))
							as? [String: [String: Any]])?["openai-codex"]))
			},
			invoke: {
				let home = try #require(self.home), host = try #require(self.host),
					app = try #require(host.app)
				var environment = [
					"AGENT_SCENARIO_TEST_HOST": "1", "AGENT_CREATE_HOME": home.directory.path,
					"HOME": home.directory.path, "CFFIXED_USER_HOME": home.directory.path,
				]
				if includeVision {
					environment["AGENT_SCENARIO_VISION_CLI"] =
						app.appendingPathComponent("Contents/Resources/VisionCLI/vision-cli").path
					environment["AGENT_VISION_ENV_FILE"] = try counterVisionEnvFile().path
				}
				let result = try host.runTest(
					filter: "^AgentScenarioTests\\.\(testName)", environment: environment,
					timeoutSeconds: 1320)
				print(result.output)
				return CreateHostResult(status: result.status, output: result.output)
			},
			stopAgent: {
				try stopScaffoldService(
					self.host?.app, relative: "AgentXPCService.xpc/Contents/MacOS/AgentApplication")
			},
			stopDevTools: {
				try stopScaffoldService(
					self.host?.app?.appendingPathComponent("Contents/Applications/DevTools.app"),
					relative: "DevToolsApplication.xpc/Contents/MacOS/DevToolsApplication")
			},
			removeHost: { try self.host?.remove() },
			finishHost: { confirmed, remove, stop, removeHost in
				let home = try #require(self.home)
				do {
					let removed = try home.finishHost(
						cleanupConfirmed: confirmed, removeFixtures: remove, stopServices: stop,
						removeHost: removeHost)
					if removed {
						print("CREATE_HOST_HOME_CLEANUP: removed after confirmed process reaping")
					} else {
						self.reportRetained(home)
					}
					return removed
				} catch { self.reportRetained(home); throw error }
			},
			removeUnstartedHome: { try self.home?.remove(cleanupConfirmed: true) })
	}
	private func reportRetained(_ home: IsolatedScenarioHome) {
		print(
			"CREATE_RETAINED_HOST_HOME: host=\(host?.app?.path ?? "unavailable") home=\(home.directory.path)"
		)
	}
}

@MainActor func runCreateScenario(
	caseName: String, testName: String, includeVision: Bool,
	makeCollection: @MainActor () -> ScenarioCollection
) async throws {
	if ProcessInfo.processInfo.environment["AGENT_SCENARIO_TEST_HOST"] == "1" {
		_ = try ChatModelCases.serviceIdentifier()
		let registry = try ScenarioRegistry([makeCollection()])
		try await registry.executeCase(caseName, observer: ScenarioTestingObserver()).requireSuccess()
	} else {
		let prepared = CreatePreparedHost()
		let context = CreateHostContext(
			testName: testName, includeVision: includeVision,
			keepProject: ProcessInfo.processInfo.environment["AGENT_CREATE_KEEP_PROJECT"] == "1",
			operations: prepared.operations(testName: testName, includeVision: includeVision))
		let registry = try ScenarioRegistry([createHostCollection(context)])
		try await registry.executeCollection("agent-create-host", observer: ScenarioTestingObserver())
			.requireSuccess()
	}
}
