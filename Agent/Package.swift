// swift-tools-version: 6.1
// @frontmatter:start
// Declares Agent executables, shared models, OpenXPC code generation, and test targets.
// @frontmatter:end
import PackageDescription

let package = Package(
	name: "Agent",
	platforms: [.macOS(.v14)],
	products: [
		.executable(name: "AgentMacosClient", targets: ["AgentMacosClient"]),
		.executable(name: "AgentApplication", targets: ["AgentApplication"]),
	],
	dependencies: [
		.package(path: "../OpenXPCGenerator"),
		.package(path: "../Scenario"),
		.package(url: "https://github.com/swiftlang/swift-testing.git", exact: "6.2.3"),
		.package(url: "https://github.com/SimplyDanny/SwiftLintPlugins.git", exact: "0.65.1"),
	],
	targets: [
		.target(name: "PreviewContract"),
		.target(name: "PortableAnimation"),
		.target(
			name: "AgentMacosClientModel", dependencies: [],
			path: "Sources/MacOSClient/Model",
			plugins: [.plugin(name: "OpenXPCBuildPlugin", package: "OpenXPCGenerator")]
		),
		.executableTarget(
			name: "AgentApplication",
			dependencies: [
				"PreviewContract",
				"PortableAnimation",
			],
			path: "Sources/Application",
			resources: [
				.copy("Resources/PreviewProtocol.swift"),
				.copy("Resources/AnimationIntent.swift"),
				.copy("Templates/DevExtension"),
			],
			plugins: [.plugin(name: "OpenXPCBuildPlugin", package: "OpenXPCGenerator")]
		),
		.executableTarget(
			name: "AgentMacosClient",
			dependencies: ["AgentMacosClientModel"],
			path: "Sources/MacOSClient",
			exclude: ["Model"]
		),
		.target(name: "AgentScenarioSupport", path: "Tests/AgentScenarioSupport"),
		.testTarget(
			name: "AgentScenarioTests",
			dependencies: [
				"AgentScenarioSupport", "AgentMacosClient", "AgentMacosClientModel",
				.product(name: "Scenario", package: "Scenario"),
				.product(name: "ScenarioTesting", package: "Scenario"),
				.product(name: "Testing", package: "swift-testing"),
			],
			exclude: ["HTView/README.md"]
		),
		.testTarget(
			name: "AgentApplicationTests",
			dependencies: [
				"AgentApplication",
				.product(name: "Scenario", package: "Scenario"),
				.product(name: "Testing", package: "swift-testing"),
			]
		),
		.testTarget(
			name: "AgentMacosClientModelTests",
			dependencies: [
				"AgentMacosClientModel",
				.product(name: "Testing", package: "swift-testing"),
			]
		),
		.testTarget(
			name: "AgentMacosClientTests",
			dependencies: [
				"AgentMacosClient",
				.product(name: "Scenario", package: "Scenario"),
				.product(name: "Testing", package: "swift-testing"),
			]
		),
		.testTarget(
			name: "AgentTests",
			dependencies: [
				"AgentApplication",
				.product(name: "Scenario", package: "Scenario"),
				"AgentMacosClient",
				"AgentMacosClientModel",
				"PreviewContract",
				"PortableAnimation",
				.product(name: "Testing", package: "swift-testing"),
			]
		),
	]
)
