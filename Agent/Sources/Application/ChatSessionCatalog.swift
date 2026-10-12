// @frontmatter:start
// Validates session paths and loads bounded Pi JSONL histories and session summaries.
// @frontmatter:end
import Foundation

public enum ChatSessionCatalog {
	public static func title(for prompt: String) -> String {
		let words = prompt.split(whereSeparator: \.isWhitespace).joined(separator: " ")
		return words.isEmpty ? "Untitled chat" : String(words.prefix(64))
	}

	public static func defaultDirectory(in project: URL) -> URL {
		project.appendingPathComponent(".pi/sessions", isDirectory: true)
	}

	/// Require an exact configured session path and never follow a linked directory or file.
	public static func validate(_ file: URL, in project: URL, sessionDirectory: URL? = nil) throws {
		let project = project.standardizedFileURL
		let defaultDirectory = self.defaultDirectory(in: project).standardizedFileURL
		let directory = (sessionDirectory ?? defaultDirectory).standardizedFileURL
		guard
			file.isFileURL,
			file.deletingLastPathComponent().standardizedFileURL.path == directory.path,
			file.pathExtension == "jsonl",
			!file.lastPathComponent.hasPrefix(".")
		else { throw WorkspaceError.invalidPath }
		var protectedURLs = [project, directory, file]
		if directory == defaultDirectory { protectedURLs.append(project.appendingPathComponent(".pi")) }
		for url in protectedURLs {
			if let attributes = try? FileManager.default.attributesOfItem(atPath: url.path),
				attributes[.type] as? FileAttributeType == .typeSymbolicLink
			{
				throw WorkspaceError.symbolicLink
			}
		}
	}

	public static func discover(in project: URL, sessionDirectory: URL? = nil) throws
		-> [ChatSessionSummary]
	{
		let directory = sessionDirectory ?? defaultDirectory(in: project)
		try validate(
			directory.appendingPathComponent("scope-check.jsonl"), in: project,
			sessionDirectory: directory)
		guard
			FileManager.default.fileExists(atPath: directory.path)
		else { return [] }
		let files = try FileManager.default.contentsOfDirectory(
			at: directory, includingPropertiesForKeys: [.isRegularFileKey], options: [.skipsHiddenFiles])
		guard
			files.count <= 1000
		else { throw SessionError.streamLimit }
		return files.filter { $0.pathExtension == "jsonl" }.compactMap {
			try? load($0, in: project, sessionDirectory: directory).summary
		}
		.sorted {
			$0.modified == $1.modified
				? $0.file.lastPathComponent > $1.file.lastPathComponent : $0.modified > $1.modified
		}
	}

	public static func load(_ file: URL, in project: URL, sessionDirectory: URL? = nil) throws
		-> ChatSessionHistory
	{
		try validate(file, in: project, sessionDirectory: sessionDirectory)
		let values = try file.resourceValues(forKeys: [
			.isRegularFileKey, .fileSizeKey, .contentModificationDateKey,
		])
		guard
			values.isRegularFile == true,
			(values.fileSize ?? Int.max) <= 16_777_216
		else { throw SessionError.streamLimit }
		let handle = try FileHandle(forReadingFrom: file)
		defer { try? handle.close() }
		let data = try handle.read(upToCount: 16_777_217) ?? Data()
		guard
			data.count <= 16_777_216
		else { throw SessionError.streamLimit }
		// A concurrent writer may have an incomplete final record; do not display it.
		let lines = data.split(separator: 10, omittingEmptySubsequences: true)
		guard
			let first = lines.first,
			let header = try JSONSerialization.jsonObject(with: Data(first)) as? [String: Any],
			header["type"] as? String == "session",
			[2, 3].contains(header["version"] as? Int ?? 0),
			let cwd = header["cwd"] as? String,
			URL(fileURLWithPath: cwd).resolvingSymlinksInPath() == project.resolvingSymlinksInPath()
		else { throw SessionError.invalidEvent }
		var entries: [String: [String: Any]] = [:]
		var leaf: String?
		var name: String?
		for (index, line) in lines.dropFirst().enumerated() {
			guard
				line.count <= 4_194_304
			else { throw SessionError.streamLimit }
			guard
				let entry = try? JSONSerialization.jsonObject(with: Data(line)) as? [String: Any]
			else {
				if index == lines.count - 2 && data.last != 10 { break }
				throw SessionError.invalidEvent
			}
			guard
				let id = entry["id"] as? String,
				entries[id] == nil
			else { throw SessionError.invalidEvent }
			entries[id] = entry
			leaf = id
			if entry["type"] as? String == "session_info" { name = entry["name"] as? String }
		}
		var branch: [[String: Any]] = []
		var visited = Set<String>()
		while let id = leaf {
			guard
				visited.insert(id).inserted,
				let entry = entries[id]
			else { throw SessionError.invalidEvent }
			branch.append(entry)
			leaf = entry["parentId"] as? String
		}
		var messages: [ChatMessage] = []
		var textBytes = 0
		for entry in branch.reversed() {
			guard
				entry["type"] as? String == "message",
				let message = entry["message"] as? [String: Any],
				let role = message["role"] as? String,
				role == "user" || role == "assistant"
			else { continue }
			let text =
				message["content"] as? String
				?? (message["content"] as? [[String: Any]] ?? []).compactMap {
					$0["type"] as? String == "text" ? $0["text"] as? String : nil
				}.joined(separator: "\n")
			textBytes += text.utf8.count
			guard
				textBytes <= 4_194_304
			else { throw SessionError.streamLimit }
			if !text.isEmpty { messages.append(ChatMessage(isUser: role == "user", text: text)) }
		}
		let title =
			name.flatMap {
				$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || $0 == "Mac Apper"
					? nil : Self.title(for: $0)
			}
			?? Self.title(for: messages.first(where: \.isUser)?.text ?? "")
		return ChatSessionHistory(
			summary: ChatSessionSummary(
				file: file, title: title, modified: values.contentModificationDate ?? .distantPast),
			messages: messages)
	}
}
