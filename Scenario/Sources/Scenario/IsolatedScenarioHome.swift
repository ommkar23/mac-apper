// @frontmatter:start
// Owns a private scenario home, scoped environment, compiler link, and selectively staged private credentials with explicit cleanup gating.
// @frontmatter:end
import Darwin
import Foundation

public final class IsolatedScenarioHome {
	public let directory: URL
	private var credentials: [URL] = []
	public var environment: [String: String] {
		[
			"HOME": directory.path, "CFFIXED_USER_HOME": directory.path,
			"TMPDIR": directory.deletingLastPathComponent().path + "/",
		]
	}
	public init() throws {
		directory = try ProjectTemporaryDirectory.appending("scenario-home-\(UUID().uuidString)")
		try FileManager.default.createDirectory(
			at: directory, withIntermediateDirectories: false, attributes: [.posixPermissions: 0o700])
	}
	public func linkInstalledToolchain() throws {
		let installed = try SwiftToolchain.executable("swift").deletingLastPathComponent()
			.deletingLastPathComponent().deletingLastPathComponent()
		let parent = try privateDirectory("Library/Developer/Toolchains")
		try FileManager.default.createSymbolicLink(
			at: parent.appendingPathComponent(installed.lastPathComponent), withDestinationURL: installed)
	}
	public func privateDirectory(_ relative: String) throws -> URL {
		let parts = try components(relative)
		var current = directory
		for part in parts {
			current.appendPathComponent(part)
			if !FileManager.default.fileExists(atPath: current.path) {
				try FileManager.default.createDirectory(
					at: current, withIntermediateDirectories: false, attributes: [.posixPermissions: 0o700])
			}
			let values = try current.resourceValues(forKeys: [.isDirectoryKey, .isSymbolicLinkKey])
			guard
				values.isDirectory == true,
				values.isSymbolicLink != true
			else { throw ScenarioFailure.message("unsafe scenario directory") }
		}
		return current
	}
	private func components(_ relative: String) throws -> [String] {
		let parts = relative.split(separator: "/", omittingEmptySubsequences: false).map(String.init)
		guard
			!parts.isEmpty,
			parts.allSatisfy({ !$0.isEmpty && $0 != "." && $0 != ".." && !$0.contains("\\") })
		else { throw ScenarioFailure.message("invalid scenario relative path") }
		return parts
	}
	// Reads only an explicitly authorized private JSON file, never its surrounding config directory.
	@discardableResult public func stageCredentialEntry(
		from source: URL, key: String, relativePath: String,
		project: ([String: Any]) throws -> [String: Any] = { $0 }
	) throws -> URL {
		let parts = try components(relativePath)
		guard
			source.isFileURL,
			source.path.hasPrefix("/")
		else { throw ScenarioFailure.message("invalid credential source") }
		let sourceParts = try components(String(source.path.dropFirst()))
		var parentFD = open("/", O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC)
		guard
			parentFD >= 0
		else { throw ScenarioFailure.message("credential root unavailable") }
		defer { Darwin.close(parentFD) }
		for part in sourceParts.dropLast() {
			let next = openat(parentFD, part, O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC)
			guard
				next >= 0
			else { throw ScenarioFailure.message("unsafe credential ancestor") }
			Darwin.close(parentFD)
			parentFD = next
		}
		let fd = openat(parentFD, sourceParts.last!, O_RDONLY | O_NOFOLLOW | O_CLOEXEC)
		guard
			fd >= 0
		else { throw ScenarioFailure.message("private credential unavailable") }
		defer { Darwin.close(fd) }
		var info = stat()
		guard
			fstat(fd, &info) == 0,
			info.st_mode & S_IFMT == S_IFREG,
			info.st_uid == getuid(),
			info.st_mode & 0o077 == 0,
			info.st_size > 0,
			info.st_size <= 262144
		else { throw ScenarioFailure.message("credential must be a bounded owner-only regular file") }
		var bytes = [UInt8](repeating: 0, count: Int(info.st_size))
		var offset = 0
		while offset < bytes.count {
			let remaining = bytes.count - offset
			let count = bytes.withUnsafeMutableBytes {
				Darwin.read(fd, $0.baseAddress!.advanced(by: offset), remaining)
			}
			guard
				count > 0
			else { throw ScenarioFailure.message("credential read failed") }
			offset += count
		}
		guard
			let entries = (try? JSONSerialization.jsonObject(with: Data(bytes))) as? [String: Any],
			let selected = entries[key] as? [String: Any],
			!selected.isEmpty
		else { throw ScenarioFailure.message("required credential entry unavailable") }
		let parent =
			parts.count == 1 ? directory : try privateDirectory(parts.dropLast().joined(separator: "/"))
		let target = parent.appendingPathComponent(parts.last!)
		let output = open(target.path, O_WRONLY | O_CREAT | O_EXCL | O_NOFOLLOW | O_CLOEXEC, 0o600)
		guard
			output >= 0
		else { throw ScenarioFailure.message("credential destination unavailable") }
		let handle = FileHandle(fileDescriptor: output, closeOnDealloc: true)
		credentials.append(target)
		try handle.write(
			contentsOf: JSONSerialization.data(withJSONObject: [key: try project(selected)]))
		try handle.close()
		return target
	}
	public func scrubCredentials() throws {
		for path in credentials where FileManager.default.fileExists(atPath: path.path) {
			try FileManager.default.removeItem(at: path)
		}
		credentials.removeAll()
	}
	@discardableResult public func finishHost(
		cleanupConfirmed: Bool, removeFixtures: Bool, stopServices: () throws -> Void,
		removeHost: () throws -> Void
	) throws -> Bool {
		guard
			cleanupConfirmed
		else { throw ScenarioFailure.message("inner cleanup unconfirmed; retain host/home") }
		try stopServices()
		try scrubCredentials()
		guard
			removeFixtures
		else { return false }
		try removeHost()
		try remove(cleanupConfirmed: true)
		return true
	}
	public func remove(cleanupConfirmed: Bool) throws {
		guard
			cleanupConfirmed
		else { throw ScenarioFailure.message("cleanup unconfirmed; retain scenario home") }
		try scrubCredentials()
		if FileManager.default.fileExists(atPath: directory.path) {
			try FileManager.default.removeItem(at: directory)
		}
	}
}
