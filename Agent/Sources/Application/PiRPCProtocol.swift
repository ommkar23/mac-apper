// @frontmatter:start
// Encodes service-owned Pi RPC commands and parses bounded LF-delimited Pi output.
// @frontmatter:end
import Foundation

public enum AgentPaths {
	public static func projectsRoot(home: URL = FileManager.default.homeDirectoryForCurrentUser)
		-> URL
	{
		home.appendingPathComponent(".mac-apper", isDirectory: true)
	}

}

public enum SessionError: Error, Equatable, Sendable {
	case invalidRequest
	case invalidEvent
	case streamLimit
}

public enum PiRPCCommand: Sendable {
	case prompt(id: String, message: String)
	case abort(id: String)

	public func encodedLine() throws -> Data {
		let object: [String: Any]
		switch self {
		case .prompt(let id, let message):
			guard
				!id.isEmpty,
				!message.isEmpty,
				message.utf8.count <= 65_536
			else { throw PiRPCError.invalidRecord }
			object = ["id": id, "type": "prompt", "message": message, "streamingBehavior": "steer"]
		case .abort(let id):
			guard
				!id.isEmpty
			else { throw PiRPCError.invalidRecord }
			object = ["id": id, "type": "abort"]
		}
		var data = try JSONSerialization.data(withJSONObject: object, options: [.sortedKeys])
		data.append(10)
		return data
	}
}

public struct PiRPCParser: Sendable {
	private var buffer = Data()
	private let maximumRecordBytes: Int

	// Allows one 2 MiB PNG encoded as base64 plus metadata; image content is not published to the journal.
	public init(maximumRecordBytes: Int = 4_194_304) {
		self.maximumRecordBytes = maximumRecordBytes
	}

	public mutating func feed(_ bytes: Data) throws -> [PiRPCEvent] {
		guard
			buffer.count + bytes.count <= maximumRecordBytes || bytes.contains(10)
		else { throw PiRPCError.recordTooLarge }
		buffer.append(bytes)
		var events: [PiRPCEvent] = []
		while let newline = buffer.firstIndex(of: 10) {
			let record = Data(buffer[..<newline])
			buffer.removeSubrange(...newline)
			guard
				record.count <= maximumRecordBytes
			else { throw PiRPCError.recordTooLarge }
			if record.isEmpty { continue }
			events.append(contentsOf: try decode(record))
		}
		guard
			buffer.count <= maximumRecordBytes
		else { throw PiRPCError.recordTooLarge }
		return events
	}

	public mutating func finish() throws -> [PiRPCEvent] {
		guard
			buffer.isEmpty
		else { throw PiRPCError.incompleteRecord }
		return []
	}

	private func decode(_ data: Data) throws -> [PiRPCEvent] {
		guard
			let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
			let type = object["type"] as? String
		else { throw PiRPCError.invalidRecord }
		switch type {
		case "response":
			guard
				let command = object["command"] as? String,
				let success = object["success"] as? Bool
			else { throw PiRPCError.invalidRecord }
			return [
				.response(
					id: object["id"] as? String, command: command, success: success,
					error: object["error"] as? String)
			]
		case "message_update":
			guard
				let update = object["assistantMessageEvent"] as? [String: Any],
				let updateType = update["type"] as? String
			else { throw PiRPCError.invalidRecord }
			if updateType == "text_delta", let delta = update["delta"] as? String {
				return [.textDelta(delta)]
			}
			return []
		case "tool_execution_start":
			guard
				let id = object["toolCallId"] as? String,
				let name = object["toolName"] as? String,
				let arguments = object["args"] as? [String: Any],
				let argumentsData = try? JSONSerialization.data(
					withJSONObject: arguments, options: [.sortedKeys]),
				let argumentsJSON = String(data: argumentsData, encoding: .utf8)
			else { throw PiRPCError.invalidRecord }
			return [.toolStarted(id: id, name: name, argumentsJSON: argumentsJSON)]
		case "tool_execution_update":
			guard
				let id = object["toolCallId"] as? String,
				let name = object["toolName"] as? String
			else { throw PiRPCError.invalidRecord }
			return [.toolUpdated(id: id, name: name, text: resultText(object["partialResult"]))]
		case "tool_execution_end":
			guard
				let id = object["toolCallId"] as? String,
				let name = object["toolName"] as? String,
				let isError = object["isError"] as? Bool
			else { throw PiRPCError.invalidRecord }
			if name == "plan" && !isError,
				let result = object["result"] as? [String: Any],
				let details = result["details"] as? [String: Any],
				let plan = Self.taskPlan(from: details)
			{
				return [
					.tasksUpdated(plan.tasks),
					.toolFinished(id: id, name: name, text: resultText(object["result"]), isError: false),
				]
			}
			return [
				.toolFinished(id: id, name: name, text: resultText(object["result"]), isError: isError)
			]
		case "extension_error":
			return [.extensionError((object["error"] as? String) ?? "Mac Apper extension failed.")]
		case "extension_ui_request":
			if object["method"] as? String == "notify", let message = object["message"] as? String {
				return [.notification(message)]
			}
			return []
		// agent_end closes a low-level loop; Pi may still retry, compact or continue.
		// Only the session-level event marks completion of Pi-owned recovery.
		case "agent_settled": return [.settled]
		default: return []
		}
	}

	private static func taskPlan(from details: [String: Any]) -> TaskPlan? {
		let tasks: Any?
		if let result = details["result"] as? [String: Any] {
			tasks = result["tasks"]
		} else {
			let response = details["response"] as? [String: Any]
			let result = response?["result"] as? [String: Any]
			let metadata = result?["metadata"] as? [String: Any]
			let plan = metadata?["plan"] as? [String: Any]
			tasks = plan?["tasks"]
		}
		guard
			let tasks,
			JSONSerialization.isValidJSONObject(["tasks": tasks]),
			let data = try? JSONSerialization.data(withJSONObject: ["tasks": tasks])
		else { return nil }
		return try? TaskPlan.decode(data)
	}

	private func resultText(_ value: Any?) -> String {
		guard
			let result = value as? [String: Any],
			let content = result["content"] as? [[String: Any]]
		else { return "" }
		return content.compactMap { item in
			item["type"] as? String == "text" ? item["text"] as? String : nil
		}.joined(separator: "\n")
	}
}
