// @frontmatter:start
// Creates and validates trusted generated projects and commits their initial Git baseline.
// @frontmatter:end
import Foundation
import PreviewContract

public enum ScaffoldError: Error, CustomStringConvertible {
	case unsupported
	case altered(String)
	case gitFailed(String)
	public var description: String {
		switch self {
		case .unsupported:
			return
				"Unsupported scaffold version. Create a new project; existing projects are preserved and are not migrated."
		case .altered(let path):
			return
				"Protected scaffold inventory changed at \(path). Restore the trusted file or create a new project."
		case .gitFailed(let message): return "Could not create the project Git baseline: \(message)"
		}
	}
}
public enum ProjectScaffold {
	public static let manifest = BaseAppTemplate.manifest
	public static func create(under parent: URL) throws -> URL {
		let root = parent.appendingPathComponent(UUID().uuidString.lowercased())
		do {
			try FileManager.default.createDirectory(
				at: root.appendingPathComponent("dist"), withIntermediateDirectories: true,
				attributes: [.posixPermissions: 0o700])
			var files = BaseAppTemplate.extensions
			files["Info.plist"] = """
				<?xml version="1.0" encoding="UTF-8"?>
				<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
				<plist version="1.0"><dict>
				<key>CFBundleDisplayName</key><string>Generated App</string>
				<key>CFBundleName</key><string>Generated App</string>
				<key>CFBundleIdentifier</key><string>com.macapper.generated.\(root.lastPathComponent)</string>
				<key>CFBundleExecutable</key><string>ProductionApp</string>
				<key>CFBundlePackageType</key><string>APPL</string>
				<key>CFBundleVersion</key><string>1</string>
				<key>LSMinimumSystemVersion</key><string>14.0</string>
				</dict></plist>
				"""
			files[".gitignore"] = ".build/\n.swiftpm/\n.mac-apper/\ndist/\n"
			files["Sources/AppModel/AnimationIntent.swift"] = try String(
				contentsOf: Bundle.module.url(forResource: "AnimationIntent", withExtension: "swift")!,
				encoding: .utf8)
			for (path, content) in try BaseAppTemplate.protectedFiles(appID: root.lastPathComponent) {
				files[path] = content
			}
			for (path, content) in files {
				let url = root.appendingPathComponent(path)
				try FileManager.default.createDirectory(
					at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
				try content.write(to: url, atomically: true, encoding: .utf8)
			}
			try createGitBaseline(in: root)
			return root
		} catch {
			try? FileManager.default.removeItem(at: root)
			throw error
		}
	}

	private static func createGitBaseline(in root: URL) throws {
		try runGit(["-c", "init.defaultBranch=main", "init", "-q"], in: root)
		try runGit(["add", "--all"], in: root)
		try runGit(
			[
				"-c", "user.name=Mac Apper",
				"-c", "user.email=mac-apper@localhost",
				"-c", "commit.gpgsign=false",
				"-c", "core.hooksPath=/dev/null",
				"commit", "-q", "-m", "Initial Mac Apper scaffold",
			], in: root)
	}

	private static func runGit(_ arguments: [String], in root: URL) throws {
		let process = Process()
		let output = Pipe()
		process.executableURL = URL(fileURLWithPath: "/usr/bin/git")
		process.arguments = arguments
		process.currentDirectoryURL = root
		process.standardOutput = output
		process.standardError = output
		var environment = ProcessInfo.processInfo.environment
		environment["GIT_CONFIG_NOSYSTEM"] = "1"
		environment["GIT_CONFIG_GLOBAL"] = "/dev/null"
		process.environment = environment
		do { try process.run() } catch {
			throw ScaffoldError.gitFailed(String(describing: error).prefix(500).description)
		}
		process.waitUntilExit()
		let message = String(
			decoding: output.fileHandleForReading.readDataToEndOfFile().prefix(500), as: UTF8.self)
		guard
			process.terminationStatus == 0
		else {
			throw ScaffoldError.gitFailed(
				message.isEmpty ? "git exited with status \(process.terminationStatus)" : message)
		}
	}
	@discardableResult public static func validate(_ root: URL) throws -> SourceInventory {
		guard
			try FileManager.default.attributesOfItem(atPath: root.path)[.type] as? FileAttributeType
				== .typeDirectory
		else { throw WorkspaceError.symbolicLink }
		let scope = try WorkspaceScope(root: root)
		let sources = try SourceInventory.collect(root)
		guard
			sources.files["Scaffold.version"] == Data(BaseAppTemplate.version.utf8)
		else { throw ScaffoldError.unsupported }
		let inventory = try BaseAppTemplate.protectedFiles(appID: root.lastPathComponent)
		for (relative, expected) in inventory {
			guard
				sources.files[relative] == Data(expected.utf8)
			else { throw ScaffoldError.altered(relative) }
		}
		for directory in [
			"PreviewContract", "PreviewSupport", "PreviewApp", "ProductionApp", "DevExtension",
		] {
			let relative = "Sources/" + directory
			let expected = inventory.keys.filter { $0.hasPrefix(relative + "/") }.map {
				URL(fileURLWithPath: $0).lastPathComponent
			}.sorted()
			var actual: [String] = []
			try DirectoryEntries.forEach(scope.resolve(relative)) { name in
				guard
					actual.count < expected.count
				else { throw SessionError.invalidRequest }
				actual.append(name)
			}
			guard
				actual.sorted() == expected
			else { throw SessionError.invalidRequest }
		}
		_ = try scope.resolve("dist")
		return sources
	}
}
