import Foundation
import Scenario
import Testing

@testable import DevToolsApplication

@Test func productionSwiftCommandsSelectStandalone64WithoutShellEnvironment() throws {
	for tool in ["swift", "swiftc"] {
		let command = try SwiftToolchain.command(
			executable: URL(fileURLWithPath: "/usr/bin/xcrun"),
			arguments: [tool, "--version"], environment: ["SWIFT_EXEC": "/old/swiftc"])
		#expect(command.executable.path.hasSuffix("swift-6.4.0-RELEASE.xctoolchain/usr/bin/\(tool)"))
		#expect(command.arguments == ["--version"])
		#expect(
			command.environment["SWIFT_EXEC"]
				== command.executable.deletingLastPathComponent().appendingPathComponent("swiftc").path)
		#expect(FileManager.default.isExecutableFile(atPath: command.executable.path))
	}
	let sdk = try SwiftToolchain.command(
		executable: URL(fileURLWithPath: "/usr/bin/xcrun"),
		arguments: ["--show-sdk-path"], environment: [:])
	#expect(sdk.executable.path == "/usr/bin/xcrun")
	#expect(sdk.arguments == ["--show-sdk-path"])
}

@Test func toolchainSelectionPreservesInjectedToolsAndOwnedProcesses() throws {
	let fixture = try ProjectTemporaryDirectory.appending("injected-tool")
	let command = try SwiftToolchain.command(
		executable: fixture, arguments: ["swift", "test"], environment: ["fixture": "yes"])
	#expect(command.executable == fixture)
	#expect(command.arguments == ["swift", "test"])
	#expect(command.environment == ["fixture": "yes"])
}

@Test func productionToolchainPreflightsBothExecutablesWithoutFallback() throws {
	let manager = FileManager.default
	let bin = try ProjectTemporaryDirectory.appending("devtools-toolchain-\(UUID().uuidString)")
	try manager.createDirectory(at: bin, withIntermediateDirectories: false)
	defer { try? manager.removeItem(at: bin) }
	for missing in ["swift", "swiftc"] {
		let present = bin.appendingPathComponent(missing == "swift" ? "swiftc" : "swift")
		try manager.copyItem(at: URL(fileURLWithPath: "/usr/bin/true"), to: present)
		defer { try? manager.removeItem(at: present) }
		for tool in ["swift", "swiftc"] {
			do {
				_ = try SwiftToolchain.command(
					executable: URL(fileURLWithPath: "/usr/bin/xcrun"), arguments: [tool, "--version"],
					environment: ["SWIFT_EXEC": "/old/swiftc"], bin: bin)
				Issue.record("Missing \(missing) must fail before starting \(tool), without CLT fallback")
			} catch {
				let message = String(describing: error)
				#expect(message.contains("standalone Swift 6.4.0"))
				#expect(message.contains(bin.appendingPathComponent(missing).path))
			}
		}
		let sdk = try SwiftToolchain.command(
			executable: URL(fileURLWithPath: "/usr/bin/xcrun"), arguments: ["--show-sdk-path"],
			environment: ["SWIFT_EXEC": "keep"], bin: bin)
		#expect(sdk.executable.path == "/usr/bin/xcrun")
		#expect(sdk.environment == ["SWIFT_EXEC": "keep"])
		let injected = try SwiftToolchain.command(
			executable: present, arguments: ["swift", "test"], environment: ["SWIFT_EXEC": "keep"],
			bin: bin)
		#expect(injected.executable == present)
		#expect(injected.environment == ["SWIFT_EXEC": "keep"])
	}
}
