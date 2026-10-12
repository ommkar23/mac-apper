// @frontmatter:start
// Tests project-scoped plan creation, validation, mutation, and retrieval.
// @frontmatter:end
import Foundation
import Testing
@testable import DevToolsApplication

@Test func addPlanAcceptsInitialTasksAndDoesNotReplaceAnExistingPlan() async throws {
	let store = PlanStore()
	let initial = try [
		PlanTask(id: "design", title: "Design", status: "in_progress"),
		PlanTask(id: "build", title: "Build", status: "pending"),
	]
	let request = try PlanRequest(
		projectRoot: "/project", action: "add_plan", tasks: initial, ids: nil)
	let created = try await store.execute(request, projectID: "first")
	#expect(created.tasks == initial)
	let retrieved = try await store.execute(
		PlanRequest(projectRoot: "/project", action: "get_tasks", tasks: nil, ids: nil),
		projectID: "first")
	#expect(retrieved.tasks == initial)
	await #expect(throws: (any Error).self) {
		_ = try await store.execute(request, projectID: "first")
	}
	let unchanged = try await store.execute(
		PlanRequest(projectRoot: "/project", action: "get_tasks", tasks: nil, ids: nil),
		projectID: "first")
	#expect(unchanged.tasks == initial)
	let other = try await store.execute(
		PlanRequest(projectRoot: "/project", action: "add_plan", tasks: nil, ids: nil),
		projectID: "other")
	#expect(other.tasks.isEmpty)
}

@Test func addPlanRejectsInvalidInitialTasksWithoutCreatingAPlan() async throws {
	let valid = try PlanTask(id: "build", title: "Build", status: "pending")
	let active = try PlanTask(id: "design", title: "Design", status: "in_progress")
	let invalidLists = try [
		[], [valid, valid],
		[PlanTask(id: "Bad ID", title: "Build", status: "pending")],
		[PlanTask(id: "build", title: "  ", status: "pending")],
		[PlanTask(id: "build", title: "Build", status: "unknown")],
		[active, PlanTask(id: "build", title: "Build", status: "in_progress")],
	]
	for items in invalidLists {
		let store = PlanStore()
		await #expect(throws: (any Error).self) {
			_ = try await store.execute(
				PlanRequest(projectRoot: "/project", action: "add_plan", tasks: items, ids: nil),
				projectID: "first")
		}
		// An invalid creation must not consume the project's one plan slot.
		let created = try await store.execute(
			PlanRequest(projectRoot: "/project", action: "add_plan", tasks: [valid], ids: nil),
			projectID: "first")
		#expect(created.tasks == [valid])
	}
	let store = PlanStore()
	await #expect(throws: (any Error).self) {
		_ = try await store.execute(
			PlanRequest(projectRoot: "/project", action: "add_plan", tasks: [valid], ids: ["build"]),
			projectID: "first")
	}
	let created = try await store.execute(
		PlanRequest(projectRoot: "/project", action: "add_plan", tasks: [valid], ids: nil),
		projectID: "first")
	#expect(created.tasks == [valid])
}

@Test func addPlanEnforcesTheTaskCountBoundary() async throws {
	let store = PlanStore()
	let tasks = try (0..<100).map {
		try PlanTask(id: "task-\($0)", title: "Task \($0)", status: "pending")
	}
	let created = try await store.execute(
		PlanRequest(projectRoot: "/project", action: "add_plan", tasks: tasks, ids: nil),
		projectID: "first")
	#expect(created.tasks == tasks)
	let extra = try PlanTask(id: "extra", title: "Extra", status: "pending")
	#expect(throws: (any Error).self) {
		_ = try PlanRequest(
			projectRoot: "/project", action: "add_plan", tasks: tasks + [extra], ids: nil)
	}
}

@Test func generatedPlanValuesStayProjectScoped() async throws {
	let store = PlanStore()
	let project = UUID().uuidString.lowercased()
	let other = UUID().uuidString.lowercased()
	let root = "/Users/example/.mac-apper/\(project)"
	let created = try await store.execute(
		PlanRequest(projectRoot: root, action: "add_plan", tasks: nil, ids: nil),
		projectID: project)
	#expect(created.tasks.isEmpty)
	let task = try PlanTask(id: "build", title: "Build app", status: "pending")
	let updated = try await store.execute(
		PlanRequest(projectRoot: root, action: "add_tasks", tasks: [task], ids: nil),
		projectID: project)
	#expect(updated.tasks.map(\.id) == ["build"])
	await #expect(throws: (any Error).self) {
		_ = try await store.execute(
			PlanRequest(projectRoot: root, action: "add_tasks", tasks: [task], ids: nil),
			projectID: project)
	}
	let changed = try PlanTask(id: "build", title: "Build successfully", status: "completed")
	let tasks = try await store.execute(
		PlanRequest(projectRoot: root, action: "update_tasks", tasks: [changed], ids: nil),
		projectID: project)
	#expect(tasks.tasks.map(\.status) == ["completed"])
	await #expect(throws: (any Error).self) {
		_ = try await store.execute(
			PlanRequest(projectRoot: root, action: "add_tasks", tasks: [changed, changed], ids: nil),
			projectID: project)
	}
	await #expect(throws: (any Error).self) {
		_ = try await store.execute(
			PlanRequest(projectRoot: root, action: "get_tasks", tasks: nil, ids: nil),
			projectID: other)
	}
	let deleted = try await store.execute(
		PlanRequest(projectRoot: root, action: "delete_tasks", tasks: nil, ids: ["build"]),
		projectID: project)
	#expect(deleted.tasks.isEmpty)
	let empty = try await store.execute(
		PlanRequest(projectRoot: root, action: "get_tasks", tasks: nil, ids: nil),
		projectID: project)
	#expect(empty.tasks.isEmpty)
}
