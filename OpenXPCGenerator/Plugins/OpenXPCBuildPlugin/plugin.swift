import Foundation
import PackagePlugin

@main struct OpenXPCBuildPlugin: BuildToolPlugin {
	func createBuildCommands(context: PluginContext, target: Target) throws -> [Command] {
		let pointer = target.directoryURL.appendingPathComponent("OpenXPC.specpath")
		var spec = context.package.directoryURL.appendingPathComponent("OpenXPC.yaml")
		var inputs: [URL] = []
		if FileManager.default.fileExists(atPath: pointer.path) {
			let relative = try String(contentsOf: pointer, encoding: .utf8)
				.trimmingCharacters(in: .whitespacesAndNewlines)
			guard
				relative.utf8.count <= 512,
				!relative.hasPrefix("/"),
				relative.split(separator: "/").allSatisfy({ $0 != ".." && !$0.isEmpty })
			else { throw PluginError.invalidSpec }
			spec = context.package.directoryURL.appendingPathComponent(relative)
			inputs.append(pointer)
		}
		let generation = spec.deletingLastPathComponent().appendingPathComponent("OpenXPCGen.yaml")
		for file in [spec, generation] {
			let attributes = try file.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey])
			guard
				attributes.isRegularFile == true,
				attributes.isSymbolicLink != true
			else { throw PluginError.invalidSpec }
		}
		let generator = try context.tool(named: "OpenXPCGenerator").url
		// Executable dependencies are not available during Swift Build planning.
		// Declare both outputs; non-agent targets receive an inert empty resource.
		let output = context.pluginWorkDirectoryURL.appendingPathComponent("OpenXPCGenerated.swift")
		let extensionFile = context.pluginWorkDirectoryURL.appendingPathComponent("Extension.ts")
		let arguments = [spec.path, generation.path, target.name, output.path, extensionFile.path]
		return [
			.buildCommand(
				displayName:
					"Generate OpenXPC for \(target.name)",
				executable: generator,
				arguments: arguments,
				inputFiles: inputs + [spec, generation],
				outputFiles: [output, extensionFile]
			)
		]
	}
}

private enum PluginError: Error { case invalidSpec }
