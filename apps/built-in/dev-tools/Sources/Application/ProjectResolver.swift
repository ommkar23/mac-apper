// @frontmatter:start
// Resolves each tool call to a project with validated manifest, package, and path scope.
// @frontmatter:end
import Foundation

public struct ResolvedProject: Sendable {
	public let scope: ProjectScope
	public let manifest: ProjectManifest
}

/// IDs select project directories; they are not authentication.
public actor ProjectResolver {
	private let projectsRoot: URL
	public init(projectsRoot: URL) { self.projectsRoot = projectsRoot }

	public func lookup(projectRoot: String, projectID: String, sessionID: String) throws
		-> ResolvedProject
	{
		guard
			UUID(uuidString: sessionID) != nil,
			sessionID.utf8.count == 36
		else { throw ProjectValidationError.invalidIdentifier }
		let project = try inspect(projectID)
		let selected = URL(fileURLWithPath: projectRoot).standardizedFileURL
		guard
			projectRoot.hasPrefix("/"),
			projectRoot.utf8.count <= 4096,
			!projectRoot.split(separator: "/").contains(where: { $0 == "." || $0 == ".." }),
			selected.resolvingSymlinksInPath() == project.scope.root
		else { throw ProjectValidationError.invalidPath }
		let package = try project.scope.resolve("Package.swift")
		let attributes = try FileManager.default.attributesOfItem(atPath: package.path)
		guard
			attributes[.type] as? FileAttributeType == .typeRegular,
			(attributes[.size] as? NSNumber)?.intValue ?? Int.max <= 1_048_576
		else { throw ProjectValidationError.invalidManifest }
		return project
	}

	private func inspect(_ projectID: String) throws -> ResolvedProject {
		guard
			projectID.utf8.count == 36,
			UUID(uuidString: projectID) != nil,
			projectID == projectID.lowercased()
		else { throw ProjectValidationError.invalidIdentifier }
		let base = try ProjectScope(root: projectsRoot)
		let root = try base.resolve(projectID)
		let scope = try ProjectScope(root: root)
		let manifestURL = try scope.resolve("app-manifest.json")
		let attributes = try FileManager.default.attributesOfItem(atPath: manifestURL.path)
		guard
			attributes[.type] as? FileAttributeType == .typeRegular,
			(attributes[.size] as? NSNumber)?.intValue ?? Int.max <= 16_384
		else { throw ProjectValidationError.invalidManifest }
		let file = try FileHandle(forReadingFrom: manifestURL)
		defer { try? file.close() }
		let data = try file.read(upToCount: 16_385) ?? Data()
		let manifest = try ProjectManifest.decode(data)
		guard
			manifest.appID == projectID
		else { throw ProjectValidationError.invalidManifest }
		return ResolvedProject(scope: scope, manifest: manifest)
	}
}
