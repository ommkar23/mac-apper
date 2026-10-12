// @frontmatter:start
// Stages isolated signed Swift test hosts with declared XPC services, provider apps, and resources, then runs filtered tests and cleans up.
// @frontmatter:end
import Darwin
import Foundation

public struct TestHostResource {
	public let source: URL
	public let relativePath: String
	public init(source: URL, relativePath: String) {
		self.source = source; self.relativePath = relativePath
	}
}

public struct TestHostService {
	public let bundleName: String
	public let executable: URL
	public let infoPlist: URL
	public let resources: [TestHostResource]
	public let environment: [String: String]
	public init(
		bundleName: String, executable: URL, infoPlist: URL, resources: [TestHostResource] = [],
		environment: [String: String] = [:]
	) {
		self.bundleName = bundleName; self.executable = executable; self.infoPlist = infoPlist;
		self.resources = resources; self.environment = environment
	}
}

public struct TestHostApplication {
	public let bundleName: String
	public let executable: URL
	public let infoPlist: URL
	public let services: [TestHostService]
	public let resources: [TestHostResource]
	public init(
		bundleName: String, executable: URL, infoPlist: URL, services: [TestHostService],
		resources: [TestHostResource]
	) {
		self.bundleName = bundleName; self.executable = executable; self.infoPlist = infoPlist
		self.services = services; self.resources = resources
	}
}

@MainActor public final class PackagedTestHost {
	public struct Result { public let status: Int32; public let output: String }
	private let testBundleExecutable: URL
	private let loader: URL
	private let services: [TestHostService]
	private let applications: [TestHostApplication]
	private let resources: [TestHostResource]
	private var directory: URL?
	public private(set) var app: URL?

	public init(
		testBundleExecutable: URL, loader: URL, services: [TestHostService],
		applications: [TestHostApplication], resources: [TestHostResource]
	) {
		self.testBundleExecutable = testBundleExecutable; self.loader = loader
		self.services = services; self.applications = applications; self.resources = resources
	}

