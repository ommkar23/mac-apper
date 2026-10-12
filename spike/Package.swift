// swift-tools-version: 6.4
import PackageDescription

let package = Package(
	name: "ImageRendererSpike",
	platforms: [.macOS(.v14)],
	products: [.executable(name: "render-spike", targets: ["RenderSpike"])],
	targets: [
		.target(name: "SpikeFixtures", resources: [.copy("Resources/checker.png")]),
		.executableTarget(name: "RenderSpike", dependencies: ["SpikeFixtures"]),
		.testTarget(name: "SpikeTests", dependencies: ["SpikeFixtures"]),
	]
)
