// @frontmatter:start
// Validates scenario directory identity and audits bounded Pi metadata for the required model, thinking, and workspace scope.
// @frontmatter:end
import Darwin
import Foundation

public struct ScenarioRuntimeProfile: Codable, Equatable, Sendable {
	public let provider: String
	public let model: String
	public let thinking: String
	public static let required = Self(
		provider: "openai-codex", model: "gpt-6.1-sol", thinking: "medium")
	public init(provider: String, model: String, thinking: String) {
		self.provider = provider; self.model = model; self.thinking = thinking
	}
}

public enum SessionAuditError: Error { case invalidMetadata, wrongRuntime, wrongScope }

// Scenario evidence identity, not permission to read project contents.
// Production path validators and scenario file checks still apply.
public struct ScenarioDirectoryIdentity: Equatable {
	let device: dev_t
	let inode: ino_t
	let canonicalPath: String

	static func components(_ path: String) throws -> [String] {
		guard
			!path.isEmpty,
			path.utf8.count <= 4096,
			!path.contains("\0"),
			!path.contains("\\")
		else { throw SessionAuditError.wrongScope }
		let parts = path.split(separator: "/", omittingEmptySubsequences: false).map(String.init)
		guard
			parts.allSatisfy({ !$0.isEmpty && $0 != "." && $0 != ".." })
		else { throw SessionAuditError.wrongScope }
		return parts
	}

	private static func hasNoExtendedACL(_ value: acl_t?) -> Bool {
		guard
			let acl = value
			// Darwin reports ENOENT when an existing object has no extended ACL.
		else { return errno == ENOENT }
		defer { acl_free(UnsafeMutableRawPointer(acl)) }
		var entry: acl_entry_t?
		return acl_valid(acl) == 0 && acl_get_entry(acl, Int32(ACL_FIRST_ENTRY.rawValue), &entry) != 0
	}

	public static func read(_ path: String) throws -> Self {
		guard
			path.hasPrefix("/")
		else { throw SessionAuditError.wrongScope }
		var pending = path == "/" ? [] : try components(String(path.dropFirst()))
		var descriptor = open("/", O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC)
		guard
			descriptor >= 0
		else { throw SessionAuditError.wrongScope }
		defer { Darwin.close(descriptor) }
		var trustedAncestors = true
		var links = 0
		var info = stat()
		while true {
			guard
				fstat(descriptor, &info) == 0,
				info.st_mode & S_IFMT == S_IFDIR
			else { throw SessionAuditError.wrongScope }
			trustedAncestors =
				trustedAncestors && info.st_uid == 0 && info.st_mode & 0o022 == 0
				&& hasNoExtendedACL(acl_get_fd_np(descriptor, ACL_TYPE_EXTENDED))
			guard
				!pending.isEmpty
			else { break }
			let part = pending.removeFirst()
			var entry = stat()
			guard
				fstatat(descriptor, part, &entry, AT_SYMLINK_NOFOLLOW) == 0
			else { throw SessionAuditError.wrongScope }
			if entry.st_mode & S_IFMT == S_IFLNK {
				// Only root-controlled aliases in an entirely root-controlled ancestry.
				// Sticky/world-writable temporary roots and user/project folders end trust.
				guard
					trustedAncestors,
					entry.st_uid == 0,
					links < 16,
					hasNoExtendedACL(
						acl_get_link_np(try canonicalPath(descriptor) + "/" + part, ACL_TYPE_EXTENDED))
				else { throw SessionAuditError.wrongScope }
				links += 1
				var bytes = [UInt8](repeating: 0, count: 4096)
				let count = bytes.withUnsafeMutableBytes {
					readlinkat(descriptor, part, $0.baseAddress!, $0.count)
				}
				guard
					count > 0,
					count < bytes.count,
					let destination = String(bytes: bytes.prefix(count), encoding: .utf8)
				else { throw SessionAuditError.wrongScope }
				let absolute = destination.hasPrefix("/")
				pending = try components(absolute ? String(destination.dropFirst()) : destination) + pending
				if absolute {
					let root = open("/", O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC)
					guard
						root >= 0
					else { throw SessionAuditError.wrongScope }
					Darwin.close(descriptor)
					descriptor = root
					trustedAncestors = true
				}
			} else {
				let next = openat(descriptor, part, O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC)
				guard
					next >= 0
				else { throw SessionAuditError.wrongScope }
				Darwin.close(descriptor)
				descriptor = next
			}
		}
		return Self(
			device: info.st_dev, inode: info.st_ino, canonicalPath: try canonicalPath(descriptor))
	}

	private static func canonicalPath(_ descriptor: Int32) throws -> String {
		var canonical = [CChar](repeating: 0, count: Int(MAXPATHLEN))
		guard
			fcntl(descriptor, F_GETPATH, &canonical) == 0
		else { throw SessionAuditError.wrongScope }
		return String(
			decoding: canonical.prefix { $0 != 0 }.map { UInt8(bitPattern: $0) }, as: UTF8.self)
	}
}

public struct ScenarioSessionAudit: Sendable {
	public let profile: ScenarioRuntimeProfile
	public let userTexts: [String]
	public let assistantCount: Int

	public static func read(_ data: Data, expectedProject: String) throws -> Self {
		guard
			data.count <= 4_194_304,
			data.last == 10
		else { throw SessionAuditError.invalidMetadata }
		let lines = data.split(separator: 10)
		guard
			let first = lines.first,
			let header = try JSONSerialization.jsonObject(with: Data(first)) as? [String: Any],
			header["type"] as? String == "session",
			let cwd = header["cwd"] as? String,
			try ScenarioDirectoryIdentity.read(cwd) == ScenarioDirectoryIdentity.read(expectedProject)
		else { throw SessionAuditError.wrongScope }
		var provider: String?
		var model: String?
		var thinking: String?
		var userTexts: [String] = []
		var assistantCount = 0
		for line in lines.dropFirst() {
			guard
				line.count <= 1_048_576,
				let record = try JSONSerialization.jsonObject(with: Data(line)) as? [String: Any]
			else { throw SessionAuditError.invalidMetadata }
			switch record["type"] as? String {
			case "model_change":
				provider = record["provider"] as? String
				model = record["modelId"] as? String
			case "thinking_level_change": thinking = record["thinkingLevel"] as? String
			case "message":
				guard
					let message = record["message"] as? [String: Any]
				else { throw SessionAuditError.invalidMetadata }
				if message["role"] as? String == "assistant" {
					guard
						message["provider"] as? String == ScenarioRuntimeProfile.required.provider,
						message["model"] as? String == ScenarioRuntimeProfile.required.model
					else { throw SessionAuditError.wrongRuntime }
					assistantCount += 1
				}
				if message["role"] as? String == "user" {
					let text =
						message["content"] as? String
						?? (message["content"] as? [[String: Any]] ?? [])
						.compactMap { $0["type"] as? String == "text" ? $0["text"] as? String : nil }.joined(
							separator: "\n")
					userTexts.append(text)
				}
			default: break
			}
		}
		guard
			let provider,
			let model,
			let thinking
		else { throw SessionAuditError.invalidMetadata }
		let profile = ScenarioRuntimeProfile(provider: provider, model: model, thinking: thinking)
		guard
			profile == .required,
			assistantCount > 0
		else { throw SessionAuditError.wrongRuntime }
		return Self(profile: profile, userTexts: userTexts, assistantCount: assistantCount)
	}
}
