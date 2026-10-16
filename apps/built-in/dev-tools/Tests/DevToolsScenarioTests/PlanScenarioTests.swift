// @frontmatter:start
// Declares packaged DevTools XPC plan lifecycle, rejection, and project-isolation scenarios.
// @frontmatter:end
import Foundation
import Scenario
import ScenarioTesting
import Testing

// Collection construction allocates no host, home or project root.
@MainActor final class DevToolsPlanCollection: CollectionContext {}

@MainActor final class DevToolsPlanCase: CaseContext {
	typealias Fixture = (id: UUID, url: URL)
	let collection: DevToolsPlanCollection
	let lifecycle = DevToolsScenarioLifecycle()
	var projects: DevToolsScenarioProjects {
		get throws { try #require(lifecycle.projects) }
	}
	let sessionID = UUID()
	var primary: Fixture?

	init(_ collection: DevToolsPlanCollection) { self.collection = collection }
	func setup() throws {
		try lifecycle.setup()
		primary = try projects.create()
	}

	func request(_ fields: [String: Any], project: Fixture? = nil) throws -> [String: Any] {
		let fixture = try #require(project ?? primary)
		var payload = fields
		payload["projectRoot"] = fixture.url.path
		return try lifecycle.perform {
			try $0.request("plan", payload: payload, projectID: fixture.id, sessionID: sessionID)
		}
	}

	func reject(_ fields: [String: Any], project: Fixture? = nil) throws {
		let fixture = try #require(project ?? primary)
		var payload = fields
		payload["projectRoot"] = fixture.url.path
		try lifecycle.perform {
			try $0.expectRejected(
				"plan", payload: payload, error: "operationFailed",
				projectID: fixture.id, sessionID: sessionID)
		}
	}

	func tasks(_ fields: [String: Any], project: Fixture? = nil) throws -> [[String: Any]] {
		let response = try request(fields, project: project)
		try #require(response["summary"] as? String == "Plan updated.")
		return try #require(response["tasks"] as? [[String: Any]])
	}
}

@MainActor func devToolsPlanCollection() -> ScenarioCollection {
	ScenarioCollection(
		"dev-tools-plan", context: DevToolsPlanCollection.init,
		cases: [
			ScenarioCase(
				"plan-initial-tasks", context: DevToolsPlanCase.init,
				setup: { try $0.setup() },
				steps: [
					Step("create and retrieve a plan with initial tasks") { context in
						let created = try context.tasks([
							"action": "add_plan", "tasks": initialPlanTasks,
						])
						try #require(NSArray(array: created).isEqual(to: initialPlanTasks))
						let retrieved = try context.tasks(["action": "get_tasks"])
						try #require(NSArray(array: retrieved).isEqual(to: initialPlanTasks))
					},
					Step("reject replacement without changing the existing plan") { context in
						try context.reject([
							"action": "add_plan",
							"tasks": [["id": "replacement", "title": "Replacement", "status": "pending"]],
						])
						let retrieved = try context.tasks(["action": "get_tasks"])
						try #require(NSArray(array: retrieved).isEqual(to: initialPlanTasks))
					},
					Step("reject invalid initial tasks without creating a plan") { context in
						let invalidTasks: [[[String: String]]] = [
							[],
							[initialPlanTasks[0], initialPlanTasks[0]],
							[
								["id": "first", "title": "First", "status": "in_progress"],
								["id": "second", "title": "Second", "status": "in_progress"],
							],
							[["id": "first", "title": "  ", "status": "pending"]],
							[["id": "first", "title": "First", "status": "unknown"]],
							[["id": "Bad ID", "title": "First", "status": "pending"]],
						]
						for tasks in invalidTasks {
							let project = try context.projects.create()
							try context.reject(["action": "add_plan", "tasks": tasks], project: project)
							try context.reject(["action": "get_tasks"], project: project)
							let created = try context.tasks(
								[
									"action": "add_plan", "tasks": initialPlanTasks,
								], project: project)
							try #require(NSArray(array: created).isEqual(to: initialPlanTasks))
						}
					},
					Step("reject ids during creation without consuming the plan slot") { context in
						let project = try context.projects.create()
						try context.reject(
							[
								"action": "add_plan", "tasks": initialPlanTasks, "ids": ["design"],
							], project: project)
						let created = try context.tasks(["action": "add_plan"], project: project)
						try #require(created.isEmpty)
					},
					Step("keep seeded tasks isolated from another project's empty plan") { context in
						let other = try context.projects.create()
						let created = try context.tasks(["action": "add_plan"], project: other)
						let isolated = try context.tasks(["action": "get_tasks"], project: other)
						let primary = try context.tasks(["action": "get_tasks"])
						try #require(created.isEmpty && isolated.isEmpty)
						try #require(NSArray(array: primary).isEqual(to: initialPlanTasks))
					},
					Step("confirm all assertions passed") { $0.lifecycle.passed = true },
				], teardown: { try $0.lifecycle.teardown() }),
			ScenarioCase(
				"plan-lifecycle", context: DevToolsPlanCase.init,
				setup: { try $0.setup() },
				steps: [
					Step("create empty plan") { context in
						let tasks = try context.tasks(["action": "add_plan"])
						try #require(tasks.isEmpty)
					},
					Step("add tasks") { context in
						let tasks = try context.tasks([
							"action": "add_tasks",
							"tasks": [
								["id": "design", "title": "Design", "status": "in_progress"],
								["id": "build", "title": "Build", "status": "pending"],
							],
						])
						try #require(tasks.map { $0["id"] as? String } == ["design", "build"])
						let retrieved = try context.tasks(["action": "get_tasks"])
						try #require(retrieved.count == 2)
					},
					Step("append tasks without replacing existing tasks") { context in
						let tasks = try context.tasks([
							"action": "add_tasks",
							"tasks": [["id": "test", "title": "Test", "status": "pending"]],
						])
						try #require(tasks.map { $0["id"] as? String } == ["design", "build", "test"])
						try #require(tasks.map { $0["title"] as? String } == ["Design", "Build", "Test"])
						try #require(
							tasks.map { $0["status"] as? String } == ["in_progress", "pending", "pending"])
					},
					Step("update progress") { context in
						let tasks = try context.tasks([
							"action": "update_tasks",
							"tasks": [
								["id": "design", "title": "Designed", "status": "completed"],
								["id": "build", "title": "Building", "status": "in_progress"],
							],
						])
						try #require(
							tasks.map { $0["status"] as? String } == ["completed", "in_progress", "pending"])
						try #require(tasks.map { $0["title"] as? String } == ["Designed", "Building", "Test"])
					},
					Step("reject a second in-progress task without mutation") { context in
						try context.reject([
							"action": "update_tasks",
							"tasks": [["id": "test", "title": "Testing", "status": "in_progress"]],
						])
						let tasks = try context.tasks(["action": "get_tasks"])
						try #require(tasks.map { $0["id"] as? String } == ["design", "build", "test"])
						try #require(tasks.map { $0["title"] as? String } == ["Designed", "Building", "Test"])
						try #require(
							tasks.map { $0["status"] as? String } == ["completed", "in_progress", "pending"])
					},
					Step("delete multiple tasks and retrieve") { context in
						let tasks = try context.tasks(["action": "delete_tasks", "ids": ["design", "test"]])
						try #require(tasks.count == 1)
						try #require(tasks.first?["id"] as? String == "build")
						let retrieved = try context.tasks(["action": "get_tasks"])
						try #require(retrieved.count == 1)
						try #require(retrieved.first?["id"] as? String == "build")
					},
					Step("delete final task and retrieve empty plan") { context in
						let deleted = try context.tasks(["action": "delete_tasks", "ids": ["build"]])
						let retrieved = try context.tasks(["action": "get_tasks"])
						try #require(deleted.isEmpty)
						try #require(retrieved.isEmpty)
					},
					Step("confirm all assertions passed") { $0.lifecycle.passed = true },
				], teardown: { try $0.lifecycle.teardown() }),
			ScenarioCase(
				"plan-rejections", context: DevToolsPlanCase.init,
				setup: [
					Step("prepare private home, signed host and primary project") { try $0.setup() }
				],
				behaviour: [
					Step("reject missing plan") { try $0.reject(["action": "get_tasks"]) },
					Step("reject duplicate plan") { context in
						_ = try context.tasks(["action": "add_plan"])
						try context.reject(["action": "add_plan"])
					},
					Step("reject duplicate and absent tasks without mutation") { context in
						_ = try context.tasks([
							"action": "add_tasks",
							"tasks": [["id": "first", "title": "First", "status": "pending"]],
						])
						try context.reject([
							"action": "add_tasks",
							"tasks": [["id": "first", "title": "Duplicate", "status": "pending"]],
						])
						try context.reject([
							"action": "update_tasks",
							"tasks": [["id": "missing", "title": "Missing", "status": "pending"]],
						])
						try context.reject(["action": "delete_tasks", "ids": ["missing"]])
						let tasks = try context.tasks(["action": "get_tasks"])
						try #require(tasks.count == 1)
						try #require(tasks.first?["id"] as? String == "first")
						try #require(tasks.first?["title"] as? String == "First")
						try #require(tasks.first?["status"] as? String == "pending")
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
				"plan-project-isolation", context: DevToolsPlanCase.init,
				setup: { try $0.setup() },
				steps: [
					Step("create a plan in the first project") { context in
						_ = try context.tasks(["action": "add_plan"])
						_ = try context.tasks([
							"action": "add_tasks",
							"tasks": [["id": "first", "title": "First", "status": "pending"]],
						])
					},
					Step("keep another project's plan separate") { context in
						let other = try context.projects.create()
						try context.reject(["action": "get_tasks"], project: other)
						let created = try context.tasks(["action": "add_plan"], project: other)
						let primary = try context.tasks(["action": "get_tasks"])
						let isolated = try context.tasks(["action": "get_tasks"], project: other)
						try #require(created.isEmpty)
						try #require(primary.count == 1)
						try #require(isolated.isEmpty)
					},
					Step("confirm all assertions passed") { $0.lifecycle.passed = true },
				], teardown: { try $0.lifecycle.teardown() }),
		])
}

private let initialPlanTasks = [
	["id": "design", "title": "Design", "status": "in_progress"],
	["id": "build", "title": "Build", "status": "pending"],
]

@Test @MainActor func devToolsPlanScenarios() async throws {
	let registry = try ScenarioRegistry([devToolsPlanCollection()])
	let observer = ScenarioTestingObserver()
	if let selected = ProcessInfo.processInfo.environment["DEV_TOOLS_SCENARIO_CASE"] {
		let report = try await registry.executeCase(selected, observer: observer)
		try report.requireSuccess()
	} else {
		let report = try await registry.executeCollection("dev-tools-plan", observer: observer)
		try report.requireSuccess()
	}
}
