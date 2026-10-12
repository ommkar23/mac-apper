import Foundation
import OpenXPCSpecification

@main enum OpenXPCGenerator {
	static func main() throws {
		let arguments = Array(CommandLine.arguments.dropFirst())
		let queryMode = arguments.count == 4 && arguments[0] == "--mode"
		guard
			queryMode || arguments.count == 4 || arguments.count == 5
		else { throw GeneratorError.invalidArguments }
		let specPath = arguments[queryMode ? 1 : 0]
		let configPath = arguments[queryMode ? 2 : 1]
		let target = arguments[queryMode ? 3 : 2]
		let input = URL(fileURLWithPath: specPath)
		let config = URL(fileURLWithPath: configPath)
		for file in [input, config] {
			let attributes = try file.resourceValues(forKeys: [
				.isRegularFileKey, .isSymbolicLinkKey, .fileSizeKey,
			])
			guard
				attributes.isRegularFile == true,
				attributes.isSymbolicLink != true,
				let size = attributes.fileSize,
				size <= 65_536
			else { throw GeneratorError.invalidSpec }
		}
		let spec = try OpenXPCSpecification(
			contractYAML: String(contentsOf: input, encoding: .utf8),
			generationYAML: String(contentsOf: config, encoding: .utf8))
		guard
			let mode = spec.generation(for: target)
		else { throw GeneratorError.unknownTarget(target) }
		if queryMode {
			print(mode.rawValue)
			return
		}
		guard
			mode != .agentClient || arguments.count == 5
		else { throw GeneratorError.invalidArguments }
		let output = URL(fileURLWithPath: arguments[3])
		let files = try OpenXPCSourceGenerator.generate(
			spec: spec, target: target, serviceDispatch: .controllers)
		if arguments.count == 5 {
			let extensionSource = files.piExtension ?? ""
			let extensionOutput = URL(fileURLWithPath: arguments[4])
			guard
				extensionOutput != output
			else { throw GeneratorError.invalidArguments }
			try extensionSource.write(to: extensionOutput, atomically: true, encoding: .utf8)
		}
		try files.swift.write(to: output, atomically: true, encoding: .utf8)
	}
}

private enum GeneratorError: Error {
	case invalidArguments
	case invalidSpec
	case unknownTarget(String)
}
