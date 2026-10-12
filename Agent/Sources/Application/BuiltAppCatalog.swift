// @frontmatter:start
// Discovers complete production app bundles under UUID project output directories.
// @frontmatter:end
import Foundation

public enum BuiltAppCatalog {
	public static func discover(in projectsRoot: URL) throws -> [BuiltApp] {
		guard
			isDirectory(projectsRoot)
		else { return [] }
		let projects = try FileManager.default.contentsOfDirectory(
			at: projectsRoot,
			includingPropertiesForKeys: [.isDirectoryKey, .isSymbolicLinkKey],
			options: [.skipsHiddenFiles]
		)

		let outputRoot = projectsRoot.appendingPathComponent("output", isDirectory: true)
		return projects.compactMap { project in
			guard
				isDirectory(project),
				UUID(uuidString: project.lastPathComponent) != nil
			else { return nil }
			let projectOutput = outputRoot.appendingPathComponent(
				project.lastPathComponent, isDirectory: true)
			guard
				isDirectory(projectOutput),
				let bundle = try? FileManager.default.contentsOfDirectory(
					at: projectOutput, includingPropertiesForKeys: [.isDirectoryKey, .isSymbolicLinkKey],
					options: [.skipsHiddenFiles]
				).first(where: { $0.pathExtension == "app" && isDirectory($0) })
			else { return nil }
			let contents = bundle.appendingPathComponent("Contents", isDirectory: true)
			let executable = contents.appendingPathComponent("MacOS/ProductionApp")
			let infoPlist = contents.appendingPathComponent("Info.plist")
			guard
				isDirectory(bundle),
				isDirectory(contents),
				isRegularFile(infoPlist),
				isRegularFile(executable),
				FileManager.default.isExecutableFile(atPath: executable.path),
				let name = displayName(from: infoPlist),
				!name.isEmpty
			else { return nil }
			return BuiltApp(name: name, projectName: project.lastPathComponent, bundleURL: bundle)
		}
		.sorted {
			$0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending
		}
	}

	private static func displayName(from infoPlist: URL) -> String? {
		guard
			let data = try? Data(contentsOf: infoPlist),
			let plist = try? PropertyListSerialization.propertyList(from: data, format: nil)
				as? [String: Any]
		else { return nil }
		return (plist["CFBundleDisplayName"] as? String) ?? (plist["CFBundleName"] as? String)
	}

	private static func isDirectory(_ url: URL) -> Bool {
		guard
			let values = try? url.resourceValues(forKeys: [.isDirectoryKey, .isSymbolicLinkKey])
		else { return false }
		return values.isDirectory == true && values.isSymbolicLink != true
	}

	private static func isRegularFile(_ url: URL) -> Bool {
		guard
			let values = try? url.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey])
		else { return false }
		return values.isRegularFile == true && values.isSymbolicLink != true
	}
}
