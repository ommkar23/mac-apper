// @frontmatter:start
// Records bounded, metadata-only diagnostics in private rotating files with safe directory traversal.
// @frontmatter:end
import Foundation

#if os(Linux)
	import Glibc
#else
	import Darwin
#endif

/// Metadata only. No free-form message, URL, path, body, header or error description API.
public struct DiagnosticRecord: Codable, Sendable {
	public enum Kind: String, Codable, Sendable {
		case request, session, process, tool, event, lifecycle
	}
	public let kind: Kind
	public let operation: String
	public let code: String
	public let requestID: String?
	public let sessionID: String?
	public let sequence: Int?
	public let status: Int?
	public let durationMS: Int?
	public let timestamp: Double
	public let toolKey: String?
	public init(
		kind: Kind, operation: String, code: String, requestID: String? = nil, sessionID: String? = nil,
		sequence: Int? = nil, status: Int? = nil, durationMS: Int? = nil, toolID: String? = nil
	) {
		// Fingerprint only: arbitrary incoming opaque IDs cannot inject content into logs.
		self.toolKey = toolID.map {
			String(
				$0.utf8.prefix(128).reduce(UInt64(14_695_981_039_346_656_037)) {
					($0 ^ UInt64($1)) &* 1_099_511_628_211
				}, radix: 16)
		}
		self.kind = kind
		self.operation = Self.operations.contains(operation) ? operation : "unknown"
		self.code = Self.codes.contains(code) ? code : "unknown"
		self.requestID = requestID.flatMap { UUID(uuidString: $0)?.uuidString.lowercased() }
		self.sessionID = sessionID.flatMap { UUID(uuidString: $0)?.uuidString.lowercased() }
		self.sequence = sequence.map { max(0, min($0, 100_000)) }
		self.status = status.map { max(0, min($0, 599)) }
		self.durationMS = durationMS.map { max(0, min($0, 3_600_000)) }
		self.timestamp = Date().timeIntervalSince1970
	}
	var isSafe: Bool {
		Self.operations.contains(operation) && Self.codes.contains(code) && timestamp.isFinite
			&& (requestID == nil || UUID(uuidString: requestID!) != nil)
			&& (sessionID == nil || UUID(uuidString: sessionID!) != nil)
			&& (toolKey == nil
				|| (toolKey!.count <= 16
					&& toolKey!.utf8.allSatisfy { (48...57).contains($0) || (97...102).contains($0) }))
	}
	private static let operations: Set<String> = [
		"start", "events", "results", "cancel", "health", "models", "responses", "unknown", "build",
		"run", "tests", "stop", "capture_window", "diagnostics", "plan", "package", "read_file",
		"write_file", "list_files", "text_delta", "tool_call", "tool_result", "file_changed",
		"completed", "cancelled", "error", "launch", "exit", "tool_activity", "incomplete",
	]
	private static let codes: Set<String> = [
		"ok", "started", "completed", "cancelled", "failed", "invalid_api_key", "session_not_found",
		"session_conflict", "request_too_large", "invalid_content_type", "invalid_request",
		"server_error", "unmatched_result", "session_terminated", "journal_limit_exceeded",
		"invalid_agent_event", "journal_rejected", "http_rejected", "unexpected_sse_content_type",
		"transport_failed", "timed_out", "connection_failed", "stream_limit", "incomplete_stream",
		"agent_protocol_failed", "agent_exited", "running", "unknown", "unsupported_model",
		"unknown_previous_response", "model_mismatch", "invalid_input", "invalid_instructions",
		"unsupported_streaming", "response_chain_busy", "pi_error", "encoding_error",
	]
}

