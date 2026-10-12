// @frontmatter:start
// Validates and applies project-scoped plan mutations using generated OpenXPC task records.
// @frontmatter:end
import Foundation

actor PlanStore {
	private var plans: [String: [PlanTask]] = [:]

	func execute(_ request: PlanRequest, projectID: String) throws -> PlanResult {
		var tasks = plans[projectID]
		switch request.action {
		case "get_tasks":
			guard
				request.tasks == nil,
				request.ids == nil,
				tasks != nil
			else { throw PlanMutationError.invalidRequest }
		case "add_plan":
			guard
				request.ids == nil,
				tasks == nil
			else { throw PlanMutationError.invalidRequest }
			let initial = request.tasks ?? []
			guard
				request.tasks == nil || !initial.isEmpty,
				initial.count <= 100,
				Set(initial.map(\.id)).count == initial.count,
				initial.allSatisfy(Self.valid),
				initial.filter({ $0.status == "in_progress" }).count <= 1
			else { throw PlanMutationError.invalidRequest }
			tasks = initial
		case "add_tasks", "update_tasks":
			guard
				let items = request.tasks,
				!items.isEmpty,
				request.ids == nil,
				var current = tasks,
				Set(items.map(\.id)).count == items.count,
				items.allSatisfy(Self.valid)
			else { throw PlanMutationError.invalidRequest }
			for item in items {
				if let index = current.firstIndex(where: { $0.id == item.id }) {
					guard
						request.action == "update_tasks"
					else { throw PlanMutationError.invalidRequest }
					current[index] = item
				} else {
					guard
						request.action == "add_tasks"
					else { throw PlanMutationError.invalidRequest }
					current.append(item)
				}
			}
			guard
				current.count <= 100,
				current.filter({ $0.status == "in_progress" }).count <= 1
			else { throw PlanMutationError.invalidRequest }
			tasks = current
		case "delete_tasks":
			guard
				let ids = request.ids,
				!ids.isEmpty,
				request.tasks == nil,
				var current = tasks,
				Set(ids).count == ids.count,
				ids.allSatisfy(Self.validID),
				ids.allSatisfy({ id in current.contains(where: { $0.id == id }) })
			else { throw PlanMutationError.invalidRequest }
			current.removeAll { ids.contains($0.id) }
			tasks = current
		default: throw PlanMutationError.invalidRequest
		}
		guard
			let tasks
		else { throw PlanMutationError.invalidRequest }
		let response = try PlanResult(summary: "Plan updated.", tasks: tasks)
		plans[projectID] = tasks
		return response
	}

	private static func valid(_ item: PlanTask) -> Bool {
		validID(item.id) && !item.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
			&& item.title.utf8.count <= 256
			&& ["pending", "in_progress", "completed", "blocked"].contains(item.status)
	}

	private static func validID(_ id: String) -> Bool {
		!id.isEmpty && id.utf8.count <= 64
			&& id.utf8.allSatisfy {
				(97...122).contains($0) || (48...57).contains($0) || $0 == 45
			}
	}
}

private enum PlanMutationError: Error { case invalidRequest }
