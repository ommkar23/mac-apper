// @frontmatter:start
// Tests format plugin wiring and Swift line chart generation and buckets.
// @frontmatter:end
import Foundation
import Testing

@Test func formattingIsAvailableAsSwiftPMCommandPlugin() throws {
	let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
		.deletingLastPathComponent().deletingLastPathComponent()
	let manifest = try String(
		contentsOf: root.appendingPathComponent("Package.swift"), encoding: .utf8)
	let plugin = try String(
		contentsOf: root.appendingPathComponent(
			"Plugins/FormatPlugin/plugin.swift"), encoding: .utf8)
	#expect(manifest.contains("verb: \"format\""))
	#expect(!manifest.contains("verb: \"format-apply\""))
	#expect(manifest.contains("verb: \"lint\""))
	#expect(plugin.contains("--in-place"))
	let lint = try String(
		contentsOf: root.appendingPathComponent(
			"Plugins/LintPlugin/plugin.swift"), encoding: .utf8)
	#expect(lint.contains("swiftlint"))
	#expect(plugin.contains("swift-format"))
	#expect(plugin.contains(".swift-format"))
	#expect(plugin.components(separatedBy: #"["Package.swift", "Agent", "Scenario", "VisionCLI", "apps"]"#).count == 3)
	let lintConfiguration = try String(contentsOf: root.appendingPathComponent(".swiftlint.yml"), encoding: .utf8)
	#expect(lintConfiguration.contains("  - VisionCLI\n"))
}
@testable import SwiftLinesChartTool

@MainActor @Test func distributionUsesTwentyLineBuckets() {
	let buckets = SwiftLinesChartTool.buckets(for: [0, 19, 40, 59, 60])
	#expect(buckets.map(\.label) == ["0–19", "20–39", "40–59", "60–79"])
	#expect(buckets.map(\.count) == [2, 0, 2, 1])
	let overflow = SwiftLinesChartTool.buckets(for: [0, 2000, 2001])
	#expect(overflow.map(\.label) == ["0–19", "2000+"])
	#expect(overflow.map(\.count) == [1, 2])
}

@Test func swiftLinesPublishesSourceDistributionAsPNG() throws {
	let repository = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
		.deletingLastPathComponent().deletingLastPathComponent()
	let fixture = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
	let scratch = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
	defer {
		try? FileManager.default.removeItem(at: fixture)
		try? FileManager.default.removeItem(at: scratch)
	}
	let manager = FileManager.default
	let plugin = fixture.appendingPathComponent("Plugins/SwiftLinesPlugin")
	let chart = plugin.appendingPathComponent("ChartTool")
	let source = fixture.appendingPathComponent("Sources/Example")
	for directory in [plugin, chart, source] {
		try manager.createDirectory(at: directory, withIntermediateDirectories: true)
	}
	try manager.copyItem(
		at: repository.appendingPathComponent("Plugins/SwiftLinesPlugin/SwiftLinesPlugin.swift"),
		to: plugin.appendingPathComponent("SwiftLinesPlugin.swift"))
	try manager.copyItem(
		at: repository.appendingPathComponent("Plugins/SwiftLinesPlugin/ChartTool/main.swift"),
		to: chart.appendingPathComponent("main.swift"))
	try "// one\n// two\n".write(
		to: source.appendingPathComponent("Two.swift"), atomically: true, encoding: .utf8)
	try "// one\n".write(
		to: source.appendingPathComponent("One.swift"), atomically: true, encoding: .utf8)
	try """
	// swift-tools-version: 6.0
	import PackageDescription
	let package = Package(name: "ChartFixture", platforms: [.macOS(.v14)], targets: [
	    .executableTarget(name: "SwiftLinesChartTool", path: "Plugins/SwiftLinesPlugin/ChartTool"),
	    .target(name: "Example"),
	    .plugin(name: "SwiftLinesPlugin", capability: .command(
	        intent: .custom(verb: "swift-lines", description: "Report Swift lines"),
	        permissions: [.writeToPackageDirectory(reason: "Export chart")]),
	        dependencies: ["SwiftLinesChartTool"], exclude: ["ChartTool"]),
	])
	""".write(to: fixture.appendingPathComponent("Package.swift"), atomically: true, encoding: .utf8)
	let process = Process()
	process.executableURL = URL(fileURLWithPath: "/usr/bin/xcrun")
	process.arguments = [
		"swift", "package", "--package-path", fixture.path,
		"--scratch-path", scratch.path,
		"--allow-writing-to-package-directory", "swift-lines",
	]
	let output = Pipe()
	process.standardOutput = output
	process.standardError = output
	try process.run()
	let text = String(decoding: output.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
	process.waitUntilExit()
	#expect(process.terminationStatus == 0, "\(text)")
	#expect(text.contains("Swift files: 2"), "\(text)")
	let png = try Data(
		contentsOf: fixture.appendingPathComponent("dist/swift-lines-distribution.png"))
	#expect(png.starts(with: [137, 80, 78, 71, 13, 10, 26, 10]))
}
