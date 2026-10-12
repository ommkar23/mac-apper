// @frontmatter:start
// Audits successful Create plan mutations around source implementation and compares the final tasks with client presentation.
// @frontmatter:end
import AgentMacosClientModel
import Foundation
import Testing

func verifyCreatePlan(session: URL, presentedTasks: [AgentTaskRecord]) throws {
	let evidence = try ScenarioToolEvidence(session: session)
	var tasks: [String: String] = [:]
	var finalTasks: [[String: Any]] = []
	var implemented: Set<String> = []
	var completedImplementation: Set<String> = []
	var created = false
	var addedTasks = false
	var updatedTasks = false
	var snapshots: [(finished: Int, tasks: [String: String])] = []
	for call in evidence.calls.sorted(by: { $0.finished < $1.finished }) where call.succeeded {
		let name = call.name
		let arguments = call.arguments
		if name == "write" || name == "edit" {
			let path = arguments["path"] as? String ?? ""
			let source =
				path.hasPrefix("Sources/")
				|| path.hasPrefix(
					session.deletingLastPathComponent()
						.deletingLastPathComponent().deletingLastPathComponent().path + "/Sources/")
			if source && path.hasSuffix(".swift"),
				let atStart = snapshots.last(where: { $0.finished < call.started })?.tasks
			{
				implemented.formUnion(
					atStart.filter { $0.value == "in_progress" && tasks[$0.key] == "in_progress" }.map(\.key))
			}
		}
		guard
			name == "plan"
		else { continue }
		let action = try #require(arguments["action"] as? String)
		let result = try #require(call.typedResult)
		let snapshot = try #require(result["tasks"] as? [[String: Any]])
		try #require(snapshot.count <= 100)
		var next: [String: String] = [:]
		for task in snapshot {
			let taskID = try #require(task["id"] as? String)
			let status = try #require(task["status"] as? String)
			try #require(next[taskID] == nil)
			try #require(["pending", "in_progress", "completed", "blocked"].contains(status))
			next[taskID] = status
			if action == "update_tasks", status == "completed", tasks[taskID] != "completed",
				implemented.contains(taskID)
			{
				completedImplementation.insert(taskID)
			}
		}
		try #require(next.values.filter { $0 == "in_progress" }.count <= 1)
		if action == "add_plan" { created = true }
		if action == "add_plan" || action == "add_tasks", !next.isEmpty { addedTasks = true }
		if action == "update_tasks" { updatedTasks = true }
		tasks = next
		snapshots.append((call.finished, next))
		finalTasks = snapshot
	}
	try #require(created && addedTasks, "Missing successful plan creation and task addition")
	try #require(updatedTasks, "Missing successful update_tasks")
	try #require(
		!completedImplementation.isEmpty,
		"No planned task was in progress during a successful source edit and subsequently completed")
	try #require(!tasks.isEmpty && tasks.values.allSatisfy { $0 == "completed" })
	try #require(presentedTasks.count == finalTasks.count, "Client did not receive the final plan")
	for task in finalTasks {
		let presented = try #require(presentedTasks.first { $0.id == task["id"] as? String })
		try #require(presented.title == task["title"] as? String)
		try #require(presented.status == "completed")
	}
	print(
		"CREATE_PLAN: \(tasks.count) completed tasks; source implementation and client delivery verified"
	)
}
