// @frontmatter:start
// Builds, stages, launches, and tracks project-owned development app processes.
// @frontmatter:end
import Foundation

struct DevelopmentRunResult: Sendable {
	let target: String
	let appBundle: URL
	let instanceID: String
}

enum DevelopmentLaunchError: Error, Sendable, Equatable {
	case executableMissing, invalidBranding
}

actor RunController: OpenXPCRunController {
	private let projects: ProjectResolver
	private let gate: DevToolsOperationGate
	private let build: BuildController
	private let environment: [String: String]
	private var processes: [String: (String, OwnedProcess)] = [:]

	init(
		projects: ProjectResolver, gate: DevToolsOperationGate, build: BuildController,
		environment: [String: String] = ProcessInfo.processInfo.environment
	) {
		self.projects = projects
		self.gate = gate
		self.build = build
		self.environment = environment
	}

	func handle(_ projectID: UUID, _ sessionID: UUID, _ request: RunRequest) async throws -> RunResult
	{
		let project = try await projects.lookup(
			projectRoot: request.projectRoot,
			projectID: projectID.uuidString.lowercased(), sessionID: sessionID.uuidString)
		return try await gate.run {
			let requestID = UUID().uuidString.lowercased()
			let result = try await self.run(project: project, requestID: requestID)
			return try RunResult(
				summary: "Launched \(result.target) development app.",
				target: result.target,
				relativePath: ".mac-apper/DevBuild/\(requestID)/\(result.target).app")
		}
	}

	func run(project: ResolvedProject, requestID: String) async throws -> DevelopmentRunResult {
		// One live instance per project; replacement does not orphan the previous instance.
		for (id, value) in processes where value.0 == project.manifest.appID {
			try await stop(instanceID: id)
		}
		let built = try await build.build(project: project, requestID: requestID)
		try Task.checkCancellation()
		let bundle = try stage(build: built, project: project, requestID: requestID)
		let instanceID = UUID().uuidString.lowercased()
		var childEnvironment = environment
		childEnvironment.removeValue(forKey: "DEVTOOLS_DEVELOPMENT_IDENTITY")
		let process = try OwnedProcess(
			executable: bundle.appendingPathComponent("Contents/MacOS/\(built.target)"),
			arguments: [], directory: project.scope.root, environment: childEnvironment,
			outputLimit: 65_536)
		do {
			try Task.checkCancellation()
			guard
				try process.isAlive()
			else { throw DevelopmentLaunchError.executableMissing }
			processes[instanceID] = (project.manifest.appID, process)
			Task { await self.monitor(instanceID) }
			return DevelopmentRunResult(target: built.target, appBundle: bundle, instanceID: instanceID)
		} catch {
			try await process.stop()
			throw error
		}
	}

	private func monitor(_ id: String) async {
		while let value = processes[id] {
			do {
				if !(try value.1.isAlive()) {
					try await stop(instanceID: id)
					return
				}
				try await Task.sleep(for: .milliseconds(100))
			} catch {
				try? await stop(instanceID: id)
				return
			}
		}
	}

	func stop(instanceID: String) async throws {
		guard
			let value = processes[instanceID]
		else { return }
		try await value.1.stop()
		processes.removeValue(forKey: instanceID)
	}

	func stopAll() async throws {
		for id in Array(processes.keys) { try await stop(instanceID: id) }
	}

	func stage(build: SourceBuildResult, project: ResolvedProject, requestID: String) throws
		-> URL
	{
		let branding = try DevelopmentBranding.load(scope: project.scope, fallback: build.target)
		let relative = ".mac-apper/DevBuild/\(requestID)/\(build.target).app"
		let bundle = try project.scope.resolve(relative)
		guard
			!FileManager.default.fileExists(atPath: bundle.path)
		else { throw DevelopmentLaunchError.executableMissing }
		let macOS = try project.scope.resolve(relative + "/Contents/MacOS")
		try FileManager.default.createDirectory(
			at: macOS, withIntermediateDirectories: true,
			attributes: [.posixPermissions: 0o700])
		let bin = build.buildDirectory.appendingPathComponent("debug").resolvingSymlinksInPath()
		guard
			bin.path.hasPrefix(build.buildDirectory.path + "/")
		else { throw DevelopmentLaunchError.executableMissing }
		let source = bin.appendingPathComponent(build.target)
		guard
			FileManager.default.isExecutableFile(atPath: source.path),
			try source.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey]).isRegularFile
				== true,
			try source.resourceValues(forKeys: [.isSymbolicLinkKey]).isSymbolicLink != true
		else { throw DevelopmentLaunchError.executableMissing }
		let destination = try project.scope.resolve(relative + "/Contents/MacOS/\(build.target)")
		try FileManager.default.copyItem(at: source, to: destination)
		try FileManager.default.setAttributes(
			[.posixPermissions: 0o700], ofItemAtPath: destination.path)
		// SwiftPM's generated accessor uses Bundle.main.bundleURL/<resource>.bundle.
		for resource in try FileManager.default.contentsOfDirectory(
			at: bin, includingPropertiesForKeys: nil)
		where resource.pathExtension == "bundle" {
			try rejectLinks(resource)
			try FileManager.default.copyItem(
				at: resource,
				to: project.scope.resolve(relative + "/" + resource.lastPathComponent))
		}
		let plist: [String: Any] = [
			"CFBundleExecutable": build.target,
			"CFBundleIdentifier": "com.macapper.dev." + project.manifest.appID,
			"CFBundleName": branding.name, "CFBundleDisplayName": branding.name,
			"CFBundlePackageType": "APPL", "CFBundleVersion": requestID,
			"CFBundleShortVersionString": "0", "LSMinimumSystemVersion": "14.0",
			"NSHighResolutionCapable": true,
		]
		try PropertyListSerialization.data(fromPropertyList: plist, format: .xml, options: 0)
			.write(to: project.scope.resolve(relative + "/Contents/Info.plist"), options: .atomic)
		return bundle
	}

	private func rejectLinks(_ url: URL) throws {
		let values = try url.resourceValues(forKeys: [
			.isSymbolicLinkKey, .isDirectoryKey, .isRegularFileKey,
		])
		guard
			values.isSymbolicLink != true
		else { throw DevelopmentLaunchError.executableMissing }
		if values.isDirectory == true {
			for child in try FileManager.default.contentsOfDirectory(
				at: url, includingPropertiesForKeys: nil)
			{
				try rejectLinks(child)
			}
		} else if values.isRegularFile != true {
			throw DevelopmentLaunchError.executableMissing
		}
	}
}
