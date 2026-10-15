// @frontmatter:start
// Prepares the optional scenario VisionCLI resource with injectable configuration and command execution.
// @frontmatter:end
import Darwin
import Foundation
import Scenario

enum AgentVisionPreparation {
	static func resource(
		includeVision: Bool, root: URL, environment: [String: String],
		envFile: () throws -> URL,
		run: (URL, [String]) throws -> Void
	) throws -> TestHostResource? {
		guard
			includeVision
		else { return nil }
		let executable: URL
		if let products = environment["AGENT_VISION_PRODUCTS"] {
			executable = try explicitExecutable(products)
		} else {
			let package = root.appendingPathComponent("VisionCLI")
			try run(
				URL(fileURLWithPath: "/usr/bin/xcrun"),
				["swift", "build", "--package-path", package.path, "-c", "release"])
			executable = package.appendingPathComponent(".build/release/vision-cli")
		}
		try run(executable, ["check-config", "--env-file", try envFile().path])
		return TestHostResource(source: executable, relativePath: "VisionCLI/vision-cli")
	}

	private static func explicitExecutable(_ products: String) throws -> URL {
		let components = products.split(separator: "/", omittingEmptySubsequences: false)
		guard
			products.hasPrefix("/"),
			components.count > 1,
			components.dropFirst().allSatisfy({ !$0.isEmpty && $0 != "." && $0 != ".." }),
			!products.contains("\\"),
			!products.unicodeScalars.contains(where: { CharacterSet.controlCharacters.contains($0) })
		else { throw ScenarioFailure.message("Invalid AGENT_VISION_PRODUCTS absolute directory") }
		var current = ""
		for component in components.dropFirst() {
			current += "/" + component
			var info = stat()
			guard
				lstat(current, &info) == 0,
				info.st_mode & S_IFMT == S_IFDIR
			else {
				throw ScenarioFailure.message(
					"AGENT_VISION_PRODUCTS requires nonlinked directory ancestors")
			}
		}
		let executable = URL(fileURLWithPath: products).appendingPathComponent("vision-cli")
		var info = stat()
		guard
			lstat(executable.path, &info) == 0,
			info.st_mode & S_IFMT == S_IFREG,
			FileManager.default.isExecutableFile(atPath: executable.path)
		else {
			throw ScenarioFailure.message(
				"AGENT_VISION_PRODUCTS requires a regular nonlinked executable vision-cli")
		}
		return executable
	}
}
