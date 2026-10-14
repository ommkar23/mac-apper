// @frontmatter:start
// Tests SDK discovery rejection, real transitive compiler imports, bounded failures, and the pre-startup gate without paid work.
// @frontmatter:end
import Foundation
import Testing
@testable import Scenario

@Suite(.serialized) struct SDKCompilerTests {
	@Test func sdkCompilerRejectsUnavailableSDK() throws {
		for output in ["", "relative", "/private/tmp/no-such-mac-apper-sdk", "/"] {
			#expect(throws: (any Error).self) {
				try SDKCompiler.resolve(discover: { output })
			}
		}
		#expect(throws: (any Error).self) {
			try SDKCompiler.resolve(discover: { throw ScenarioFailure.message("xcrun failed") })
		}
	}

	@Test func sdkCompilerPreflightImportsTransitiveSDKModulesWithoutInheritedSDK() throws {
		let compiler = try SDKCompiler.resolve()
		for sdkroot in [nil, "/private/tmp/misleading-sdk"] as [String?] {
			var environment = ProcessInfo.processInfo.environment
			environment["SDKROOT"] = sdkroot
			try compiler.preflight(environment: environment)
		}
	}

	@Test func sdkCompilerGateDoesNotStartAfterFailure() throws {
		var started = false
		#expect(throws: (any Error).self) {
			try SDKCompiler.beforeStartup(preflight: { throw ScenarioFailure.message("import failed") }) {
				started = true
			}
		}
		#expect(!started)
		try SDKCompiler.beforeStartup(preflight: {}) { started = true }
		#expect(started)
	}

	@Test func sdkCompilerRealFailuresBlockStartupAndCleanScratch() throws {
		let compiler = try SDKCompiler.resolve()
		let failing = SDKCompiler(executable: URL(fileURLWithPath: "/usr/bin/false"), sdk: compiler.sdk)
		let manager = FileManager.default
		func ownedScratch() throws -> Set<String> {
			Set(
				try manager.contentsOfDirectory(atPath: ProjectTemporaryDirectory.root().path).filter {
					$0.hasPrefix("mac-apper-sdk-preflight-") || $0.hasPrefix("mac-apper-sdk-command-")
				})
		}
		let before = try ownedScratch()
		var started = false
		#expect(throws: (any Error).self) {
			try SDKCompiler.beforeStartup(preflight: { try failing.preflight() }) { started = true }
		}
		#expect(!started)
		#expect(try ownedScratch() == before)
		#expect(throws: (any Error).self) {
			try SDKCompiler.command(URL(fileURLWithPath: "/bin/sleep"), ["5"], timeout: 0.05)
		}
		#expect(try ownedScratch() == before)
		let scratch = try ProjectTemporaryDirectory.appending(
			"mac-apper-sdk-import-test-\(UUID().uuidString)")
		try manager.createDirectory(
			at: scratch, withIntermediateDirectories: false, attributes: [.posixPermissions: 0o700])
		defer { try? manager.removeItem(at: scratch) }
		#expect(throws: (any Error).self) {
			try SDKCompiler.beforeStartup(preflight: {
				try compiler.requireImport(module: "MissingAppModel", searchPath: scratch, scratch: scratch)
			}) { started = true }
		}
		#expect(!started)
	}
}
