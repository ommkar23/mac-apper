// @frontmatter:start
// Runs strict SwiftLint over the authored project sources.
// @frontmatter:end
import Foundation
import PackagePlugin

@main struct LintPlugin: CommandPlugin {
	func performCommand(context: PluginContext, arguments: [String]) async throws {
		guard arguments.isEmpty else { throw Failure.invalidArguments }
		let root = context.package.directoryURL
		let process = Process()
		process.executableURL = try context.tool(named: "swiftlint").url
		process.arguments = [
			"lint", "--strict", "--no-cache", "--config",
			root.appendingPathComponent(".swiftlint.yml").path, root.path,
		]
		process.environment = ProcessInfo.processInfo.environment.merging([
			"TOOLCHAIN_DIR": "/Library/Developer/CommandLineTools"
		]) { _, newer in newer }
		process.standardOutput = FileHandle.standardOutput
		process.standardError = FileHandle.standardError
		try process.run()
		process.waitUntilExit()
		guard process.terminationReason == .exit, process.terminationStatus == 0 else {
			throw Failure.lintFailed(process.terminationStatus)
		}
	}
}

private enum Failure: Error {
	case invalidArguments
	case lintFailed(Int32)
}
