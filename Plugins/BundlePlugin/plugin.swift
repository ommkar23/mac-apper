// @frontmatter:start
// Assembles and verifies the signed Mac Apper app bundle.
// @frontmatter:end
import Foundation
import PackagePlugin

@main struct BundlePlugin: CommandPlugin {
	private static let usage = "Usage: swift package bundle app | --help"
	private var swiftBin: URL {
		FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(
			"Library/Developer/Toolchains/swift-6.4.0-RELEASE.xctoolchain/usr/bin")
	}

	func performCommand(context: PluginContext, arguments: [String]) async throws {
		if arguments == ["--help"] { print(Self.usage); return }
		let root = context.package.directoryURL
		guard
			arguments == ["app"]
		else { throw Failure.invalidArguments }
		let manager = FileManager.default
		guard
			manager.isExecutableFile(atPath: swiftBin.appendingPathComponent("swift").path),
			manager.isExecutableFile(atPath: swiftBin.appendingPathComponent("swiftc").path)
		else { throw Failure.unsafePath("Install standalone Swift 6.4.0 before bundling") }
		let dist = root.appendingPathComponent("dist")
		let plist = root.appendingPathComponent("Bundles/app/Info.plist")
		let metadata =
			try PropertyListSerialization.propertyList(
				from: Data(contentsOf: plist), format: nil) as? [String: Any]
		let manifest = try String(
			contentsOf: root.appendingPathComponent(
				"Bundles/app/Bundle.yaml"), encoding: .utf8)
		guard
			manifest
				== "schema_version: 1\nagents: [chat, create]\nproviders: [dev-tools]\nclient_product: AgentMacosClient\n",
			metadata?["CFBundleIdentifier"] as? String == "com.ommkar.mac-apper"
		else { throw Failure.invalidArguments }
		let owned = dist.appendingPathComponent("com.ommkar.mac-apper")
		let build = owned.appendingPathComponent("build")
		let generated = build.appendingPathComponent("generated")
		let clientBuild = build.appendingPathComponent("agent-client")
		let serviceBuild = build.appendingPathComponent("agent-xpc-service")
		let app = owned.appendingPathComponent("Mac Apper.app")
		let service = app.appendingPathComponent("Contents/XPCServices/AgentXPCService.xpc")
		for path in [dist, owned, build, app] where path.isSymbolicLink {
			throw Failure.unsafePath(path.path)
		}
		if manager.fileExists(atPath: owned.path) {
			let marker = owned.appendingPathComponent(".bundle-owner")
			guard
				!marker.isSymbolicLink,
				(try? String(contentsOf: marker, encoding: .utf8)) == "com.ommkar.mac-apper\n"
			else { throw Failure.unsafePath(owned.path) }
			guard
				try !runningExecutable(under: owned)
			else { throw Failure.bundleInUse(owned.path) }
			try manager.removeItem(at: owned)
		}
		try manager.createDirectory(at: owned, withIntermediateDirectories: true)
		try "com.ommkar.mac-apper\n".write(
			to: owned.appendingPathComponent(".bundle-owner"), atomically: true, encoding: .utf8)
		let identity = ProcessInfo.processInfo.environment["MAC_APPER_SIGNING_IDENTITY"] ?? "-"
		try run(
			swiftBin.appendingPathComponent("swift").path,
			[
				root.appendingPathComponent(
					"Scripts/generate-integration.swift"
				).path, generated.path,
			])
		for (product, scratch) in [
			("AgentMacosClient", clientBuild), ("AgentApplication", serviceBuild),
		] {
			try run(
				swiftBin.appendingPathComponent("swift").path,
				[
					"build", "--package-path",
					root.appendingPathComponent("Agent").path, "-c", "release", "--product", product,
					"--scratch-path", scratch.path, "-j", "2",
				])
		}
		let macOS = app.appendingPathComponent("Contents/MacOS")
		let resources = app.appendingPathComponent("Contents/Resources")
		let serviceMacOS = service.appendingPathComponent("Contents/MacOS")
		let serviceResources = service.appendingPathComponent("Contents/Resources")
		for path in [macOS, resources, serviceMacOS, serviceResources] {
			try manager.createDirectory(at: path, withIntermediateDirectories: true)
		}
		try copy(
			clientBuild.appendingPathComponent("release/AgentMacosClient"),
			to: macOS.appendingPathComponent("AgentMacosClient"))
		try copy(
			plist,
			to: app.appendingPathComponent("Contents/Info.plist"))
		try copy(
			generated.appendingPathComponent("IntegrationCatalog.json"),
			to: resources.appendingPathComponent("IntegrationCatalog.json"))
		try copy(
			root.appendingPathComponent("Agent/Extensions"),
			to: resources.appendingPathComponent("AgentExtensions"))
		try copy(
			serviceBuild.appendingPathComponent("release/Agent_AgentApplication.bundle"),
			to: resources.appendingPathComponent("Agent_AgentApplication.bundle"))
		try copy(
			serviceBuild.appendingPathComponent("release/Agent_AgentApplication.bundle"),
			to: serviceResources.appendingPathComponent("Agent_AgentApplication.bundle"))
		try copy(
			serviceBuild.appendingPathComponent("release/AgentApplication"),
			to: serviceMacOS.appendingPathComponent("AgentApplication"))
		try copy(
			root.appendingPathComponent("Agent/Resources/AgentXPCService-Info.plist"),
			to: service.appendingPathComponent("Contents/Info.plist"))
		for executable in [
			macOS.appendingPathComponent("AgentMacosClient"),
			serviceMacOS.appendingPathComponent("AgentApplication"),
		] {
			try manager.setAttributes([.posixPermissions: 0o755], ofItemAtPath: executable.path)
		}
		try run(
			swiftBin.appendingPathComponent("swift").path,
			[
				root.appendingPathComponent(
					"Scripts/package-providers.swift"
				).path, root.path, build.path, app.path, identity,
			])
		try run("/usr/bin/codesign", ["--force", "--sign", identity, service.path])
		try run("/usr/bin/codesign", ["--force", "--sign", identity, app.path])
		try run("/usr/bin/codesign", ["--verify", "--deep", "--strict", "--verbose=2", app.path])
		try run("/usr/bin/plutil", ["-lint", app.appendingPathComponent("Contents/Info.plist").path])
		print(
			"Artifact: \(app.path)\nCatalog: \(resources.appendingPathComponent("IntegrationCatalog.json").path)"
		)
	}

