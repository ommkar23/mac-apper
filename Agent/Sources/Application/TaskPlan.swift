// @frontmatter:start
// Decodes bounded task plans with unique IDs and valid task statuses.
// @frontmatter:end
import Foundation

public enum TaskStatus: String, Codable, Sendable {
	case pending
	case inProgress = "in_progress"
	case completed
	case blocked
}

public struct PlanTask: Codable, Equatable, Sendable, Identifiable {
	public let id: String
	public let title: String
	public let status: TaskStatus

	public init(id: String, title: String, status: TaskStatus) {
		self.id = id
		self.title = title
		self.status = status
	}
}

public struct TaskPlan: Codable, Equatable, Sendable {
	public let tasks: [PlanTask]

	public static func decode(_ data: Data) throws -> TaskPlan {
		guard
			data.count <= 32_768,
			let object = try JSONSerialization.jsonObject(with: data) as? [String: Any],
			Set(object.keys) == ["tasks"],
			let rows = object["tasks"] as? [[String: Any]],
			rows.count <= 100,
			rows.allSatisfy({ Set($0.keys) == ["id", "title", "status"] })
		else { throw PlanError.invalidPayload }
		let plan = try JSONDecoder().decode(Self.self, from: data)
		guard
			Set(plan.tasks.map(\.id)).count == plan.tasks.count,
			plan.tasks.filter({ $0.status == .inProgress }).count <= 1,
			plan.tasks.allSatisfy({ task in
				!task.id.isEmpty && task.id.utf8.count <= 64
					&& task.id.utf8.allSatisfy {
						(97...122).contains($0) || (48...57).contains($0) || $0 == 45
					} && !task.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
					&& task.title.utf8.count <= 256
			})
		else { throw PlanError.invalidPayload }
		return plan
	}
}

public enum PlanError: Error, Sendable {
	case invalidPayload
}
