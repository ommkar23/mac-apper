// @frontmatter:start
// Drives WorkspaceSession with production client adapters and audits only test-owned Chat histories, processes, and cleanup.
// @frontmatter:end
import AgentMacosClient
import AgentMacosClientModel
import AgentScenarioSupport
import Foundation
import Scenario

private enum ChatModelFailure: Error {
	case timeout, modelFailed, invalidScope, invalidHistory, cleanupFailed, missingProcess
}

@MainActor final class ChatModelSession {
	let adapter = AgentServiceXPCAdapter()
	let runtime: AgentXPCRuntime
	let workspace: WorkspaceSession
	private var submission: Task<Void, Never>?
	private var launchSnapshot: ScenarioProcessSnapshot?
	private var launchStamp: String?
	private var ownedPi: [ChatOwnedPiIdentity] = []

	init() {
		runtime = AgentXPCRuntime(transport: adapter)
		workspace = WorkspaceSession(
			runtime: runtime, workspaceStore: AgentXPCWorkspaceStore(transport: adapter))
		workspace.selectAgent("chat")
	}
	var file: URL {
		get throws {
			guard
				let file = workspace.sessionFile
			else { throw ChatModelFailure.invalidScope };
			return file
		}
	}
	var project: URL {
		get throws {
			guard
				let project = workspace.project
			else { throw ChatModelFailure.invalidScope };
			return project
		}
	}
	var id: UUID {
		get throws {
			guard
				let id = UUID(uuidString: try file.deletingPathExtension().lastPathComponent)
			else { throw ChatModelFailure.invalidScope }; return id
		}
	}
	var successfulTools: Set<String> {
		get throws {
			let evidence = try ScenarioToolEvidence(session: file)
			for call in evidence.calls {
				print(
					"CHAT_TOOL_EVIDENCE: name=\(call.name) id=\(call.id) parent=\(call.parentID ?? "direct") succeeded=\(call.succeeded) start=\(call.started) finish=\(call.finished)"
				)
			}
			return Set(evidence.calls.filter { $0.succeeded && !$0.resultText.isEmpty }.map(\.name))
		}
	}

	func submit(_ text: String) async throws {
		guard
			!workspace.busy
		else { throw ChatModelFailure.modelFailed }
		workspace.idea = text
		if workspace.connected {
			await workspace.submit()
		} else {
			launchSnapshot = nil; launchStamp = nil
			submission = Task { await workspace.submit() }
			var identityFailure: (any Error)?
			try await wait {
				// Capture immutable process identity before Pi can rewrite its displayed argv.
				if self.launchSnapshot == nil, self.workspace.sessionFile != nil,
					let snapshot = try? self.findRunningPi(),
					let stamp = try? self.processIdentity(snapshot.pid)
				{
					do {
						guard
							let pid = Int32(snapshot.pid)
						else { throw ChatModelFailure.missingProcess }
						self.ownedPi.append(try ChatOwnedPiIdentity.capture(pid))
						self.launchSnapshot = snapshot; self.launchStamp = stamp
					} catch { identityFailure = error }
				}
				return identityFailure != nil || self.workspace.connected
			}
			if let identityFailure { throw identityFailure }
		}
		guard
			workspace.idea.isEmpty,
			workspace.sessionFile != nil,
			workspace.isChatOnly,
			workspace.selectedAgentID == "chat"
		else { throw ChatModelFailure.modelFailed }
	}

	func answer() async throws -> String {
		try await wait { !self.workspace.busy && self.workspace.state.status == "Completed" }
		guard
			let text = workspace.messages.last(where: { !$0.isUser })?.text,
			!text.isEmpty,
			text.utf8.count <= 60_000
		else { throw ChatModelFailure.modelFailed }
		return text
	}
	func prompt(_ text: String) async throws -> String {
		try await submit(text); return try await answer()
	}

	func wait(timeout: Int = 160, until predicate: @MainActor () -> Bool) async throws {
		let deadline = ContinuousClock.now.advanced(by: .seconds(timeout))
		while !predicate() {
			try Task.checkCancellation()
			guard
				ContinuousClock.now < deadline
			else { throw ChatModelFailure.timeout }
			guard
				workspace.busy || workspace.state.status != "Failed"
			else { throw ChatModelFailure.modelFailed }
			try await Task.sleep(for: .milliseconds(50))
		}
	}

	func waitUntilActive() async throws {
		try await wait(timeout: 120) {
			self.workspace.busy
				&& self.workspace.state.liveDetails.contains(where: { $0.hasSuffix(" · started") })
		}
	}

	func history(at cursor: Int) async throws -> AgentSessionEventBatch {
		let batch = try await adapter.history(
			.init(sessionID: try id.uuidString.lowercased(), cursor: cursor),
			projectPath: try project.path)
		guard
			batch.failure == nil,
			batch.nextCursor == cursor + batch.events.count,
			batch.events.enumerated().allSatisfy({ $0.element.sequence == cursor + $0.offset })
		else { throw ChatModelFailure.invalidHistory }
		return batch
	}
	func allHistory() async throws -> [SequencedAgentServiceEvent] {
		var events: [SequencedAgentServiceEvent] = []
		while true {
			let batch = try await history(at: events.count)
			guard
				events.count + batch.events.count <= 8192
			else { throw ChatModelFailure.invalidHistory }
			events += batch.events
			if batch.events.isEmpty { return events }
		}
	}

	func audit() throws -> ScenarioSessionAudit {
		let file = try file
		let values = try file.resourceValues(forKeys: [
			.isRegularFileKey, .isSymbolicLinkKey, .fileSizeKey,
		])
		guard
			values.isRegularFile == true,
			values.isSymbolicLink != true,
			let size = values.fileSize,
			size <= 4_194_304
		else { throw ChatModelFailure.invalidHistory }
		return try ScenarioSessionAudit.read(Data(contentsOf: file), expectedProject: try project.path)
	}

