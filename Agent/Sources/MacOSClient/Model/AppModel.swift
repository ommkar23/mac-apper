// @frontmatter:start
// Accumulates bounded transcript, task, status, and activity presentation from Pi events.
// @frontmatter:end
import Foundation
import Observation

@MainActor @Observable public final class AppModel {
	public private(set) var transcript = ""
	public private(set) var tasks: [AgentTaskRecord] = []
	public private(set) var status = "Ready"
	public private(set) var liveDetails: [String] = []

	public init() {}

	public func accept(_ event: PiRPCEvent) {
		switch event {
		case .textDelta(let delta):
			guard
				transcript.utf8.count + delta.utf8.count <= 1_048_576
			else {
				status = "Failed"
				liveDetails.append("Pi output exceeded the display limit.")
				return
			}
			transcript += delta
			status = "Working"
		case .tasksUpdated(let tasks):
			self.tasks = tasks
			status = "Working"
		case .toolStarted(_, let name, _):
			status = name
			liveDetails.append("\(name) · started")
		case .toolUpdated(_, let name, let text):
			status = name
			if !text.isEmpty { liveDetails.append("\(name) · \(text.prefix(500))") }
		case .toolFinished(_, let name, let text, let isError):
			status = isError ? "Failed" : "Working"
			liveDetails.append(
				"\(name) · \(isError ? "failed" : "completed")"
					+ (text.isEmpty ? "" : " · \(text.prefix(500))"))
		case .extensionError(let message):
			status = "Failed"
			liveDetails.append("Extension error · \(message.prefix(500))")
		case .notification(let message):
			liveDetails.append(message)
		case .response(_, let command, let success, let error):
			if !success {
				status = "Failed"
				liveDetails.append("\(command) rejected" + (error.map { " · \($0.prefix(500))" } ?? ""))
			}
		case .settled:
			if status != "Failed" && status != "Cancelled" { status = "Completed" }
		}
		if liveDetails.count > 200 { liveDetails.removeFirst(liveDetails.count - 200) }
	}

	public func finish(cancelled: Bool) {
		status = cancelled ? "Cancelled" : "Failed"
	}
}
