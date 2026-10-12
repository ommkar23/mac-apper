// swift-tools-version: 6.1
import PackageDescription

let package = Package(
	name: "OpenXPCGenerator",
	platforms: [.macOS(.v14)],
	products: [
		.library(name: "OpenXPCSpecification", targets: ["OpenXPCSpecification"]),
		.plugin(name: "OpenXPCBuildPlugin", targets: ["OpenXPCBuildPlugin"]),
	],
	dependencies: [
		.package(url: "https://github.com/jpsim/Yams.git", from: "6.0.0"),
		.package(url: "https://github.com/swiftlang/swift-testing.git", exact: "6.2.3"),
	],
	targets: [
		.target(
			name: "OpenXPCSpecification",
			dependencies: [.product(name: "Yams", package: "Yams")],
			resources: [.copy("Schemas/openxpc.schema.json"), .copy("Schemas/openxpc-gen.schema.json")]
		),
		.plugin(
			name: "OpenXPCBuildPlugin",
			capability: .buildTool(),
			dependencies: ["OpenXPCGenerator"]
		),
		.executableTarget(name: "OpenXPCGenerator", dependencies: ["OpenXPCSpecification"]),
		.testTarget(
			name: "OpenXPCSpecificationTests",
			dependencies: [
				"OpenXPCSpecification",
				.product(name: "Testing", package: "swift-testing"),
			]
		),
	]
)
