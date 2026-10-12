// @frontmatter:start
// Resolves the installed macOS SDK and runs bounded standalone compiler/import preflights with explicit SDK arguments.
// @frontmatter:end
import Darwin
import Foundation

public struct SDKCompiler: Sendable {
	public let executable: URL
	public let sdk: URL

	public static func resolve(discover: () throws -> String = discoverSDK) throws -> Self {
		let output = try discover().trimmingCharacters(in: .whitespacesAndNewlines)
		guard
			output.hasPrefix("/"),
			!output.contains("\n"),
			!output.contains("\0")
		else {
			throw ScenarioFailure.message(
				"macOS SDK discovery returned no absolute SDK path; check xcrun --sdk macosx --show-sdk-path and Command Line Tools selection"
			)
		}
		let sdk = URL(fileURLWithPath: output).resolvingSymlinksInPath()
		let values = try? sdk.resourceValues(forKeys: [.isDirectoryKey])
		guard
			values?.isDirectory == true,
			FileManager.default.fileExists(atPath: sdk.appendingPathComponent("SDKSettings.json").path),
			FileManager.default.fileExists(
				atPath: sdk.appendingPathComponent("usr/include/sys/types.h").path)
		else {
			throw ScenarioFailure.message(
				"Invalid installed macOS SDK at \(output); check Command Line Tools selection")
		}
		return try Self(executable: SwiftToolchain.executable("swiftc"), sdk: sdk)
	}

	public static func discoverSDK() throws -> String {
		let result = try command(
			URL(fileURLWithPath: "/usr/bin/xcrun"), ["--sdk", "macosx", "--show-sdk-path"], timeout: 10)
		guard
			result.status == 0
		else {
			throw ScenarioFailure.message("macOS SDK discovery failed: \(result.output.suffix(4096))")
		}
		return result.output
	}

	public func arguments(_ arguments: [String], scratch: URL) -> [String] {
		// These probes need no driver/link jobs or external macro expansion. Run one frontend
		// directly so timeout/cancellation reaping cannot strand a driver-owned compiler child.
		[
			"-frontend", "-enable-objc-interop", "-sdk", sdk.path, "-module-cache-path",
			scratch.appendingPathComponent("ProbeModules").path,
		] + arguments
	}

	public func run(
		_ arguments: [String], scratch: URL,
		environment: [String: String] = ProcessInfo.processInfo.environment
	) throws -> Result {
		try Self.command(
			executable, self.arguments(arguments, scratch: scratch), environment: environment, timeout: 30
		)
	}

	public func requireImport(
		module: String, searchPath: URL, scratch: URL,
		environment: [String: String] = ProcessInfo.processInfo.environment
	) throws {
		let source = scratch.appendingPathComponent("ImportProbe.swift")
		try "import \(module)\n".write(to: source, atomically: true, encoding: .utf8)
		defer { try? FileManager.default.removeItem(at: source) }
		let result = try run(
			["-typecheck", "-I", searchPath.path, source.path], scratch: scratch, environment: environment
		)
		guard
			result.status == 0
		else {
			throw ScenarioFailure.message(
				"Compiler setup/module import failed (\(module)); compiler=\(executable.path) SDK=\(sdk.path): \(result.output.suffix(4096))"
			)
		}
	}

	public func preflight(environment: [String: String] = ProcessInfo.processInfo.environment) throws
	{
		let start = Date()
		var passed = false
		defer {
			print(
				"SCENARIO_SDK_PREFLIGHT: \(passed ? "passed" : "failed") compile and transitive import in \(Date().timeIntervalSince(start)) seconds; SDK=\(sdk.path)"
			)
		}
		let scratch = URL(fileURLWithPath: "/private/tmp/mac-apper-sdk-preflight-\(UUID().uuidString)")
		try FileManager.default.createDirectory(
			at: scratch, withIntermediateDirectories: false, attributes: [.posixPermissions: 0o700])
		defer { try? FileManager.default.removeItem(at: scratch) }
		let source = scratch.appendingPathComponent("SDKPreflight.swift")
		try """
		import Foundation
		import Darwin
		import os
		import CoreData
		import Observation
		public struct SDKPreflightValue { public let date: Date; public let context: NSManagedObjectContext }
		""".write(to: source, atomically: true, encoding: .utf8)
		let result = try run(
			[
				"-emit-module", "-module-name", "SDKPreflight", "-emit-module-path",
				scratch.appendingPathComponent("SDKPreflight.swiftmodule").path, source.path,
			], scratch: scratch, environment: environment)
		guard
			result.status == 0
		else {
			throw ScenarioFailure.message(
				"Compiler/SDK preflight compilation failed before startup; compiler=\(executable.path) SDK=\(sdk.path): \(result.output.suffix(4096))"
			)
		}
		try requireImport(
			module: "SDKPreflight", searchPath: scratch, scratch: scratch, environment: environment)
		passed = true
	}

	public static func beforeStartup<T>(preflight: () throws -> Void, start: () throws -> T) throws
		-> T
	{
		try preflight()
		return try start()
	}

	public struct Result: Sendable {
		public let status: Int32
		public let output: String
	}

	static func command(
		_ executable: URL, _ arguments: [String],
		environment: [String: String] = ProcessInfo.processInfo.environment, timeout: TimeInterval
	) throws -> Result {
		let directory = URL(fileURLWithPath: "/private/tmp/mac-apper-sdk-command-\(UUID().uuidString)")
		try FileManager.default.createDirectory(
			at: directory, withIntermediateDirectories: false, attributes: [.posixPermissions: 0o700])
		defer { try? FileManager.default.removeItem(at: directory) }
		let log = directory.appendingPathComponent("output")
		try Data().write(to: log, options: .withoutOverwriting)
		let handle = try FileHandle(forWritingTo: log)
		defer { try? handle.close() }
		let process = Process()
		process.executableURL = executable
		process.arguments = arguments
		var environment = environment
		environment.removeValue(forKey: "SDKROOT")
		process.environment = environment
		process.standardInput = FileHandle.nullDevice
		process.standardOutput = handle
		process.standardError = handle
		try process.run()
		defer {
			if process.isRunning { _ = kill(process.processIdentifier, SIGKILL) }
			process.waitUntilExit()
		}
		let deadline = Date().addingTimeInterval(timeout)
		while process.isRunning {
			try Task.checkCancellation()
			guard
				Date() < deadline,
				(try log.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? Int.max) <= 1_048_576
			else {
				throw ScenarioFailure.message(
					"SDK/compiler command exceeded \(timeout)-second/1-MiB bound: \(executable.path)")
			}
			Thread.sleep(forTimeInterval: 0.02)
		}
		process.waitUntilExit()
		guard
			(try log.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? Int.max) <= 1_048_576
		else { throw ScenarioFailure.message("SDK/compiler command output exceeds 1 MiB") }
		return try Result(
			status: process.terminationStatus, output: String(contentsOf: log, encoding: .utf8))
	}
}
