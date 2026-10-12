// @frontmatter:start
// Resolves standalone Swift 6.4 tools for scenario preparation, compiler evidence, and matching test-loader selection.
// @frontmatter:end
import Foundation

public enum SwiftToolchain {
	public static func executable(_ tool: String) throws -> URL {
		guard
			["swift", "swiftc"].contains(tool)
		else { throw ScenarioFailure.message("invalid Swift tool") }
		let url = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(
			"Library/Developer/Toolchains/swift-6.4.0-RELEASE.xctoolchain/usr/bin/\(tool)")
		guard
			FileManager.default.isExecutableFile(atPath: url.path)
		else { throw ScenarioFailure.message("standalone Swift 6.4.0 is not installed") }
		return url
	}
}
