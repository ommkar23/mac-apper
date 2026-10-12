// @frontmatter:start
// Copies a deployed app into an isolated signed host, retaining its real client unless a replacement is explicitly supplied.
// @frontmatter:end
import Foundation

@MainActor public final class PackagedApplicationHost {
	private let deployedApp: URL
	private let clientExecutable: URL?
	private var directory: URL?
	private var client: URL?
	public private(set) var app: URL?

	public init(deployedApp: URL, clientExecutable: URL? = nil) {
		self.deployedApp = deployedApp
		self.clientExecutable = clientExecutable
	}

	public func prepare() throws {
		guard
			directory == nil,
			deployedApp.pathExtension == "app",
			try deployedApp.resourceValues(forKeys: [.isDirectoryKey, .isSymbolicLinkKey]).isDirectory
				== true,
			try deployedApp.resourceValues(forKeys: [.isSymbolicLinkKey]).isSymbolicLink != true
		else { throw ScenarioFailure.message("invalid deployed app") }
		if let clientExecutable {
			guard
				FileManager.default.isExecutableFile(atPath: clientExecutable.path),
				try clientExecutable.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey])
					.isRegularFile == true,
				try clientExecutable.resourceValues(forKeys: [.isSymbolicLinkKey]).isSymbolicLink != true
			else { throw ScenarioFailure.message("invalid replacement client") }
		}
		try ScenarioProcess.run(
			"/usr/bin/codesign", ["--verify", "--deep", "--strict", deployedApp.path])
		let manager = FileManager.default
		let temporary = manager.temporaryDirectory.appendingPathComponent(
			"scenario-app-host-\(UUID().uuidString)")
		let staged = temporary.appendingPathComponent("Scenario.app")
		do {
			try manager.createDirectory(
				at: temporary, withIntermediateDirectories: false,
				attributes: [.posixPermissions: 0o700])
			try manager.copyItem(at: deployedApp, to: staged)
			let contents = staged.appendingPathComponent("Contents")
			let plist = contents.appendingPathComponent("Info.plist")
			var info = try Self.plist(plist)
			guard
				let oldClient = info["CFBundleExecutable"] as? String,
				oldClient.range(of: "^[A-Za-z][A-Za-z0-9_-]{0,127}$", options: .regularExpression) != nil
			else { throw ScenarioFailure.message("invalid deployed app executable") }
			var client = contents.appendingPathComponent("MacOS/\(oldClient)")
			if let clientExecutable {
				try manager.removeItem(at: client)
				client = contents.appendingPathComponent("MacOS/\(clientExecutable.lastPathComponent)")
				try manager.copyItem(at: clientExecutable, to: client)
				info["CFBundleExecutable"] = client.lastPathComponent
				try Self.save(info, to: plist)
			}
			guard
				manager.isExecutableFile(atPath: client.path)
			else { throw ScenarioFailure.message("invalid app client") }
			guard
				let enumerator = manager.enumerator(
					at: staged,
					includingPropertiesForKeys: [.isSymbolicLinkKey], options: [])
			else { throw ScenarioFailure.message("cannot enumerate scenario app") }
			var bundles = [staged]
			var count = 0
			for case let url as URL in enumerator {
				count += 1
				guard
					count <= 4096,
					try url.resourceValues(forKeys: [.isSymbolicLinkKey]).isSymbolicLink != true
				else { throw ScenarioFailure.message("unsafe scenario app contents") }
				if ["app", "xpc"].contains(url.pathExtension) { bundles.append(url) }
			}
			for bundle in bundles.sorted(by: { $0.path.count > $1.path.count }) {
				let plist = bundle.appendingPathComponent("Contents/Info.plist")
				var info = try Self.plist(plist)
				let identifier = "com.macapper.scenario.\(UUID().uuidString.lowercased())"
				info["CFBundleIdentifier"] = identifier
				try Self.save(info, to: plist)
				try ScenarioProcess.run(
					"/usr/bin/codesign",
					["--force", "--sign", "-", "--identifier", identifier, bundle.path])
			}
			try ScenarioProcess.run("/usr/bin/codesign", ["--verify", "--deep", "--strict", staged.path])
			directory = temporary
			app = staged
			self.client = client
		} catch {
			try? manager.removeItem(at: temporary)
			throw error
		}
	}

	public func run(arguments: [String], request: Data = Data("{}".utf8), timeoutSeconds: Int = 330)
		throws -> XPCClientAdapter.Reply
	{
		guard
			let client
		else { throw ScenarioFailure.message("scenario app is not staged") }
		return try XPCClientAdapter().call(
			client, request: request, arguments: arguments,
			maxResponseBytes: 65_536, timeoutSeconds: timeoutSeconds)
	}

	public func remove() throws {
		guard
			let directory
		else { return }
		try FileManager.default.removeItem(at: directory)
		self.directory = nil
		client = nil
		app = nil
	}

	private static func plist(_ url: URL) throws -> [String: Any] {
		let values = try url.resourceValues(forKeys: [
			.isRegularFileKey, .isSymbolicLinkKey, .fileSizeKey,
		])
		guard
			values.isRegularFile == true,
			values.isSymbolicLink != true,
			let size = values.fileSize,
			size <= 65_536,
			let result = try PropertyListSerialization.propertyList(
				from: Data(contentsOf: url), format: nil) as? [String: Any]
		else { throw ScenarioFailure.message("invalid scenario app plist") }
		return result
	}

	private static func save(_ info: [String: Any], to url: URL) throws {
		try PropertyListSerialization.data(fromPropertyList: info, format: .xml, options: 0).write(
			to: url)
	}
}
