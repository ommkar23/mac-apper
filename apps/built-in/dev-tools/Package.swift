// swift-tools-version: 6.1
// @frontmatter:start
// Declares DevTools' generated OpenXPC service and Pi client with their unit tests.
// @frontmatter:end
import PackageDescription

let package = Package(
	name: "DevTools",
	platforms: [.macOS(.v14)],
	products: [
		.executable(name: "DevToolsApplication", targets: ["DevToolsApplication"]),
		.executable(name: "DevToolsTerminalClient", targets: ["DevToolsTerminalClient"]),
	],
	dependencies: [
		.package(path: "../../../OpenXPCGenerator"),
		.package(path: "../../../Scenario"),
		.package(url: "https://github.com/swiftlang/swift-testing.git", exact: "6.2.3"),
	],
	targets: [
		.executableTarget(
			name: "DevToolsApplication",
			path: "Sources/Application",
			resources: [.copy("Resources/PreviewRenderer.swift")],
			plugins: [.plugin(name: "OpenXPCBuildPlugin", package: "OpenXPCGenerator")]
		),
		.executableTarget(
			name: "DevToolsTerminalClient",
			path: "Sources/AgentClient",
			plugins: [.plugin(name: "OpenXPCBuildPlugin", package: "OpenXPCGenerator")]
		),
		.testTarget(
			name: "DevToolsContractTests",
			dependencies: [
				.product(name: "OpenXPCSpecification", package: "OpenXPCGenerator"),
				.product(name: "Testing", package: "swift-testing"),
			]
		),
		.testTarget(
			name: "DevToolsTests",
			dependencies: [
				"DevToolsApplication",
				.product(name: "Testing", package: "swift-testing"),
			]
		),
		.testTarget(
			name: "DevToolsScenarioTests",
			dependencies: [
				"DevToolsApplication", "DevToolsTerminalClient", "Scenario",
				.product(name: "Testing", package: "swift-testing"),
			],
			path: "Tests/DevToolsScenarioTests",
			resources: [.copy("Resources/PreviewToolHarness.ts")]
		),
		.testTarget(
			name: "DevToolsXPCServiceTests",
			dependencies: [
				"DevToolsApplication",
				.product(name: "Testing", package: "swift-testing"),
			]
		),
	]
)
