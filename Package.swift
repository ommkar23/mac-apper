// swift-tools-version: 6.1
// @frontmatter:start
// Declares integration tests, formatting tools, and app bundle command plugins.
// @frontmatter:end
import PackageDescription

let package = Package(
	name: "AgentIntegration",
	platforms: [.macOS(.v14)],
	dependencies: [
		.package(path: "Scenario"),
		.package(url: "https://github.com/swiftlang/swift-testing.git", exact: "6.2.3"),
		.package(url: "https://github.com/swiftlang/swift-syntax.git", exact: "602.0.0"),
		.package(url: "https://github.com/SimplyDanny/SwiftLintPlugins.git", exact: "0.65.1"),
	],
	targets: [
		.testTarget(
			name: "IntegrationTests",
			dependencies: [
				.product(name: "Scenario", package: "Scenario"),
				.product(name: "Testing", package: "swift-testing"),
			]
		),
		.plugin(
			name: "FormatPlugin",
			capability: .command(
				intent: .custom(verb: "format", description: "Apply or check Swift source formatting"),
				permissions: [.writeToPackageDirectory(reason: "Format Swift source files in place")]
			),
			dependencies: ["GuardFormatTool"],
			exclude: ["Core", "Tool"]
		),
		.plugin(
			name: "LintPlugin",
			capability: .command(
				intent: .custom(verb: "lint", description: "Lint authored Swift sources")),
			dependencies: [.product(name: "SwiftLintBinary", package: "SwiftLintPlugins")]
		),
		.plugin(
			name: "BundlePlugin",
			capability: .command(
				intent: .custom(verb: "bundle", description: "Assemble and sign the app bundle")
			)
		),
		.plugin(
			name: "UnbundlePlugin",
			capability: .command(
				intent: .custom(verb: "unbundle", description: "Remove a verified owned bundle")
			)
		),
		.plugin(
			name: "CleanTestPlugin",
			capability: .command(
				intent: .custom(
					verb: "clean-test",
					description: "Test a package in a disposable SwiftPM scratch directory"))
		),
		.plugin(
			name: "SwiftLinesPlugin",
			capability: .command(
				intent: .custom(
					verb: "swift-lines",
					description: "Report authored Swift source lines and export a distribution chart"),
				permissions: [
					.writeToPackageDirectory(reason: "Export the Swift line distribution PNG to dist")
				]
			),
			dependencies: ["SwiftLinesChartTool"],
			exclude: ["ChartTool"]
		),
		.executableTarget(name: "SwiftLinesChartTool", path: "Plugins/SwiftLinesPlugin/ChartTool"),
		.executableTarget(
			name: "GuardFormatTool", dependencies: ["GuardFormatCore"],
			path: "Plugins/FormatPlugin/Tool"),
		.target(
			name: "GuardFormatCore",
			dependencies: [
				.product(name: "SwiftSyntax", package: "swift-syntax"),
				.product(name: "SwiftParser", package: "swift-syntax"),
			], path: "Plugins/FormatPlugin/Core"),
		.testTarget(
			name: "SwiftLinesPluginTests",
			dependencies: [
				"SwiftLinesChartTool", "GuardFormatCore",
				.product(name: "Scenario", package: "Scenario"),
				.product(name: "Testing", package: "swift-testing"),
			],
			path: "Plugins/SwiftLinesPluginTests"
		),
	]
)
