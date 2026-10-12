// @frontmatter:start
// Declares the standalone macOS vision verification executable, reusable core, and offline tests.
// @frontmatter:end
// swift-tools-version: 6.0
import PackageDescription

let package = Package(
	name: "VisionCLI",
	platforms: [.macOS(.v14)],
	products: [.executable(name: "vision-cli", targets: ["VisionCLI"])],
	dependencies: [.package(url: "https://github.com/swiftlang/swift-testing.git", exact: "6.2.3")],
	targets: [
		.target(name: "VisionCore"),
		.executableTarget(name: "VisionCLI", dependencies: ["VisionCore"]),
		.testTarget(
			name: "VisionCoreTests",
			dependencies: ["VisionCore", .product(name: "Testing", package: "swift-testing")]),
	])
