// @frontmatter:start
// Correlates bounded Agent journal tool lifecycles with direct Pi results and complete persisted nested-call ancestry.
// @frontmatter:end
import CoreFoundation
import Foundation

private enum ToolEvidenceFailure: Error {
	case invalid, incomplete, mismatch
}

struct ScenarioToolCall {
	let id: String
	let name: String
	let arguments: [String: Any]
	let parentID: String?
	let started: Int
	let finished: Int
	let succeeded: Bool
	let resultText: String
	// Nested calls have no persisted result; only their actual journal completion supplies this JSON.
	let typedResult: [String: Any]?
	let deliveryTool: String
	let deliveredContent: [[String: Any]]

	func deliversPNG(_ bytes: Data) -> Bool {
		guard
			succeeded,
			bytes.count <= 2_097_152,
			parentID == nil || deliveryTool == "codemode"
		else { return false }
		return deliveredContent.contains {
			guard
				$0["type"] as? String == "image",
				$0["mimeType"] as? String == "image/png",
				let encoded = $0["data"] as? String,
				encoded.utf8.count <= 2_796_204
			else { return false }
			return Data(base64Encoded: encoded) == bytes
		}
	}
}

struct ScenarioToolEvidence {
	let calls: [ScenarioToolCall]

	init(session: URL) throws {
		let journal = session.deletingLastPathComponent().deletingLastPathComponent()
			.appendingPathComponent("agent-events/\(session.lastPathComponent)")
		try self.init(session: Self.read(session), journal: Self.read(journal))
	}

	init(session: Data, journal: Data) throws {
		let transcript = try Self.transcript(session)
		let lifecycles = try Self.lifecycles(journal)
		guard
			Set(transcript.keys) == Set(lifecycles.keys)
		else { throw ToolEvidenceFailure.incomplete }
		var matched: [ScenarioToolCall] = []
		for (id, recorded) in transcript {
			guard
				let lifecycle = lifecycles[id],
				let end = lifecycle.end,
				let isError = lifecycle.isError,
				let text = lifecycle.text,
				recorded.name == lifecycle.name,
				try Self.same(recorded.arguments, lifecycle.arguments),
				recorded.failed == isError
			else { throw ToolEvidenceFailure.mismatch }
			let root = try Self.root(of: id, in: transcript)
			guard
				let rootLifecycle = lifecycles[root.id],
				let rootEnd = rootLifecycle.end,
				rootLifecycle.text == Self.text(root.message),
				rootLifecycle.isError == root.failed
			else { throw ToolEvidenceFailure.mismatch }
			if let parentID = recorded.parentID {
				guard
					let parent = lifecycles[parentID],
					let parentEnd = parent.end,
					parent.start < lifecycle.start,
					end < parentEnd
				else { throw ToolEvidenceFailure.mismatch }
			}
			guard
				rootLifecycle.start <= lifecycle.start,
				end <= rootEnd
			else { throw ToolEvidenceFailure.mismatch }
			var succeeded = !isError && !root.failed
			var ancestorID = recorded.parentID
			while let parentID = ancestorID {
				guard
					let ancestor = transcript[parentID]
				else { throw ToolEvidenceFailure.incomplete }
				succeeded = succeeded && !ancestor.failed
				ancestorID = ancestor.parentID
			}
			var typed: [String: Any]?
			if succeeded && ["test", "preview", "build", "run", "plan"].contains(recorded.name) {
				guard
					let json = text.data(using: .utf8),
					let value = try? Self.object(json)
				else { throw ToolEvidenceFailure.mismatch }
				typed = value
				if recorded.parentID == nil {
					guard
						let details = recorded.message["details"] as? [String: Any],
						let result = details["result"] as? [String: Any],
						try Self.same(value, result)
					else { throw ToolEvidenceFailure.mismatch }
				}
			}
			matched.append(
				ScenarioToolCall(
					id: id, name: recorded.name, arguments: lifecycle.arguments,
					parentID: recorded.parentID, started: lifecycle.start, finished: end,
					succeeded: succeeded, resultText: text, typedResult: typed,
					deliveryTool: root.name,
					deliveredContent: root.message["content"] as? [[String: Any]] ?? []))
		}
		calls = matched.sorted { $0.started < $1.started }
	}

