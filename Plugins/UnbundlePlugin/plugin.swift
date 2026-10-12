// @frontmatter:start
// Removes only the validated, tool-owned Mac Apper app bundle directory.
// @frontmatter:end
import Foundation
import PackagePlugin

@main struct UnbundlePlugin: CommandPlugin {
	private static let usage = "Usage: swift package unbundle app | --help"

	func performCommand(context: PluginContext, arguments: [String]) async throws {
		if arguments == ["--help"] { print(Self.usage); return }
		guard arguments == ["app"] else { throw Failure.invalidArguments }
		let relative = "Bundles/app/Info.plist"
		let expectedID = "com.ommkar.mac-apper"
		let plist = context.package.directoryURL.appendingPathComponent(relative)
		let values = try PropertyListSerialization.propertyList(
			from: Data(contentsOf: plist), format: nil) as? [String: Any]
		guard let id = values?["CFBundleIdentifier"] as? String,
			id == expectedID
		else { throw Failure.invalidIdentifier }
		let dist = context.package.directoryURL.appendingPathComponent("dist")
		let owned = dist.appendingPathComponent(id)
		guard !dist.isSymbolicLink, !owned.isSymbolicLink else {
			throw Failure.unsafePath(owned.path)
		}
		guard FileManager.default.fileExists(atPath: owned.path) else {
			print("No bundle to remove: \(owned.path)")
			return
		}
		let marker = owned.appendingPathComponent(".bundle-owner")
		let attributes = try marker.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey])
		guard attributes.isRegularFile == true, attributes.isSymbolicLink != true,
			try String(contentsOf: marker, encoding: .utf8) == id + "\n"
		else { throw Failure.unsafePath(owned.path) }
		let process = Process()
		process.executableURL = URL(fileURLWithPath: "/bin/ps")
		process.arguments = ["-axo", "command="]
		let output = Pipe()
		process.standardOutput = output
		try process.run()
		let commands = output.fileHandleForReading.readDataToEndOfFile()
		process.waitUntilExit()
		guard process.terminationStatus == 0, commands.count <= 2_000_000,
			!String(decoding: commands, as: UTF8.self).split(separator: "\n").contains(where: {
				$0.trimmingCharacters(in: .whitespaces).hasPrefix(owned.path + "/")
			})
		else { throw Failure.bundleInUse(owned.path) }
		try FileManager.default.removeItem(at: owned)
		print("Removed bundle and build output: \(owned.path)")
	}
}

private extension URL {
	var isSymbolicLink: Bool {
		(try? resourceValues(forKeys: [.isSymbolicLinkKey]).isSymbolicLink) == true
	}
}

private enum Failure: Error {
	case invalidArguments
	case invalidIdentifier
	case unsafePath(String)
	case bundleInUse(String)
}
