// swift-tools-version: 6.0
// @frontmatter:start
// Declares the reusable Scenario library and Swift tests.
// @frontmatter:end
import PackageDescription

let package = Package(
	name: "Scenario",
	platforms: [.macOS(.v14)],
	products: [
		.library(name: "Scenario", targets: ["Scenario"]),
		.library(name: "ScenarioTesting", targets: ["ScenarioTesting"]),
	],
	dependencies: [
		.package(url: "https://github.com/swiftlang/swift-testing.git", exact: "6.2.3")
	],
	targets: [
		.target(name: "Scenario"),
		.target(
			name: "ScenarioTesting",
			dependencies: ["Scenario", .product(name: "Testing", package: "swift-testing")]),
		.testTarget(
			name: "ScenarioTestingTests",
			dependencies: ["ScenarioTesting", .product(name: "Testing", package: "swift-testing")]),
		.testTarget(
			name: "ScenarioTests",
			dependencies: ["Scenario", .product(name: "Testing", package: "swift-testing")]
		),
	]
)
