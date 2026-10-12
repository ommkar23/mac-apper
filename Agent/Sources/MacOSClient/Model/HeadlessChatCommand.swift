// @frontmatter:start
// Submits one headless Chat message through WorkspaceSession and returns bounded presentation state after stopping its runtime.
// @frontmatter:end
import Foundation

public struct HeadlessChatResult: Codable, Sendable {
	public let success: Bool
	public let reply: String?
	public let agentID: String
	public let isChatOnly: Bool
	public let status: String
	public let projectPath: String?
	public let sessionFilePath: String?
	public let cleanupVerified: Bool
}

@MainActor public enum HeadlessChatCommand {
	public static func run(
		message: String, runtime: any AgentSessionRuntime,
		store: any WorkspaceStore
	) async -> HeadlessChatResult {
		let workspace = WorkspaceSession(runtime: runtime, workspaceStore: store)
		workspace.selectAgent("chat")
		let text = message.trimmingCharacters(in: .whitespacesAndNewlines)
		guard
			!text.isEmpty,
			text.utf8.count <= 60_000
		else {
			return HeadlessChatResult(
				success: false, reply: nil, agentID: "chat", isChatOnly: true,
				status: "InvalidRequest", projectPath: nil, sessionFilePath: nil, cleanupVerified: true)
		}
		workspace.idea = text
		let submission = Task { await workspace.submit() }
		let deadline = ContinuousClock.now.advanced(by: .seconds(120))
		var completed = false
		while ContinuousClock.now < deadline {
			if workspace.state.status == "Completed", !workspace.busy { completed = true; break }
			if workspace.state.status == "Failed" { break }
			do { try await Task.sleep(for: .milliseconds(50)) } catch { break }
		}
		let reply = workspace.messages.last(where: { !$0.isUser })?.text
		let bounded = reply.map { $0.utf8.count <= 8000 } ?? false
		let status = completed ? workspace.state.status : "Incomplete"
		let project = workspace.project?.path, file = workspace.sessionFile?.path
		let stopped = await runtime.stop()
		_ = await workspace.shutdown()
		await submission.value
		return HeadlessChatResult(
			success: completed && bounded && stopped,
			reply: bounded ? reply : nil, agentID: workspace.selectedAgentID,
			isChatOnly: workspace.isChatOnly,
			status: status, projectPath: project, sessionFilePath: file, cleanupVerified: stopped)
	}
}
