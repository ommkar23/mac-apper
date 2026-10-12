// @frontmatter:start
// Appends sequenced session events and pages validated journal history, repairing only partial tails.
// @frontmatter:end
import Foundation

/// Server-owned presentation history. Pi's session JSONL remains conversation context.
struct SessionEventJournal {
	let url: URL
	private static let maximumRecord = 65_536
	private static let maximumPage = 65_536

	init(sessionFile: URL, sessionID: String) throws {
		guard
			sessionFile.deletingPathExtension().lastPathComponent == sessionID,
			sessionID.range(of: "^[A-Za-z0-9-]{1,128}$", options: .regularExpression) != nil
		else { throw AgentProcessManagerError.invalidScope }
		let parent = sessionFile.deletingLastPathComponent().deletingLastPathComponent()
		guard
			parent.resolvingSymlinksInPath() == parent.standardizedFileURL
		else { throw AgentProcessManagerError.invalidScope }
		let directory = parent.appendingPathComponent("agent-events", isDirectory: true)
		try FileManager.default.createDirectory(
			at: directory, withIntermediateDirectories: true,
			attributes: [.posixPermissions: 0o700])
		let directoryValues = try directory.resourceValues(forKeys: [
			.isDirectoryKey, .isSymbolicLinkKey,
		])
		guard
			directoryValues.isDirectory == true,
			directoryValues.isSymbolicLink != true
		else { throw AgentProcessManagerError.invalidScope }
		url = directory.appendingPathComponent("\(sessionID).jsonl")
		if FileManager.default.fileExists(atPath: url.path) {
			let values = try url.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey])
			guard
				values.isRegularFile == true,
				values.isSymbolicLink != true
			else { throw AgentProcessManagerError.invalidScope }
		} else {
			guard
				FileManager.default.createFile(
					atPath: url.path, contents: nil,
					attributes: [.posixPermissions: 0o600])
			else { throw AgentProcessManagerError.invalidScope }
		}
	}

	func append(_ event: SequencedAgentServiceEvent) throws {
		let data = try JSONEncoder().encode(event)
		guard
			data.count <= Self.maximumRecord
		else { throw AgentProcessManagerError.invalidScope }
		let handle = try FileHandle(forWritingTo: url)
		defer { try? handle.close() }
		try handle.seekToEnd()
		try handle.write(contentsOf: data + Data([10]))
		try handle.synchronize()
	}

	func page(cursor: Int, limit: Int = 128) throws -> AgentSessionEventBatch {
		guard
			cursor >= 0,
			(1...128).contains(limit)
		else { throw AgentProcessManagerError.staleCursor }
		let scanned = try scan(cursor: cursor, limit: limit, repair: false)
		guard
			cursor <= scanned.total
		else { throw AgentProcessManagerError.staleCursor }
		return AgentSessionEventBatch(
			events: scanned.events, nextCursor: cursor + scanned.events.count,
			terminal: false, failure: nil)
	}

	func recover() throws -> Int {
		try scan(cursor: 0, limit: nil, repair: true).total
	}

	private func scan(cursor: Int, limit: Int?, repair: Bool)
		throws -> (events: [SequencedAgentServiceEvent], total: Int)
	{
		let handle = try FileHandle(forReadingFrom: url)
		defer { try? handle.close() }
		var buffer = Data()
		var total = 0
		var bytes = 0
		var events: [SequencedAgentServiceEvent] = []
		while let chunk = try handle.read(upToCount: 8_192), !chunk.isEmpty {
			buffer.append(chunk)
			while let newline = buffer.firstIndex(of: 10) {
				let line = Data(buffer[..<newline])
				buffer.removeSubrange(...newline)
				guard
					!line.isEmpty,
					line.count <= Self.maximumRecord,
					let event = try? JSONDecoder().decode(SequencedAgentServiceEvent.self, from: line),
					event.sequence == total
				else { throw AgentProcessManagerError.staleCursor }
				if total >= cursor {
					if !events.isEmpty && bytes + line.count > Self.maximumPage {
						return (events, total)
					}
					events.append(event)
					bytes += line.count
				}
				total += 1
				if let limit, events.count >= limit { return (events, total) }
			}
			guard
				buffer.count <= Self.maximumRecord
			else { throw AgentProcessManagerError.staleCursor }
		}
		if !buffer.isEmpty {
			guard
				repair
			else { throw AgentProcessManagerError.staleCursor }
			let writer = try FileHandle(forWritingTo: url)
			defer { try? writer.close() }
			let size = try writer.seekToEnd()
			try writer.truncate(atOffset: size - UInt64(buffer.count))
		}
		return (events, total)
	}
}
