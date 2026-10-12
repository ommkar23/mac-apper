// @frontmatter:start
// Verifies Swift 6.4 compilation and development launch through the packaged DevTools generated client and service.
// @frontmatter:end
import Darwin
import Foundation
import Scenario
import Testing

@Test @MainActor func devToolsToolchainBuildRunScenario() async throws {
	let projects = DevToolsScenarioProjects()
	let host = try DevToolsScenarioInputs.host()
	let fixture = try projects.create()
	defer { try? projects.remove(); try? host.remove() }
	let manifest = """
		// swift-tools-version: 6.0
		import PackageDescription
		let package = Package(name: "ToolchainFixture", platforms: [.macOS(.v14)], targets: [
		    .executableTarget(name: "ProductionApp")
		])
		"""
	try manifest.write(
		to: fixture.url.appendingPathComponent("Package.swift"), atomically: true, encoding: .utf8)
	let source = fixture.url.appendingPathComponent("Sources/ProductionApp/main.swift")
	try FileManager.default.createDirectory(
		at: source.deletingLastPathComponent(), withIntermediateDirectories: true)
	try """
	#if compiler(<6.4)
	#error("Swift 6.4 is required")
	#endif
	import Foundation
	let marker = URL(fileURLWithPath: FileManager.default.currentDirectoryPath).appendingPathComponent("run-pid")
	try String(ProcessInfo.processInfo.processIdentifier).write(to: marker, atomically: true, encoding: .utf8)
	Thread.sleep(forTimeInterval: 2)
	""".write(to: source, atomically: true, encoding: .utf8)
	let original = try Data(contentsOf: source)
	try host.prepare()
	let built = try host.request(
		"build", payload: ["projectRoot": fixture.url.path], projectID: fixture.id)
	#expect(built["target"] as? String == "ProductionApp")
	let launched = try host.request(
		"run", payload: ["projectRoot": fixture.url.path], projectID: fixture.id)
	#expect(launched["target"] as? String == "ProductionApp")
	let relative = try #require(launched["relativePath"] as? String)
	#expect(relative.hasPrefix(".mac-apper/DevBuild/"))
	let binary = fixture.url.appendingPathComponent(relative + "/Contents/MacOS/ProductionApp")
	#expect(FileManager.default.isExecutableFile(atPath: binary.path))
	let marker = fixture.url.appendingPathComponent("run-pid")
	let deadline = ContinuousClock.now.advanced(by: .seconds(5))
	while !FileManager.default.fileExists(atPath: marker.path), ContinuousClock.now < deadline {
		try await Task.sleep(for: .milliseconds(20))
	}
	let pid = try #require(Int32(try String(contentsOf: marker, encoding: .utf8)))
	#expect(kill(pid, 0) == 0)
	// This owned fixture exits itself; wait before removing its sources and host.
	while kill(pid, 0) == 0, ContinuousClock.now < deadline {
		try await Task.sleep(for: .milliseconds(50))
	}
	#expect(kill(pid, 0) != 0 && errno == ESRCH)
	#expect(try Data(contentsOf: source) == original)
	#expect(
		try String(contentsOf: fixture.url.appendingPathComponent("Package.swift"), encoding: .utf8)
			== manifest)
	#expect(
		!FileManager.default.fileExists(atPath: fixture.url.appendingPathComponent(".build").path))
}
