// @frontmatter:start
// Selects the standalone Swift 6.4 compiler for production commands while retaining injected tools and CLT SDK discovery.
// @frontmatter:end
import Foundation

struct SwiftToolchain {
	enum Failure: Error, CustomStringConvertible {
		case missingExecutable(URL)

		var description: String {
			switch self {
			case .missingExecutable(let url):
				return
					"Required standalone Swift 6.4.0 executable is missing or not executable: \(url.path). Install standalone Swift 6.4.0; CLT fallback is disabled."
			}
		}
	}

	struct Command {
		let executable: URL
		let arguments: [String]
		let environment: [String: String]
	}

	static func compactDiagnostics(_ output: String) -> String {
		// Swift Build appends long compiler invocations after the actionable errors.
		output.components(separatedBy: "\n").map { line in
			let trimmed = line.trimmingCharacters(in: .whitespaces)
			if trimmed.hasPrefix("/") || trimmed.hasPrefix("builtin-SwiftDriver "),
				trimmed.contains("/swift-frontend ") || trimmed.contains("/swiftc ")
			{
				return "[compiler invocation omitted]"
			}
			return line
		}.joined(separator: "\n")
	}

	static var bin: URL {
		FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(
			"Library/Developer/Toolchains/swift-6.4.0-RELEASE.xctoolchain/usr/bin")
	}

	static func command(
		executable: URL, arguments: [String], environment: [String: String], bin: URL = Self.bin
	) throws -> Command {
		guard
			executable.path == "/usr/bin/xcrun",
			let tool = arguments.first,
			["swift", "swiftc"].contains(tool)
		else { return Command(executable: executable, arguments: arguments, environment: environment) }
		for required in ["swift", "swiftc"] {
			let url = bin.appendingPathComponent(required)
			guard
				FileManager.default.isExecutableFile(atPath: url.path)
			else { throw Failure.missingExecutable(url) }
		}
		var selected = environment
		selected["SWIFT_EXEC"] = bin.appendingPathComponent("swiftc").path
		return Command(
			executable: bin.appendingPathComponent(tool), arguments: Array(arguments.dropFirst()),
			environment: selected)
	}
}
