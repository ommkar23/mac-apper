// @frontmatter:start
// Runs swift-format and the guard-style tool in apply or check mode.
// @frontmatter:end
import Foundation
import PackagePlugin

@main struct FormatPlugin: CommandPlugin {
	func performCommand(context: PluginContext, arguments: [String]) async throws {
		let options = arguments.filter { $0 != "--allow-writing-to-package-directory" }
		guard options.isEmpty || options == ["--check"] else { throw Failure.invalidArguments }
		let root = context.package.directoryURL
		let process = Process()
		process.executableURL = URL(fileURLWithPath: "/usr/bin/xcrun")
		process.arguments =
			["swift-format", options.isEmpty ? "format" : "lint"]
			+ (options.isEmpty ? ["--in-place"] : ["--strict"])
			+ ["--recursive", "--configuration", root.appendingPathComponent(".swift-format").path]
			+ ["Package.swift", "Agent", "Scenario", "VisionCLI", "apps"].map {
				root.appendingPathComponent($0).path
			}
		try run(process)
		let tool = Process()
		tool.executableURL = try context.tool(named: "GuardFormatTool").url
		tool.arguments =
			[options.isEmpty ? "--apply" : "--check"]
			+ ["Package.swift", "Agent", "Scenario", "VisionCLI", "apps"].map {
				root.appendingPathComponent($0).path
			}
		try run(tool)
	}

	private func run(_ process: Process) throws {
		process.standardOutput = FileHandle.standardOutput
		process.standardError = FileHandle.standardError
		try process.run()
		process.waitUntilExit()
		guard process.terminationReason == .exit, process.terminationStatus == 0 else {
			throw Failure.formatFailed(process.terminationStatus)
		}
	}
}

private enum Failure: Error {
	case invalidArguments
	case formatFailed(Int32)
}
