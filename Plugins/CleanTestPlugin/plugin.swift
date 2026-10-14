// @frontmatter:start
// Runs selected package tests in a disposable, private SwiftPM scratch directory.
// @frontmatter:end
import Darwin
import Foundation
import PackagePlugin

@main struct CleanTestPlugin: CommandPlugin {
	func performCommand(context: PluginContext, arguments: [String]) async throws {
		guard
			let package = arguments.first,
			[
				".", "Agent", "Scenario", "apps/built-in/dev-tools",
			].contains(package),
			arguments.count == 1 || (arguments.count == 3 && arguments[1] == "--filter")
		else { throw Failure.invalidArguments }
		let manager = FileManager.default
		let temporary = context.package.directoryURL.appendingPathComponent(".tmp", isDirectory: true)
		if !manager.fileExists(atPath: temporary.path) {
			try manager.createDirectory(
				at: temporary, withIntermediateDirectories: false, attributes: [.posixPermissions: 0o700])
		}
		let values = try temporary.resourceValues(forKeys: [.isDirectoryKey, .isSymbolicLinkKey])
		let attributes = try manager.attributesOfItem(atPath: temporary.path)
		guard
			values.isDirectory == true,
			values.isSymbolicLink != true,
			(attributes[.posixPermissions] as? NSNumber)?.intValue == 0o700,
			(attributes[.ownerAccountID] as? NSNumber)?.uint32Value == getuid()
		else { throw Failure.unsafeTemporaryRoot }
		let scratch = temporary.appendingPathComponent("mac-apper-test.\(UUID().uuidString)")
		try manager.createDirectory(
			at: scratch, withIntermediateDirectories: false,
			attributes: [.posixPermissions: 0o700])
		defer { try? manager.removeItem(at: scratch) }
		let process = Process()
		let bin = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(
			"Library/Developer/Toolchains/swift-6.4.0-RELEASE.xctoolchain/usr/bin")
		process.executableURL = bin.appendingPathComponent("swift")
		var environment = ProcessInfo.processInfo.environment
		environment["SWIFT_EXEC"] = bin.appendingPathComponent("swiftc").path
		environment["TMPDIR"] = temporary.path + "/"
		process.environment = environment
		process.arguments =
			[
				"test", "--package-path",
				context.package.directoryURL.appendingPathComponent(package).path,
				"--scratch-path", scratch.path, "-j", "2",
			] + Array(arguments.dropFirst())
		process.standardOutput = FileHandle.standardOutput
		process.standardError = FileHandle.standardError
		try process.run()
		process.waitUntilExit()
		guard
			process.terminationReason == .exit,
			process.terminationStatus == 0
		else { throw Failure.testFailed(process.terminationStatus) }
	}
}

private enum Failure: Error {
	case invalidArguments
	case unsafeTemporaryRoot
	case testFailed(Int32)
}
