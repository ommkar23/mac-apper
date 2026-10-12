// @frontmatter:start
// Discovers chat and app projects with their sessions and built-app metadata.
// @frontmatter:end
import Foundation

public enum WorkspaceLibrary {
	public static func chatProject(in root: URL) -> URL {
		root.appendingPathComponent(".chat", isDirectory: true)
	}

	public static func discover(in root: URL) throws -> [WorkspaceGroup] {
		let chat = chatProject(in: root)
		var result = [
			WorkspaceGroup(
				project: chat, title: "Chat", isChatOnly: true, app: nil,
				sessions: (try? ChatSessionCatalog.discover(in: chat)) ?? [])
		]
		guard
			FileManager.default.fileExists(atPath: root.path)
		else { return result }
		let apps = try BuiltAppCatalog.discover(in: root)
		let children = try FileManager.default.contentsOfDirectory(
			at: root, includingPropertiesForKeys: [.isDirectoryKey], options: [.skipsHiddenFiles])
		for project in children.sorted(by: { $0.lastPathComponent < $1.lastPathComponent }) {
			guard
				UUID(uuidString: project.lastPathComponent) != nil,
				try FileManager.default.attributesOfItem(atPath: project.path)[.type] as? FileAttributeType
					== .typeDirectory
			else { continue }
			let sessions = (try? ChatSessionCatalog.discover(in: project)) ?? []
			let app = apps.first { $0.projectName == project.lastPathComponent }
			let settingsName = try? projectAppName(project)
			result.append(
				WorkspaceGroup(
					project: project, title: settingsName ?? app?.name ?? project.lastPathComponent,
					isChatOnly: false, app: app, sessions: sessions))
		}
		return result
	}

	private static func projectAppName(_ project: URL) throws -> String {
		let file = project.appendingPathComponent("Info.plist")
		let values = try file.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey])
		guard
			values.isRegularFile == true,
			values.isSymbolicLink != true
		else { throw WorkspaceError.invalidPath }
		guard
			let info = NSDictionary(contentsOf: file),
			let name = info["CFBundleDisplayName"] as? String
		else { throw WorkspaceError.invalidPath }
		return try AppName.sanitize(name)
	}
}
