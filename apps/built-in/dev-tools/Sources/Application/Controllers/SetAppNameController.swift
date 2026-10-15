// @frontmatter:start
// Sets scoped project branding with code-point sanitation and bounded atomic plist replacement.
// @frontmatter:end
import Darwin
import Foundation

private enum SetAppNameFailure: Error {
	case invalidName, invalidMetadata
}

struct SetAppNameController: OpenXPCSet_app_nameController {
	private let projects: ProjectResolver
	private let gate: DevToolsOperationGate

	init(projects: ProjectResolver, gate: DevToolsOperationGate) {
		self.projects = projects
		self.gate = gate
	}

	func handle(_ projectID: UUID, _ sessionID: UUID, _ request: SetAppNameRequest) async throws
		-> SetAppNameResult
	{
		let project = try await projects.lookup(
			projectRoot: request.projectRoot,
			projectID: projectID.uuidString.lowercased(), sessionID: sessionID.uuidString)
		return try await gate.run {
			let name = try Self.sanitize(request.name)
			let result = try SetAppNameResult(summary: "App name set to \(name).", name: name)
			try Task.checkCancellation()
			try Self.update(scope: project.scope, name: name)
			return result
		}
	}

	private static func sanitize(_ input: String) throws -> String {
		// Match the former TypeScript sanitizer, including ECMAScript whitespace, not
		// Foundation's broader control/whitespace sets or Swift grapheme counting.
		let cleaned = input.unicodeScalars.map { scalar -> String in
			let value = scalar.value
			let whitespace =
				(0x09...0x0D).contains(value) || value == 0x20 || value == 0xA0
				|| value == 0x1680 || (0x2000...0x200A).contains(value)
				|| value == 0x2028 || value == 0x2029 || value == 0x202F
				|| value == 0x205F || value == 0x3000 || value == 0xFEFF
			if value < 32 || value == 127 || scalar == "/" || scalar == "\\" || scalar == ":"
				|| whitespace
			{
				return " "
			}
			return String(scalar)
		}.joined()
		var name = cleaned.split(separator: " ").joined(separator: " ")
		while name.lowercased().hasSuffix(".app") {
			name.removeLast(4)
			while name.hasSuffix(" ") { name.removeLast() }
		}
		guard
			!name.isEmpty,
			!name.hasPrefix("."),
			name.unicodeScalars.count <= 64
		else { throw SetAppNameFailure.invalidName }
		return name
	}

	private static func update(scope: ProjectScope, name: String) throws {
		_ = try scope.resolve("Info.plist")
		let directory = open(scope.root.path, O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC)
		guard
			directory >= 0
		else { throw SetAppNameFailure.invalidMetadata }
		defer { close(directory) }
		let source = openat(directory, "Info.plist", O_RDONLY | O_NOFOLLOW | O_NONBLOCK | O_CLOEXEC)
		guard
			source >= 0
		else { throw SetAppNameFailure.invalidMetadata }
		defer { close(source) }
		var original = stat()
		guard
			fstat(source, &original) == 0,
			(original.st_mode & S_IFMT) == S_IFREG,
			original.st_size > 0,
			original.st_size <= DevelopmentBranding.maximumPlistBytes
		else { throw SetAppNameFailure.invalidMetadata }
		var data = Data()
		var buffer = [UInt8](repeating: 0, count: 4096)
		while true {
			let count = Darwin.read(source, &buffer, buffer.count)
			if count < 0 && errno == EINTR { continue }
			guard
				count >= 0,
				data.count + count <= DevelopmentBranding.maximumPlistBytes
			else { throw SetAppNameFailure.invalidMetadata }
			if count == 0 { break }
			data.append(contentsOf: buffer.prefix(count))
		}
		var format = PropertyListSerialization.PropertyListFormat.xml
		guard
			var plist = try PropertyListSerialization.propertyList(
				from: data, options: [], format: &format) as? [String: Any]
		else { throw SetAppNameFailure.invalidMetadata }
		plist["CFBundleDisplayName"] = name
		plist["CFBundleName"] = name
		let updated = try PropertyListSerialization.data(
			fromPropertyList: plist, format: format, options: 0)
		guard
			updated.count <= DevelopmentBranding.maximumPlistBytes
		else { throw SetAppNameFailure.invalidMetadata }
		try replace(updated, directory: directory, original: original)
	}

	private static func replace(_ data: Data, directory: Int32, original: stat) throws {
		let temporary = ".mac-apper-name-\(UUID().uuidString.lowercased()).plist"
		let destination = openat(
			directory, temporary, O_WRONLY | O_CREAT | O_EXCL | O_NOFOLLOW | O_CLOEXEC, 0o600)
		guard
			destination >= 0
		else { throw SetAppNameFailure.invalidMetadata }
		defer {
			close(destination)
			unlinkat(directory, temporary, 0)
		}
		try data.withUnsafeBytes { bytes in
			var offset = 0
			while offset < bytes.count {
				let count = Darwin.write(
					destination, bytes.baseAddress!.advanced(by: offset), bytes.count - offset)
				if count < 0 && errno == EINTR { continue }
				guard
					count > 0
				else { throw SetAppNameFailure.invalidMetadata }
				offset += count
			}
		}
		var current = stat()
		// Reject an observed replacement. This check and rename are not an atomic
		// compare-and-swap against hostile concurrent project writers.
		guard
			fsync(destination) == 0,
			fstatat(directory, "Info.plist", &current, AT_SYMLINK_NOFOLLOW) == 0,
			(current.st_mode & S_IFMT) == S_IFREG,
			current.st_dev == original.st_dev,
			current.st_ino == original.st_ino,
			current.st_size == original.st_size,
			current.st_mtimespec.tv_sec == original.st_mtimespec.tv_sec,
			current.st_mtimespec.tv_nsec == original.st_mtimespec.tv_nsec
		else { throw SetAppNameFailure.invalidMetadata }
		try Task.checkCancellation()
		guard
			renameat(directory, temporary, directory, "Info.plist") == 0
		else { throw SetAppNameFailure.invalidMetadata }
	}
}
