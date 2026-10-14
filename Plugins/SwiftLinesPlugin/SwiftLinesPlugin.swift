// @frontmatter:start
// Counts authored Swift source lines and exports a distribution chart.
// @frontmatter:end
import Foundation
import PackagePlugin

@main struct SwiftLinesPlugin: CommandPlugin {
	func performCommand(context: PluginContext, arguments: [String]) async throws {
		guard
			arguments.isEmpty
		else { throw ReportError.unexpectedArguments }
		try report(context: context, root: context.package.directoryURL.standardizedFileURL)
	}

	private func report(context: PluginContext, root: URL) throws {
		let manager = FileManager.default
		let keys: Set<URLResourceKey> = [.isDirectoryKey, .isRegularFileKey, .isSymbolicLinkKey]
		let excluded: Set<String> = [
			".tmp", ".build", ".git", ".swiftpm", "dist", "HostBuilds", "Generated",
			"Tests", "Fixtures", "Plugins", "Scripts",
		]
		var sourceDirectories: [URL] = []
		var enumerationError: (any Error)?
		guard
			let directories = manager.enumerator(
				at: root, includingPropertiesForKeys: Array(keys), options: [.skipsHiddenFiles],
				errorHandler: { _, error in
					enumerationError = error; return false
				}
			)
		else { throw ReportError.cannotEnumerate(root.path) }
		for case let url as URL in directories {
			let values = try url.resourceValues(forKeys: keys)
			if values.isSymbolicLink == true || excluded.contains(url.lastPathComponent) {
				if values.isDirectory == true { directories.skipDescendants() }
				continue
			}
			guard
				values.isDirectory == true
			else { continue }
			if url.lastPathComponent == "Sources" {
				sourceDirectories.append(url)
				directories.skipDescendants()
			}
		}
		if let enumerationError { throw enumerationError }
		var rows: [(path: String, lines: Int)] = []
		let rootPrefix = root.path + "/"
		for directory in sourceDirectories {
			guard
				let files = manager.enumerator(
					at: directory, includingPropertiesForKeys: Array(keys), options: [.skipsHiddenFiles],
					errorHandler: { _, error in
						enumerationError = error; return false
					}
				)
			else { throw ReportError.cannotEnumerate(directory.path) }
			for case let url as URL in files {
				let values = try url.resourceValues(forKeys: keys)
				if values.isSymbolicLink == true || excluded.contains(url.lastPathComponent) {
					if values.isDirectory == true { files.skipDescendants() }
					continue
				}
				guard
					values.isRegularFile == true,
					url.pathExtension == "swift"
				else { continue }
				let path = url.standardizedFileURL.path
				guard
					path.hasPrefix(rootPrefix)
				else { continue }
				rows.append((String(path.dropFirst(rootPrefix.count)), try lineCount(at: url)))
			}
			if let enumerationError { throw enumerationError }
		}
		rows.sort { $0.path < $1.path }
		print("Swift files: \(rows.count)")
		print("Total lines: \(rows.reduce(0) { $0 + $1.lines })")
		print("File\tLines")
		for row in rows { print("\(row.path)\t\(row.lines)") }
		let dist = root.appendingPathComponent("dist", isDirectory: true)
		if let attributes = try? manager.attributesOfItem(atPath: dist.path) {
			guard
				attributes[.type] as? FileAttributeType == .typeDirectory
			else { throw ReportError.unsafeDestination }
		} else {
			try manager.createDirectory(at: dist, withIntermediateDirectories: false)
		}
		let output = dist.appendingPathComponent("swift-lines-distribution.png")
		if let attributes = try? manager.attributesOfItem(atPath: output.path) {
			guard
				attributes[.type] as? FileAttributeType == .typeRegular
			else { throw ReportError.unsafeDestination }
		}
		let input = context.pluginWorkDirectoryURL.appendingPathComponent("swift-lines.json")
		try JSONEncoder().encode(rows.map(\.lines)).write(to: input, options: .atomic)
		let process = Process()
		process.executableURL = try context.tool(named: "SwiftLinesChartTool").url
		process.arguments = [input.path, output.path]
		let diagnostics = Pipe()
		process.standardError = diagnostics
		try process.run()
		let errorText = String(
			decoding: diagnostics.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
		process.waitUntilExit()
		guard
			process.terminationStatus == 0
		else { throw ReportError.chartFailed(errorText) }
		print("Chart: \(output.path)")
	}

	private func lineCount(at url: URL) throws -> Int {
		let handle = try FileHandle(forReadingFrom: url)
		defer { try? handle.close() }
		var lines = 0
		var lastByte: UInt8?
		while let data = try handle.read(upToCount: 65_536), !data.isEmpty {
			lines += data.reduce(0) { $0 + ($1 == 10 ? 1 : 0) }
			lastByte = data.last
		}
		return lines + (lastByte == nil || lastByte == 10 ? 0 : 1)
	}
}

private enum ReportError: Error, CustomStringConvertible {
	case unexpectedArguments
	case cannotEnumerate(String)
	case unsafeDestination
	case chartFailed(String)

	var description: String {
		switch self {
		case .unexpectedArguments:
			"usage: swift package --allow-writing-to-package-directory swift-lines"
		case .cannotEnumerate(let path): "cannot enumerate \(path)"
		case .unsafeDestination: "chart destination is not a regular file inside a real dist directory"
		case .chartFailed(let detail): "chart export failed: \(detail)"
		}
	}
}
