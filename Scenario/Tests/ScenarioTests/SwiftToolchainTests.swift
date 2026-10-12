import Foundation
import Testing

@testable import Scenario

private final class SwiftToolchainTestAnchor: NSObject {}

@Test @MainActor func preparationNonSwiftCommandsDoNotResolveToolsOrOverrideEnvironment() throws {
	for (path, arguments) in [
		("/usr/bin/true", []), ("/usr/bin/xcrun", ["--show-sdk-path"]),
		("/private/tmp/injected-tool", ["swift", "test"]),
	] {
		let executable = URL(fileURLWithPath: path)
		let command = try PackagedTestHost.preparationCommand(executable, arguments: arguments) { _ in
			throw ScenarioFailure.message("standalone Swift is absent in this fixture")
		}
		#expect(command.executable == executable)
		#expect(command.arguments == arguments)
		#expect(command.environment.isEmpty)
	}
}

@Test @MainActor func preparationNonSwiftExecutionPreservesInheritedSwiftExec() throws {
	let inherited = ProcessInfo.processInfo.environment["SWIFT_EXEC"]
	try PackagedTestHost.runPreparation(
		URL(fileURLWithPath: "/bin/sh"),
		arguments: [
			"-c", "test \"${SWIFT_EXEC+x}\" = \"$1\" && test \"${SWIFT_EXEC-}\" = \"$2\"",
			"environment-check", inherited == nil ? "" : "x", inherited ?? "",
		])
}

@Test @MainActor func preparationRedirectsBothSwiftToolsAndPinsCompiler() throws {
	for tool in ["swift", "swiftc"] {
		var resolved: [String] = []
		let bin = URL(fileURLWithPath: "/private/tmp/standalone-swift64/usr/bin")
		let command = try PackagedTestHost.preparationCommand(
			URL(fileURLWithPath: "/usr/bin/xcrun"), arguments: [tool, "--version"]
		) { name in
			resolved.append(name)
			return bin.appendingPathComponent(name)
		}
		#expect(command.executable == bin.appendingPathComponent(tool))
		#expect(command.arguments == ["--version"])
		#expect(command.environment == ["SWIFT_EXEC": bin.appendingPathComponent("swiftc").path])
		#expect(resolved.contains(tool))
	}
}

@Test @MainActor func packagedStandaloneLoaderSmoke() throws {
	if ProcessInfo.processInfo.environment["SCENARIO_SWIFT64_HOSTED"] == "1" {
		print("SWIFT64_HOSTED_TEST_STARTED")
		return
	}
	let tests = try #require(Bundle(for: SwiftToolchainTestAnchor.self).executableURL)
	let host = PackagedTestHost(
		testBundleExecutable: tests, loader: try PackagedTestHost.swiftPMTestLoader(),
		services: [], applications: [], resources: [])
	try host.prepare()
	defer { try? host.remove() }
	let result = try host.runTest(
		filter: "^ScenarioTests.packagedStandaloneLoaderSmoke",
		environment: ["SCENARIO_SWIFT64_HOSTED": "1"], timeoutSeconds: 30)
	#expect(result.status == 0, "\(result.output)")
	#expect(result.output.contains("SWIFT64_HOSTED_TEST_STARTED"), "Hosted test must actually run")
}

@Test @MainActor func scenarioUsesStandaloneSwiftAndMatchingTestLoader() throws {
	let swift = try SwiftToolchain.executable("swift")
	#expect(swift.path.hasSuffix("swift-6.4.0-RELEASE.xctoolchain/usr/bin/swift"))
	let loader = try PackagedTestHost.swiftPMTestLoader()
	#expect(
		loader.path.hasPrefix(swift.deletingLastPathComponent().deletingLastPathComponent().path + "/"))
	#expect(throws: (any Error).self) { try SwiftToolchain.executable("../swift") }
}