	// Capture revisions at Test start, not completion: a concurrent write cannot make a stale pass qualify.
	func testedSourcePaths(project: URL) throws -> [String] {
		let mutations = try calls.filter { ["write", "edit"].contains($0.name) }.compactMap {
			call -> (String, Int, Bool)? in
			guard
				let path = call.arguments["path"] as? String
			else { throw ToolEvidenceFailure.invalid }
			let prefix = project.path + "/"
			let relative = path.hasPrefix(prefix) ? String(path.dropFirst(prefix.count)) : path
			guard
				relative.hasPrefix("Tests/AppModelTests/"),
				relative.hasSuffix(".swift")
			else { return nil }
			guard
				relative.split(separator: "/", omittingEmptySubsequences: false)
					.allSatisfy({ !$0.isEmpty && $0 != "." && $0 != ".." })
			else { throw ToolEvidenceFailure.invalid }
			return (relative, call.finished, call.succeeded)
		}
		guard
			Set(mutations.map { $0.0 }).count <= 32
		else { throw ToolEvidenceFailure.invalid }
		let passing = calls.filter {
			$0.succeeded && $0.name == "test" && $0.typedResult?["status"] as? String == "passed"
				&& Self.integer($0.typedResult?["exitCode"]) == 0
		}
		var latest: [String: Int] = [:]
		var authored: Set<String> = []
		for (path, revision, succeeded) in mutations {
			latest[path] = max(latest[path] ?? -1, revision)
			if succeeded { authored.insert(path) }
		}
		return latest.filter { path, revision in
			authored.contains(path) && passing.contains { revision < $0.started }
		}.keys.sorted()
	}

	private struct Recorded {
		let id: String
		let name: String
		let arguments: [String: Any]
		let parentID: String?
		let failed: Bool
		let message: [String: Any]
	}

	private struct Lifecycle {
		let name: String
		let arguments: [String: Any]
		let start: Int
		var end: Int?
		var text: String?
		var isError: Bool?
	}

	private static func transcript(_ data: Data) throws -> [String: Recorded] {
		var pending: [String: [String: Any]] = [:]
		var seen: Set<String> = []
		var records: [String: Recorded] = [:]
		for entry in try lines(data, maximumLine: 4_194_304) {
			guard
				entry["type"] as? String == "message",
				let message = entry["message"] as? [String: Any]
			else { continue }
			if message["role"] as? String == "assistant" {
				for call in message["content"] as? [[String: Any]] ?? []
				where call["type"] as? String == "toolCall" {
					let id = try identifier(call["id"])
					guard
						seen.insert(id).inserted
					else { throw ToolEvidenceFailure.invalid }
					pending[id] = call
				}
			}
			guard
				message["role"] as? String == "toolResult"
			else { continue }
			let id = try identifier(message["toolCallId"])
			guard
				let call = pending.removeValue(forKey: id),
				let name = call["name"] as? String,
				message["toolName"] as? String == name,
				let arguments = call["arguments"] as? [String: Any],
				let failed = message["isError"] as? Bool,
				records[id] == nil
			else { throw ToolEvidenceFailure.invalid }
			records[id] = Recorded(
				id: id, name: name, arguments: arguments, parentID: nil,
				failed: failed, message: message)
			if let nested = message["nestedCalls"] as? [String: Any] {
				guard
					nested["complete"] as? Bool == true,
					let children = nested["calls"] as? [[String: Any]],
					children.count <= 256
				else { throw ToolEvidenceFailure.incomplete }
				for child in children {
					let childID = try identifier(child["id"])
					let components = childID.split(separator: "/", omittingEmptySubsequences: false)
					guard
						childID.hasPrefix(id + "/"),
						let last = components.last,
						let number = Int(last),
						number > 0,
						String(number) == last,
						seen.insert(childID).inserted,
						let childName = child["name"] as? String,
						let childArgs = child["arguments"] as? [String: Any],
						let status = child["status"] as? String,
						["ok", "error"].contains(status)
					else { throw ToolEvidenceFailure.incomplete }
					let parent = components.dropLast().joined(separator: "/")
					records[childID] = Recorded(
						id: childID, name: childName, arguments: childArgs,
						parentID: parent, failed: status == "error", message: [:])
				}
			}
		}
		guard
			pending.isEmpty
		else { throw ToolEvidenceFailure.incomplete }
		return records
	}

