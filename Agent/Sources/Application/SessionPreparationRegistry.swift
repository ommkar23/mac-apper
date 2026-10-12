// @frontmatter:start
// Tracks bounded service-issued session bindings until the Agent starts or resumes them.
// @frontmatter:end
import Foundation

@MainActor public final class SessionPreparationRegistry {
	private struct Entry {
		let request: AgentSessionStartRequest
		var issuedAt: Date
		var starting = false
	}

	private var entries: [String: Entry] = [:]
	private let maximumPending = 256
	private let lifetime: TimeInterval = 15 * 60

	public init() {}

	func issue(_ prepared: WorkspacePreparedSession, agentID: String) throws {
		let sessionID = prepared.sessionFile.deletingPathExtension().lastPathComponent
		let request = try AgentSessionStartRequest(
			sessionID: sessionID, agentID: agentID,
			projectPath: prepared.project.path, sessionFilePath: prepared.sessionFile.path,
			title: prepared.isNew ? prepared.title : nil, firstRequest: prepared.creatingApp)
		let now = Date()
		entries = entries.filter {
			$0.value.starting || now.timeIntervalSince($0.value.issuedAt) < lifetime
		}
		if let existing = entries[sessionID] {
			guard
				!existing.starting,
				existing.request.agentID == request.agentID,
				existing.request.projectPath == request.projectPath,
				existing.request.sessionFilePath == request.sessionFilePath
			else { throw AgentProcessManagerError.duplicateSession }
		} else if entries.count >= maximumPending {
			guard
				let oldest = entries.filter({ !$0.value.starting }).min(by: {
					$0.value.issuedAt < $1.value.issuedAt
				})
			else { throw AgentProcessManagerError.invalidScope }
			entries.removeValue(forKey: oldest.key)
		}
		entries[sessionID] = Entry(request: request, issuedAt: now)
	}

	func begin(_ request: AgentSessionStartRequest) throws {
		guard
			var entry = entries[request.sessionID],
			entry.request == request,
			!entry.starting,
			Date().timeIntervalSince(entry.issuedAt) < lifetime
		else { throw AgentProcessManagerError.invalidScope }
		entry.starting = true
		entries[request.sessionID] = entry
	}

	func finish(sessionID: String, started: Bool) {
		guard
			var entry = entries[sessionID],
			entry.starting
		else { return }
		if started {
			entries.removeValue(forKey: sessionID)
		} else {
			entry.starting = false
			entries[sessionID] = entry
		}
	}

	func discardIfMatches(_ request: AgentSessionStartRequest) {
		guard
			entries[request.sessionID]?.request == request
		else { return }
		entries.removeValue(forKey: request.sessionID)
	}
}
