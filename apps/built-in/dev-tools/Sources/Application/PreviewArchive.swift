// @frontmatter:start
// Saves validated preview bytes in private persistent project/session folders using nonlinked directory descriptors and exclusive timestamped filenames.
// @frontmatter:end
import Darwin
import Foundation

enum PreviewArchive {
	enum Failure: Error { case invalidData, invalidTimestamp, filesystem(Int32), collisionLimit }

	static func save(
		_ data: Data, projectsRoot: URL, projectID: UUID, sessionID: UUID, timestamp: Date = Date()
	) throws -> URL {
		guard
			!data.isEmpty,
			data.count <= 2_097_152
		else { throw Failure.invalidData }
		let microseconds = timestamp.timeIntervalSince1970 * 1_000_000
		guard
			microseconds.isFinite,
			microseconds >= 0,
			microseconds < Double(Int64.max) - 1024
		else { throw Failure.invalidTimestamp }
		let base = Int64(microseconds.rounded(.down))
		var directory = open(projectsRoot.path, O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC)
		guard
			directory >= 0
		else { throw Failure.filesystem(errno) }
		defer { close(directory) }
		// Validate the configured root's actual pathname before creating archive entries.
		var archivePath = try canonicalURL(for: directory, directory: true).path
		for component in [
			"previews", projectID.uuidString.lowercased(), sessionID.uuidString.lowercased(),
		] {
			guard
				mkdirat(directory, component, 0o700) == 0 || errno == EEXIST
			else { throw Failure.filesystem(errno) }
			let child = openat(directory, component, O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC)
			guard
				child >= 0
			else { throw Failure.filesystem(errno) }
			close(directory)
			directory = child
			archivePath += "/\(component)"
		}
		for attempt in 0..<100 {
			let name = "preview-\(base + Int64(attempt)).png"
			let file = openat(
				directory, name, O_WRONLY | O_CREAT | O_EXCL | O_NOFOLLOW | O_CLOEXEC, 0o600)
			if file < 0 {
				if errno == EEXIST { continue }
				throw Failure.filesystem(errno)
			}
			var complete = false
			defer {
				close(file)
				if !complete { unlinkat(directory, name, 0) }
			}
			try data.withUnsafeBytes { bytes in
				guard
					let baseAddress = bytes.baseAddress
				else { throw Failure.invalidData }
				var offset = 0
				while offset < bytes.count {
					let count = Darwin.write(file, baseAddress.advanced(by: offset), bytes.count - offset)
					if count < 0 && errno == EINTR { continue }
					guard
						count > 0
					else { throw Failure.filesystem(errno) }
					offset += count
				}
			}
			guard
				fsync(file) == 0
			else { throw Failure.filesystem(errno) }
			let review = try canonicalURL(for: file, directory: false)
			guard
				review.path == "\(archivePath)/\(name)"
			else { throw Failure.filesystem(EINVAL) }
			complete = true
			return review
		}
		throw Failure.collisionLimit
	}

	/// Foundation's symlink resolution can abbreviate /private/tmp back to /tmp.
	/// Use kernel identity, then reopen every component without following links.
	/// This is a point-in-time check, not protection against later replacement.
	private static func canonicalURL(for descriptor: Int32, directory: Bool) throws -> URL {
		var buffer = [CChar](repeating: 0, count: Int(MAXPATHLEN))
		guard
			fcntl(descriptor, F_GETPATH, &buffer) == 0
		else { throw Failure.filesystem(errno) }
		let path = String(cString: buffer)
		let components = path.split(separator: "/", omittingEmptySubsequences: false).dropFirst()
		guard
			path.hasPrefix("/"),
			path.utf8.count <= 4096,
			!path.unicodeScalars.contains(where: CharacterSet.controlCharacters.contains),
			!components.isEmpty,
			components.allSatisfy({ !$0.isEmpty && $0 != "." && $0 != ".." })
		else { throw Failure.filesystem(EINVAL) }
		var current = open("/", O_RDONLY | O_DIRECTORY | O_CLOEXEC)
		guard
			current >= 0
		else { throw Failure.filesystem(errno) }
		defer { close(current) }
		for (index, component) in components.enumerated() {
			let isDirectory = directory || index < components.count - 1
			let child = openat(
				current, String(component),
				O_RDONLY | O_NONBLOCK | O_NOFOLLOW | O_CLOEXEC | (isDirectory ? O_DIRECTORY : 0))
			guard
				child >= 0
			else { throw Failure.filesystem(errno) }
			close(current)
			current = child
		}
		var original = stat(), reopened = stat()
		guard
			fstat(descriptor, &original) == 0,
			fstat(current, &reopened) == 0
		else { throw Failure.filesystem(errno) }
		guard
			original.st_dev == reopened.st_dev,
			original.st_ino == reopened.st_ino,
			reopened.st_mode & S_IFMT == (directory ? S_IFDIR : S_IFREG)
		else { throw Failure.filesystem(EINVAL) }
		// Do not resolve or standardize this URL: preserve the kernel's spelling.
		let url = URL(fileURLWithPath: path)
		guard
			url.path == path
		else { throw Failure.filesystem(EINVAL) }
		return url
	}
}