/// Bounded queue and three 256 KiB private files. All I/O runs on a utility queue.
/// Descriptor-relative traversal refuses symlinks, foreign owners and writable ancestors
/// (except sticky system temporary directories). Leaf directories must be private.
public final class PrivateDiagnostics: @unchecked Sendable {
	public static let shared = PrivateDiagnostics(
		directory: FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(
			".mac-apper-diagnostics"))
	public let directory: URL
	private let queue = DispatchQueue(label: "private-diagnostics", qos: .utility)
	private let lock = NSLock()
	private var pending = 0
	public init(directory: URL) { self.directory = directory }
	public func record(_ record: DiagnosticRecord) {
		guard
			lock.withLock({
				if pending >= 256 { return false }
				pending += 1
				return true
			})
		else { return }
		queue.async { [self] in
			defer { lock.withLock { pending -= 1 } }
			guard
				let data = try? JSONEncoder().encode(record)
			else { return }
			try? withDirectory { fd in
				try expire(fd)
				let current = try file(fd, "current.jsonl", write: true)
				var info = stat()
				guard
					fstat(current, &info) == 0
				else {
					close(current)
					throw Failure.unsafe
				}
				if Int64(info.st_size) + Int64(data.count + 1) > 262_144 {
					close(current)
					// rename/unlink operate on directory entries, never follow their targets.
					unlinkat(fd, "previous-2.jsonl", 0)
					renameat(fd, "previous-1.jsonl", fd, "previous-2.jsonl")
					guard
						renameat(fd, "current.jsonl", fd, "previous-1.jsonl") == 0
					else { throw Failure.unsafe }
					let next = try file(fd, "current.jsonl", write: true)
					defer { close(next) }
					try append(data + Data([10]), to: next)
				} else {
					defer { close(current) }
					try append(data + Data([10]), to: current)
				}
			}
		}
	}
	public func snapshot() async -> String {
		await withCheckedContinuation { continuation in
			queue.async { [self] in
				let text = try? withDirectory { fd -> String in
					try expire(fd)
					var all = Data()
					for name in ["previous-2.jsonl", "previous-1.jsonl", "current.jsonl"] {
						guard
							let input = try? file(fd, name, write: false)
						else { continue }
						let handle = FileHandle(fileDescriptor: input, closeOnDealloc: true)
						if let bytes = try handle.read(upToCount: 262_144) { all.append(bytes) }
						try handle.close()
					}
					// Copy only re-encoded schema-validated metadata, never arbitrary file bytes.
					return all.split(separator: 10).compactMap { line -> String? in
						guard
							let record = try? JSONDecoder().decode(DiagnosticRecord.self, from: Data(line)),
							record.isSafe,
							let encoded = try? JSONEncoder().encode(record)
						else { return nil }
						return String(decoding: encoded, as: UTF8.self)
					}.joined(separator: "\n")
				}
				continuation.resume(
					returning: text ?? "Diagnostics unavailable (unsafe or inaccessible path).")
			}
		}
	}
	public func validatedDirectory() async -> URL? {
		await withCheckedContinuation { continuation in
			queue.async { [self] in
				let valid =
					(try? withDirectory { fd in
						try expire(fd)
						return true
					}) ?? false
				continuation.resume(returning: valid ? directory : nil)
			}
		}
	}
	private enum Failure: Error { case unsafe }
	private func withDirectory<T>(_ body: (Int32) throws -> T) throws -> T {
		let path = directory.path
		guard
			path.hasPrefix("/"),
			!path.contains("\0")
		else { throw Failure.unsafe }
		let parts = path.split(separator: "/")
		guard
			!parts.isEmpty,
			!parts.contains(".."),
			!parts.contains(".")
		else { throw Failure.unsafe }
		var fd = open("/", O_RDONLY | O_DIRECTORY | O_CLOEXEC)
		guard
			fd >= 0
		else { throw Failure.unsafe }
		defer { close(fd) }
		for (index, part) in parts.enumerated() {
			let name = String(part)
			if mkdirat(fd, name, 0o700) != 0 && errno != EEXIST { throw Failure.unsafe }
			let next = openat(fd, name, O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC)
			guard
				next >= 0
			else { throw Failure.unsafe }
			var info = stat()
			let leaf = index == parts.count - 1
			let valid =
				fstat(next, &info) == 0 && (info.st_uid == getuid() || (!leaf && info.st_uid == 0))
				&& (leaf
					? info.st_mode & 0o777 == 0o700
					: (info.st_mode & 0o022 == 0 || info.st_mode & 0o1000 != 0))
			guard
				valid
			else {
				close(next)
				throw Failure.unsafe
			}
			close(fd)
			fd = next
		}
		return try body(fd)
	}
	private func file(_ directory: Int32, _ name: String, write: Bool) throws -> Int32 {
		let fd = openat(
			directory, name,
			(write ? O_WRONLY | O_CREAT | O_APPEND : O_RDONLY) | O_NOFOLLOW | O_CLOEXEC | O_NONBLOCK,
			0o600)
		guard
			fd >= 0
		else { throw Failure.unsafe }
		var info = stat()
		guard
			fstat(fd, &info) == 0,
			info.st_mode & S_IFMT == S_IFREG,
			info.st_uid == getuid(),
			info.st_mode & 0o777 == 0o600,
			info.st_nlink == 1,
			info.st_size <= 262_144
		else {
			close(fd)
			throw Failure.unsafe
		}
		return fd
	}
	private func expire(_ directory: Int32) throws {
		for name in ["current.jsonl", "previous-1.jsonl", "previous-2.jsonl"] {
			var info = stat()
			guard
				fstatat(directory, name, &info, AT_SYMLINK_NOFOLLOW) == 0
			else { continue }
			guard
				info.st_mode & S_IFMT == S_IFREG,
				info.st_uid == getuid(),
				info.st_nlink == 1,
				info.st_mode & 0o777 == 0o600
			else { throw Failure.unsafe }
			#if os(Linux)
				let modified = info.st_mtim.tv_sec
			#else
				let modified = info.st_mtimespec.tv_sec
			#endif
			if Date().timeIntervalSince1970 - Double(modified) > 604_800 { unlinkat(directory, name, 0) }
		}
	}
	private func append(_ data: Data, to fd: Int32) throws {
		try data.withUnsafeBytes { bytes in
			var offset = 0
			while offset < bytes.count {
				#if os(Linux)
					let count = Glibc.write(fd, bytes.baseAddress!.advanced(by: offset), bytes.count - offset)
				#else
					let count = Darwin.write(
						fd, bytes.baseAddress!.advanced(by: offset), bytes.count - offset)
				#endif
				if count < 0 && errno == EINTR { continue }
				guard
					count > 0
				else { throw Failure.unsafe }
				offset += count
			}
		}
	}
}
