// @frontmatter:start
// Resolves project-relative paths while rejecting traversal and linked path components.
// @frontmatter:end
import Foundation

/// A scope is a safety boundary, not a sandbox for compiled native code.
public struct ProjectScope: Sendable {
	public let root: URL

	public init(root: URL) throws {
		guard
			root.isFileURL
		else { throw ProjectValidationError.invalidPath }
		// Canonicalize system aliases such as /var, but never accept an aliased project root.
		let attributes = try FileManager.default.attributesOfItem(atPath: root.path)
		guard
			attributes[.type] as? FileAttributeType == .typeDirectory
		else { throw ProjectValidationError.invalidPath }
		self.root = root.resolvingSymlinksInPath().standardizedFileURL
	}

	public func resolve(_ relative: String) throws -> URL {
		let components = relative.split(separator: "/", omittingEmptySubsequences: false)
		guard
			relative.utf8.count <= 1_024,
			!relative.contains("\\"),
			!relative.unicodeScalars.contains(where: { $0.value < 32 }),
			components.allSatisfy({ !$0.isEmpty && $0 != "." && $0 != ".." })
		else { throw ProjectValidationError.invalidPath }
		var result = root
		for component in components {
			result.appendPathComponent(String(component))
			if let attributes = try? FileManager.default.attributesOfItem(atPath: result.path),
				attributes[.type] as? FileAttributeType == .typeSymbolicLink
			{
				throw ProjectValidationError.invalidPath
			}
		}
		return result
	}
}