	public static func withInputDirectory<Value>(_ body: (URL) throws -> Value) throws -> Value {
		let directory = FileManager.default.temporaryDirectory.appendingPathComponent(
			"scenario-test-inputs-\(UUID().uuidString)")
		try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: false)
		defer { try? FileManager.default.removeItem(at: directory) }
		return try body(directory)
	}

	public static func runPreparation(_ executable: URL, arguments: [String]) throws {
		let selected = try preparationCommand(executable, arguments: arguments)
		let result = try command(
			selected.executable, arguments: selected.arguments,
			environment: selected.environment, timeout: 600)
		guard
			result.status == 0
		else {
			throw ScenarioFailure.message("scenario prerequisite failed: \(result.output.suffix(2000))")
		}
	}

	struct PreparationCommand {
		let executable: URL
		let arguments: [String]
		let environment: [String: String]
	}

	static func preparationCommand(
		_ executable: URL, arguments: [String],
		resolveTool: (String) throws -> URL = SwiftToolchain.executable
	) throws -> PreparationCommand {
		guard
			executable.path == "/usr/bin/xcrun",
			let tool = arguments.first,
			["swift", "swiftc"].contains(tool)
		else {
			return PreparationCommand(
				executable: executable, arguments: arguments, environment: [:])
		}
		return PreparationCommand(
			executable: try resolveTool(tool), arguments: Array(arguments.dropFirst()),
			environment: ["SWIFT_EXEC": try resolveTool("swiftc").path])
	}

	public static func swiftPMTestLoader() throws -> URL {
		let swift = try SwiftToolchain.executable("swift")
		let helper = swift.deletingLastPathComponent().deletingLastPathComponent()
			.appendingPathComponent("libexec/swift/pm/swiftpm-testing-helper")
		try executable(helper)
		return helper
	}

	public func prepare() throws {
		guard
			directory == nil
		else { throw ScenarioFailure.message("test host already staged") }
		let temporary = FileManager.default.temporaryDirectory.appendingPathComponent(
			"scenario-test-host-\(UUID().uuidString)")
		let staged = temporary.appendingPathComponent("ScenarioTests.app")
		do {
			try Self.executable(loader); try Self.executable(testBundleExecutable)
			let contents = staged.appendingPathComponent("Contents")
			try copy(loader, to: contents.appendingPathComponent("MacOS/\(loader.lastPathComponent)"))
			let tests = contents.appendingPathComponent("Resources/TestBundle")
			try copy(testBundleExecutable, to: tests)
			try sign(tests)
			try save(
				[
					"CFBundleExecutable": loader.lastPathComponent, "CFBundlePackageType": "APPL",
					"CFBundleIdentifier": identity(), "LSUIElement": true,
				], to: contents.appendingPathComponent("Info.plist"))
			try stage(resources, under: contents.appendingPathComponent("Resources"))
			for service in services {
				try stage(service, under: contents.appendingPathComponent("XPCServices"))
			}
			for application in applications {
				try Self.name(application.bundleName, suffix: ".app")
				let bundle = contents.appendingPathComponent("Applications/\(application.bundleName)")
				try stageExecutable(application.executable, plist: application.infoPlist, bundle: bundle)
				try stage(application.resources, under: bundle.appendingPathComponent("Contents/Resources"))
				for service in application.services {
					try stage(service, under: bundle.appendingPathComponent("Contents/XPCServices"))
				}
				try sign(bundle)
			}
			try sign(staged)
			try ScenarioProcess.run("/usr/bin/codesign", ["--verify", "--deep", "--strict", staged.path])
			directory = temporary; app = staged
		} catch { try? FileManager.default.removeItem(at: temporary); throw error }
	}

	public func runTest(
		filter: String, environment: [String: String] = [:], timeoutSeconds: Int = 2100
	) throws -> Result {
		guard
			let app,
			!filter.isEmpty,
			filter.utf8.count <= 512,
			(1...3600).contains(timeoutSeconds)
		else { throw ScenarioFailure.message("invalid filtered test invocation") }
		return try Self.command(
			app.appendingPathComponent("Contents/MacOS/\(loader.lastPathComponent)"),
			arguments: [
				"--test-bundle-path", app.appendingPathComponent("Contents/Resources/TestBundle").path,
				"--testing-library", "swift-testing", "--filter", filter,
			], environment: environment, timeout: timeoutSeconds)
	}

	public func remove() throws {
		guard
			let directory
		else { return }
		try FileManager.default.removeItem(at: directory)
		self.directory = nil; app = nil
	}

	private func stage(_ service: TestHostService, under root: URL) throws {
		try Self.name(service.bundleName, suffix: ".xpc")
		let bundle = root.appendingPathComponent(service.bundleName)
		try stageExecutable(
			service.executable, plist: service.infoPlist, bundle: bundle, environment: service.environment
		)
		try stage(service.resources, under: bundle.appendingPathComponent("Contents/Resources"))
		try sign(bundle)
	}

	private func stageExecutable(
		_ source: URL, plist: URL, bundle: URL, environment: [String: String] = [:]
	) throws {
		try Self.executable(source)
		try copy(
			source, to: bundle.appendingPathComponent("Contents/MacOS/\(source.lastPathComponent)"))
		try Self.regular(plist)
		guard
			var info = try PropertyListSerialization.propertyList(
				from: Data(contentsOf: plist), format: nil) as? [String: Any],
			info["CFBundleExecutable"] as? String == source.lastPathComponent
		else { throw ScenarioFailure.message("test host executable does not match plist") }
		info["CFBundleIdentifier"] = identity()
		if !environment.isEmpty {
			var xpc = info["XPCService"] as? [String: Any] ?? [:]
			let inherited = xpc["EnvironmentVariables"] as? [String: String] ?? [:]
			xpc["EnvironmentVariables"] = inherited.merging(environment) { _, scoped in scoped }
			info["XPCService"] = xpc
		}
		try save(info, to: bundle.appendingPathComponent("Contents/Info.plist"))
	}

	private func stage(_ resources: [TestHostResource], under root: URL) throws {
		for resource in resources {
			let parts = resource.relativePath.split(separator: "/", omittingEmptySubsequences: false)
			guard
				!parts.isEmpty,
				parts.allSatisfy({ !$0.isEmpty && $0 != "." && $0 != ".." && !$0.contains("\\") }),
				resource.relativePath.utf8.count <= 1024
			else { throw ScenarioFailure.message("invalid test host resource destination") }
			try copy(resource.source, to: root.appendingPathComponent(resource.relativePath))
		}
	}

	private static func name(_ value: String, suffix: String) throws {
		guard
			value.hasSuffix(suffix),
			value.dropLast(suffix.count).range(
				of: "^[A-Za-z][A-Za-z0-9-]{0,63}$", options: .regularExpression) != nil
		else { throw ScenarioFailure.message("invalid test host bundle name") }
	}
	private static func regular(_ url: URL) throws {
		let value = try url.resourceValues(forKeys: [
			.isRegularFileKey, .isSymbolicLinkKey, .fileSizeKey,
		])
		guard
			value.isRegularFile == true,
			value.isSymbolicLink != true,
			let size = value.fileSize,
			size <= 268_435_456
		else { throw ScenarioFailure.message("invalid test host input") }
	}
	private static func executable(_ url: URL) throws {
		try regular(url)
		guard
			FileManager.default.isExecutableFile(atPath: url.path)
		else { throw ScenarioFailure.message("invalid test host executable") }
	}
	private func copy(_ source: URL, to destination: URL) throws {
		let manager = FileManager.default
		let values = try source.resourceValues(forKeys: [.isDirectoryKey, .isSymbolicLinkKey])
		guard
			values.isSymbolicLink != true
		else { throw ScenarioFailure.message("linked test host input") }
		if values.isDirectory == true {
			guard
				let entries = manager.enumerator(
					at: source, includingPropertiesForKeys: [.isSymbolicLinkKey])
			else { throw ScenarioFailure.message("invalid test host resource tree") }
			var count = 0
			for case let entry as URL in entries {
				count += 1
				guard
					count <= 16_384,
					try entry.resourceValues(forKeys: [.isSymbolicLinkKey]).isSymbolicLink != true
				else { throw ScenarioFailure.message("unsafe test host resource tree") }
			}
		} else {
			try Self.regular(source)
		}
		try manager.createDirectory(
			at: destination.deletingLastPathComponent(), withIntermediateDirectories: true)
		try manager.copyItem(at: source, to: destination)
	}
	private func identity() -> String { "com.macapper.scenario.\(UUID().uuidString.lowercased())" }
	private func save(_ info: [String: Any], to url: URL) throws {
		try PropertyListSerialization.data(fromPropertyList: info, format: .xml, options: 0).write(
			to: url)
	}
	private func sign(_ url: URL) throws {
		do { try ScenarioProcess.run("/usr/bin/codesign", ["--force", "--sign", "-", url.path]) } catch
		{ throw ScenarioFailure.message("could not sign test-host component \(url.lastPathComponent)") }
	}

	private static func command(
		_ executable: URL, arguments: [String], environment: [String: String] = [:], timeout: Int
	) throws -> Result {
		let manager = FileManager.default
		let scratch = manager.temporaryDirectory.appendingPathComponent(
			"scenario-test-output-\(UUID().uuidString)")
		try manager.createDirectory(at: scratch, withIntermediateDirectories: false)
		defer { try? manager.removeItem(at: scratch) }
		let output = scratch.appendingPathComponent("output")
		manager.createFile(atPath: output.path, contents: nil)
		let handle = try FileHandle(forWritingTo: output)
		defer { try? handle.close() }
		let process = Process(); process.executableURL = executable; process.arguments = arguments
		process.environment = ProcessInfo.processInfo.environment.merging(environment) { _, value in
			value
		}
		process.standardInput = FileHandle.nullDevice; process.standardOutput = handle;
		process.standardError = handle
		let finished = DispatchSemaphore(value: 0)
		process.terminationHandler = { _ in finished.signal() }
		try process.run()
		if finished.wait(timeout: .now() + .seconds(timeout)) == .timedOut {
			process.terminate()
			if finished.wait(timeout: .now() + 5) == .timedOut {
				kill(process.processIdentifier, SIGKILL); _ = finished.wait(timeout: .now() + 5)
			}
			throw ScenarioFailure.message("packaged Swift tests timed out")
		}
		let reader = try FileHandle(forReadingFrom: output)
		defer { try? reader.close() }
		let data = try reader.read(upToCount: 65_537) ?? Data()
		guard
			data.count <= 65_536
		else { throw ScenarioFailure.message("oversized packaged test output") }
		return Result(status: process.terminationStatus, output: String(decoding: data, as: UTF8.self))
	}
}
