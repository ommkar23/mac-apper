// @frontmatter:start
// Allocates disposable paths under the repository's private .tmp directory and scopes child TMPDIR values.
// @frontmatter:end
import Darwin
import Foundation

public enum ProjectTemporaryDirectory {
	public static var repositoryRoot: URL {
		URL(fileURLWithPath: #filePath)
			.deletingLastPathComponent().deletingLastPathComponent()
			.deletingLastPathComponent().deletingLastPathComponent()
	}

	public static func root(project: URL = repositoryRoot) throws -> URL {
		var parent = stat()
		guard
			project.isFileURL,
			lstat(project.path, &parent) == 0,
			parent.st_mode & S_IFMT == S_IFDIR
		else {
			throw ScenarioFailure.message(
				"Temporary project root must be an existing nonlinked directory")
		}
		let directory = project.appendingPathComponent(".tmp", isDirectory: true)
		guard
			mkdir(directory.path, 0o700) == 0 || errno == EEXIST
		else { throw ScenarioFailure.message("Cannot create repository .tmp directory") }
		var info = stat()
		guard
			lstat(directory.path, &info) == 0,
			info.st_mode & S_IFMT == S_IFDIR,
			info.st_uid == getuid(),
			info.st_mode & 0o077 == 0
		else {
			throw ScenarioFailure.message(
				"Repository .tmp must be a private, owner-owned, nonlinked directory")
		}
		return directory
	}

	public static func appending(_ name: String) throws -> URL {
		guard
			!name.isEmpty,
			name != ".",
			name != "..",
			name.utf8.count <= 255,
			!name.contains("/"),
			!name.contains("\\"),
			!name.unicodeScalars.contains(where: { CharacterSet.controlCharacters.contains($0) })
		else { throw ScenarioFailure.message("Invalid repository temporary filename") }
		return try root().appendingPathComponent(name)
	}

	public static func environment(
		_ source: [String: String] = ProcessInfo.processInfo.environment
	) throws -> [String: String] {
		var result = source
		result["TMPDIR"] = try root().path + "/"
		return result
	}
}
