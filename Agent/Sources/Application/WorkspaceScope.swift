// @frontmatter:start
// Resolves relative project paths while rejecting traversal, hidden components, and symlinks.
// @frontmatter:end
import Foundation

public enum WorkspaceError: Error, Sendable {
	case invalidRoot
	case invalidPath
	case symbolicLink
}

public struct WorkspaceScope: Sendable {
	public let root: URL

	public init(root: URL) throws {
		var directory: ObjCBool = false
		guard
			root.isFileURL,
			FileManager.default.fileExists(atPath: root.path, isDirectory: &directory),
			directory.boolValue
		else { throw WorkspaceError.invalidRoot }
		self.root = root.resolvingSymlinksInPath().standardizedFileURL
	}

	public func resolve(_ relativePath: String) throws -> URL {
		let parts = relativePath.split(separator: "/", omittingEmptySubsequences: false)
		guard
			!relativePath.isEmpty,
			relativePath.utf8.count <= 1_024,
			!relativePath.contains("\0"),
			!relativePath.contains("\\"),
			parts.allSatisfy({ !$0.isEmpty && !$0.hasPrefix(".") })
		else { throw WorkspaceError.invalidPath }
		var result = root
		for part in parts {
			result.appendPathComponent(String(part))
			if let attributes = try? FileManager.default.attributesOfItem(atPath: result.path),
				attributes[.type] as? FileAttributeType == .typeSymbolicLink
			{
				throw WorkspaceError.symbolicLink
			}
		}
		guard
			result.standardizedFileURL.path.hasPrefix(root.path + "/")
		else { throw WorkspaceError.invalidPath }
		return result
	}
}