	func stop() async throws {
		// A partial startup must not leave an untracked Pi behind when its host is retained.
		if ownedPi.isEmpty, workspace.sessionFile != nil {
			let snapshot = try findRunningPi()
			guard
				let pid = Int32(snapshot.pid)
			else { throw ChatModelFailure.missingProcess }
			ownedPi.append(try ChatOwnedPiIdentity.capture(pid))
		}
		if let file = workspace.sessionFile, !workspace.connected {
			_ = try await runtime.attach(sessionFile: file)
		}
		guard
			await runtime.stop(),
			await workspace.shutdown()
		else { throw ChatModelFailure.cleanupFailed }
		for identity in ownedPi { try identity.reap() }
		await submission?.value
		submission = nil
	}

	func validateOwnedPiReaped() throws {
		for identity in ownedPi { try identity.requireReaped() }
	}

	func removeOwnedFiles() throws {
		try validateOwnedPiReaped()
		guard
			let file = workspace.sessionFile,
			let project = workspace.project
		else { return }
		let manager = FileManager.default
		let expected = manager.homeDirectoryForCurrentUser.appendingPathComponent(".mac-apper/.chat")
			.standardizedFileURL
		guard
			project.standardizedFileURL == expected,
			file.deletingLastPathComponent().standardizedFileURL
				== expected.appendingPathComponent(".pi/sessions"),
			file.pathExtension == "jsonl",
			UUID(uuidString: file.deletingPathExtension().lastPathComponent) != nil
		else { throw ChatModelFailure.invalidScope }
		for directory in [
			expected.deletingLastPathComponent(), expected, expected.appendingPathComponent(".pi"),
			expected.appendingPathComponent(".pi/sessions"),
			expected.appendingPathComponent(".pi/agent-events"),
		]
		where manager.fileExists(atPath: directory.path) {
			guard
				try directory.resourceValues(forKeys: [.isSymbolicLinkKey]).isSymbolicLink != true
			else { throw ChatModelFailure.invalidScope }
		}
		let journal = project.appendingPathComponent(
			".pi/agent-events/\(try id.uuidString.lowercased()).jsonl")
		let archive = URL(fileURLWithPath: "/private/tmp/mac-apper-chat-evidence-\(UUID().uuidString)")
		try manager.createDirectory(
			at: archive, withIntermediateDirectories: false,
			attributes: [.posixPermissions: 0o700])
		print("CHAT_EVIDENCE_RETAINED: \(archive.path) session=\(file.path) journal=\(journal.path)")
		for (url, name) in [(file, "session.jsonl"), (journal, "journal.jsonl")]
		where manager.fileExists(atPath: url.path) {
			let values = try url.resourceValues(forKeys: [
				.isRegularFileKey, .isSymbolicLinkKey, .fileSizeKey,
			])
			guard
				values.isRegularFile == true,
				values.isSymbolicLink != true,
				let size = values.fileSize,
				size <= 4_194_304
			else { throw ChatModelFailure.invalidScope }
			let copy = archive.appendingPathComponent(name)
			try manager.copyItem(at: url, to: copy)
			try manager.setAttributes([.posixPermissions: 0o600], ofItemAtPath: copy.path)
			try manager.removeItem(at: url)
		}
	}

	func runningPi() throws -> ScenarioProcessSnapshot {
		guard
			let snapshot = launchSnapshot,
			try processIdentity(snapshot.pid) == launchStamp
		else { throw ChatModelFailure.missingProcess }
		return snapshot
	}
	private func findRunningPi() throws -> ScenarioProcessSnapshot {
		let data = try processOutput(["-ww", "-axo", "pid=,command="], limit: 2_000_000)
		return try ScenarioProcessSnapshot.find(
			String(decoding: data, as: UTF8.self), sessionPath: try file.path)
	}
	func processIdentity(_ pid: String) throws -> String {
		guard
			Int32(pid) != nil
		else { throw ChatModelFailure.missingProcess }
		let data = try processOutput(["-p", pid, "-o", "lstart="], limit: 256)
		let stamp = String(decoding: data, as: UTF8.self).trimmingCharacters(
			in: .whitespacesAndNewlines)
		guard
			!stamp.isEmpty
		else { throw ChatModelFailure.missingProcess }
		return stamp
	}
	private func processOutput(_ arguments: [String], limit: Int) throws -> Data {
		let process = Process(); process.executableURL = URL(fileURLWithPath: "/bin/ps");
		process.arguments = arguments
		let output = Pipe(); process.standardOutput = output;
		process.standardError = FileHandle.nullDevice
		try process.run()
		let data = output.fileHandleForReading.readDataToEndOfFile(); process.waitUntilExit()
		guard
			process.terminationStatus == 0,
			data.count <= limit
		else { throw ChatModelFailure.missingProcess }
		return data
	}
}

@MainActor final class ChatModelSessions: CaseContext {
	var owned: [ChatModelSession] = []
	func create(_ prompt: String) async throws -> ChatModelSession {
		let session = ChatModelSession(); owned.append(session)
		try await session.submit(prompt)
		return session
	}
	func cleanup() async throws {
		var failures: [String] = []
		for session in owned.reversed() {
			do {
				try await ChatScenarioCleanup.removeSession(
					stop: { try await session.stop() },
					reap: { try session.validateOwnedPiReaped() },
					remove: { try session.removeOwnedFiles() })
			} catch { failures.append(String(describing: error)) }
		}
		guard
			failures.isEmpty
		else { throw ScenarioFailure.message("Chat cleanup failed; retain host/evidence: \(failures)") }
		print(ChatScenarioCleanup.confirmation)
	}
}
