// @frontmatter:start
// Finds authored Swift files and applies or checks parsed guard formatting.
// @frontmatter:end
import Foundation
import GuardFormatCore

@main enum GuardFormatTool {
	static func main() throws {
		let arguments = Array(CommandLine.arguments.dropFirst())
		guard arguments.count >= 2, ["--apply", "--check"].contains(arguments[0]) else {
			throw Failure.invalidArguments
		}
		let manager = FileManager.default
		var files: [URL] = []
		for path in arguments.dropFirst() {
			let url = URL(fileURLWithPath: path)
			var isDirectory: ObjCBool = false
			guard manager.fileExists(atPath: url.path, isDirectory: &isDirectory) else {
				throw Failure.missingPath(path)
			}
			if isDirectory.boolValue {
				guard
					let enumerator = manager.enumerator(
						at: url,
						includingPropertiesForKeys: [.isRegularFileKey, .isSymbolicLinkKey])
				else {
					throw Failure.missingPath(path)
				}
				for case let file as URL in enumerator {
					if [".build", ".git", ".swiftpm", "dist", "HostBuilds", "Generated"].contains(
						file.lastPathComponent)
					{
						enumerator.skipDescendants()
						continue
					}
					let values = try file.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey])
					if values.isSymbolicLink == true { enumerator.skipDescendants(); continue }
					if values.isRegularFile == true, file.pathExtension == "swift" { files.append(file) }
				}
			} else if url.pathExtension == "swift" {
				files.append(url)
			}
		}
		var changed = 0
		for file in files.sorted(by: { $0.path < $1.path }) {
			let source = try String(contentsOf: file, encoding: .utf8)
			let formatted = formatGuards(source)
			guard formatted != source else { continue }
			changed += 1
			if arguments[0] == "--apply" {
				try formatted.write(to: file, atomically: true, encoding: .utf8)
			} else {
				fputs("Guard style: \(file.path)\n", stderr)
			}
		}
		guard changed == 0 || arguments[0] == "--apply" else {
			throw Failure.needsFormatting(changed)
		}
	}
}

private enum Failure: Error {
	case invalidArguments
	case missingPath(String)
	case needsFormatting(Int)
}