	private func runningExecutable(under directory: URL) throws -> Bool {
		let process = Process()
		process.executableURL = URL(fileURLWithPath: "/bin/ps")
		process.arguments = ["-axo", "command="]
		let output = Pipe()
		process.standardOutput = output
		try process.run()
		let commands = output.fileHandleForReading.readDataToEndOfFile()
		process.waitUntilExit()
		guard
			process.terminationStatus == 0,
			commands.count <= 2_000_000
		else { throw Failure.unsafePath(directory.path) }
		return String(decoding: commands, as: UTF8.self).split(separator: "\n").contains {
			$0.trimmingCharacters(in: .whitespaces).hasPrefix(directory.path + "/")
		}
	}

	private func copy(_ source: URL, to destination: URL) throws {
		try FileManager.default.copyItem(at: source, to: destination)
	}

	private func run(_ executable: String, _ arguments: [String]) throws {
		let process = Process()
		process.executableURL = URL(fileURLWithPath: executable)
		process.arguments = arguments
		var environment = ProcessInfo.processInfo.environment
		environment["SWIFT_EXEC"] = swiftBin.appendingPathComponent("swiftc").path
		process.environment = environment
		process.standardOutput = FileHandle.standardOutput
		process.standardError = FileHandle.standardError
		try process.run()
		process.waitUntilExit()
		guard
			process.terminationReason == .exit,
			process.terminationStatus == 0
		else { throw Failure.commandFailed(executable, process.terminationStatus) }
	}
}

private extension URL {
	var isSymbolicLink: Bool {
		(try? resourceValues(forKeys: [.isSymbolicLinkKey]).isSymbolicLink) == true
	}
}

private enum Failure: Error {
	case invalidArguments
	case unsafePath(String)
	case bundleInUse(String)
	case commandFailed(String, Int32)
}