	private static func lifecycles(_ data: Data) throws -> [String: Lifecycle] {
		var calls: [String: Lifecycle] = [:]
		for (sequence, record) in try lines(data, maximumLine: 65_536).enumerated() {
			guard
				integer(record["sequence"]) == sequence,
				let event = record["event"] as? [String: Any],
				event.count == 1
			else { throw ToolEvidenceFailure.invalid }
			if let started = event["toolStarted"] as? [String: Any] {
				let id = try identifier(started["id"])
				guard
					calls[id] == nil,
					let name = started["name"] as? String,
					let text = started["text"] as? String,
					let bytes = text.data(using: .utf8)
				else { throw ToolEvidenceFailure.invalid }
				calls[id] = Lifecycle(name: name, arguments: try object(bytes), start: sequence)
			}
			if let finished = event["toolFinished"] as? [String: Any] {
				let id = try identifier(finished["id"])
				guard
					var call = calls[id],
					call.end == nil,
					finished["name"] as? String == call.name,
					let text = finished["text"] as? String,
					let failed = finished["isError"] as? Bool
				else { throw ToolEvidenceFailure.invalid }
				call.end = sequence; call.text = text; call.isError = failed
				calls[id] = call
			}
		}
		return calls
	}

	private static func root(of id: String, in records: [String: Recorded]) throws -> Recorded {
		guard
			var current = records[id]
		else { throw ToolEvidenceFailure.incomplete }
		var visited: Set<String> = [id]
		while let parent = current.parentID {
			guard
				visited.insert(parent).inserted,
				let next = records[parent]
			else { throw ToolEvidenceFailure.incomplete }
			current = next
		}
		return current
	}

	private static func read(_ url: URL) throws -> Data {
		let values = try url.resourceValues(forKeys: [
			.isRegularFileKey, .isSymbolicLinkKey, .fileSizeKey,
		])
		guard
			values.isRegularFile == true,
			values.isSymbolicLink != true,
			(values.fileSize ?? Int.max) <= 4_194_304
		else { throw ToolEvidenceFailure.invalid }
		let handle = try FileHandle(forReadingFrom: url)
		defer { try? handle.close() }
		return try handle.read(upToCount: 4_194_305) ?? Data()
	}

	private static func lines(_ data: Data, maximumLine: Int) throws -> [[String: Any]] {
		guard
			data.count <= 4_194_304,
			data.isEmpty || data.last == 10
		else { throw ToolEvidenceFailure.incomplete }
		return try data.split(separator: 10, omittingEmptySubsequences: false).dropLast().map {
			guard
				!$0.isEmpty,
				$0.count <= maximumLine
			else { throw ToolEvidenceFailure.invalid }
			return try object(Data($0))
		}
	}

	private static func object(_ data: Data) throws -> [String: Any] {
		guard
			let value = try JSONSerialization.jsonObject(with: data) as? [String: Any]
		else { throw ToolEvidenceFailure.invalid }
		return value
	}

	private static func integer(_ value: Any?) -> Int? {
		guard
			let number = value as? NSNumber,
			CFGetTypeID(number) != CFBooleanGetTypeID(),
			number.doubleValue == Double(number.intValue)
		else { return nil }
		return number.intValue
	}

	private static func identifier(_ value: Any?) throws -> String {
		guard
			let id = value as? String,
			!id.isEmpty,
			id.utf8.count <= 1024
		else { throw ToolEvidenceFailure.invalid }
		return id
	}

	private static func same(_ lhs: [String: Any], _ rhs: [String: Any]) throws -> Bool {
		try JSONSerialization.data(withJSONObject: lhs, options: [.sortedKeys])
			== JSONSerialization.data(withJSONObject: rhs, options: [.sortedKeys])
	}

	private static func text(_ message: [String: Any]) -> String {
		(message["content"] as? [[String: Any]] ?? []).compactMap {
			$0["type"] as? String == "text" ? $0["text"] as? String : nil
		}.joined(separator: "\n")
	}
}
