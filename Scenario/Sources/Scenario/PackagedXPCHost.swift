// @frontmatter:start
// Stages and signs a disposable generated-client XPC host with explicitly declared bounded app and service resources.
// @frontmatter:end
import Foundation

public struct XPCHostDefinition {
	public let appName: String
	public let clientExecutable: URL
	public let serviceExecutable: URL
	public let appPlist: URL
	public let servicePlist: URL
	public let appResources: [TestHostResource]
	public let serviceResources: [TestHostResource]

	public init(
		appName: String, clientExecutable: URL, serviceExecutable: URL,
		appPlist: URL, servicePlist: URL,
		appResources: [TestHostResource] = [], serviceResources: [TestHostResource] = []
	) throws {
		guard
			appName.range(of: "^[A-Za-z][A-Za-z0-9-]{0,63}$", options: .regularExpression) != nil
		else { throw ScenarioFailure.message("invalid XPC host name") }
		self.appName = appName
		self.clientExecutable = clientExecutable
		self.serviceExecutable = serviceExecutable
		self.appPlist = appPlist
		self.servicePlist = servicePlist
		self.appResources = appResources
		self.serviceResources = serviceResources
	}
}

@MainActor public final class PackagedXPCHost {
	private let definition: XPCHostDefinition
	private var directory: URL?
	private var client: URL?
	public private(set) var app: URL?

	public init(_ definition: XPCHostDefinition) { self.definition = definition }

	public func prepare() throws {
		guard
			directory == nil
		else { throw ScenarioFailure.message("XPC host already staged") }
		let manager = FileManager.default
		let temporary = try ProjectTemporaryDirectory.root().appendingPathComponent(
			"scenario-xpc-host-\(UUID().uuidString)")
		let stagedApp = temporary.appendingPathComponent("\(definition.appName).app")
		let contents = stagedApp.appendingPathComponent("Contents")
		let client = contents.appendingPathComponent(
			"MacOS/\(definition.clientExecutable.lastPathComponent)")
		let serviceName = definition.serviceExecutable.lastPathComponent
		let serviceBundle = contents.appendingPathComponent("XPCServices/\(serviceName).xpc")
		let serviceContents = serviceBundle.appendingPathComponent("Contents")
		let service = serviceContents.appendingPathComponent("MacOS/\(serviceName)")
		let identifier = "com.macapper.scenario.\(UUID().uuidString.lowercased()).xpc"
		do {
			try manager.createDirectory(
				at: client.deletingLastPathComponent(), withIntermediateDirectories: true)
			try manager.createDirectory(
				at: service.deletingLastPathComponent(), withIntermediateDirectories: true)
			for source in [definition.clientExecutable, definition.serviceExecutable] {
				guard
					manager.isExecutableFile(atPath: source.path),
					(try source.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey]))
						.isRegularFile == true,
					(try source.resourceValues(forKeys: [.isSymbolicLinkKey])).isSymbolicLink != true
				else { throw ScenarioFailure.message("invalid XPC host executable") }
			}
			try manager.copyItem(at: definition.clientExecutable, to: client)
			try manager.copyItem(at: definition.serviceExecutable, to: service)
			var appInfo = try Self.plist(definition.appPlist)
			guard
				appInfo["CFBundleExecutable"] as? String == client.lastPathComponent
			else { throw ScenarioFailure.message("XPC host executable does not match plist") }
			appInfo["CFBundleIdentifier"] = "com.macapper.scenario.\(UUID().uuidString.lowercased())"
			try Self.save(appInfo, to: contents.appendingPathComponent("Info.plist"))
			var serviceInfo = try Self.plist(definition.servicePlist)
			guard
				serviceInfo["CFBundleExecutable"] as? String == serviceName
			else { throw ScenarioFailure.message("XPC service executable does not match plist") }
			serviceInfo["CFBundleIdentifier"] = identifier
			var xpc = serviceInfo["XPCService"] as? [String: Any] ?? [:]
			xpc["EnvironmentVariables"] = try ProjectTemporaryDirectory.environment(
				xpc["EnvironmentVariables"] as? [String: String] ?? [:])
			serviceInfo["XPCService"] = xpc
			try Self.save(serviceInfo, to: serviceContents.appendingPathComponent("Info.plist"))
			try Self.stageResources(
				definition.appResources, under: contents.appendingPathComponent("Resources"))
			try Self.stageResources(
				definition.serviceResources, under: serviceContents.appendingPathComponent("Resources"))
			try ScenarioProcess.run(
				"/usr/bin/codesign",
				[
					"--force", "--sign", "-", "--identifier", identifier, serviceBundle.path,
				])
			try ScenarioProcess.run("/usr/bin/codesign", ["--force", "--sign", "-", stagedApp.path])
			try ScenarioProcess.run(
				"/usr/bin/codesign", ["--verify", "--deep", "--strict", stagedApp.path])
			self.directory = temporary
			self.app = stagedApp
			self.client = client
		} catch {
			try? manager.removeItem(at: temporary)
			throw error
		}
	}

	public func remove() throws {
		guard
			let directory
		else { return }
		try FileManager.default.removeItem(at: directory)
		self.directory = nil
		app = nil
		client = nil
	}

	public func request(
		_ command: String, payload: [String: Any], projectID: UUID = UUID(),
		sessionID: UUID = UUID(), timeoutSeconds: Int = 345
	) throws -> [String: Any] {
		let (reply, requestID, project) = try send(
			command, payload: payload, projectID: projectID, sessionID: sessionID,
			timeoutSeconds: timeoutSeconds)
		guard
			reply.status == 0
		else {
			throw ScenarioFailure.message(
				"XPC host client failed: \(Self.failureCode(reply.data))")
		}
		guard
			let record = try JSONSerialization.jsonObject(with: reply.data) as? [String: Any],
			record["version"] as? Int == 1,
			record["requestID"] as? String == requestID,
			record["projectID"] as? String == project,
			record["success"] as? Bool == true,
			let encoded = record["payload"] as? String,
			let data = Data(base64Encoded: encoded),
			data.count <= 65_536,
			let value = try JSONSerialization.jsonObject(with: data) as? [String: Any]
		else { throw ScenarioFailure.message("invalid XPC host response") }
		return value
	}

	/// Requires an identified failure envelope from the generated terminal client.
	public func expectRejected(
		_ command: String, payload: [String: Any], error: String,
		projectID: UUID = UUID(), sessionID: UUID = UUID(), timeoutSeconds: Int = 345
	) throws {
		let (reply, requestID, project) = try send(
			command, payload: payload, projectID: projectID, sessionID: sessionID,
			timeoutSeconds: timeoutSeconds)
		guard
			reply.status == 1,
			let record = try JSONSerialization.jsonObject(with: reply.data) as? [String: Any],
			Set(record.keys).isSubset(of: [
				"version", "requestID", "projectID", "success", "payload", "error",
			]),
			record["version"] as? Int == 1,
			record["requestID"] as? String == requestID,
			record["projectID"] as? String == project,
			record["success"] as? Bool == false,
			(record["payload"] == nil || record["payload"] is NSNull),
			record["error"] as? String == error
		else {
			throw ScenarioFailure.message(
				"unexpected XPC operation failure: \(Self.failureCode(reply.data))")
		}
	}

	private static func failureCode(_ data: Data) -> String {
		let record = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
		guard
			let code = record?["error"] as? String,
			["operationFailed", "invalidRequest", "invalidResponse", "unavailable", "timedOut"]
				.contains(code)
		else { return "unknown" }
		return code
	}

	private func send(
		_ command: String, payload: [String: Any], projectID: UUID, sessionID: UUID,
		timeoutSeconds: Int
	) throws -> (XPCClientAdapter.Reply, String, String) {
		guard
			let client,
			command.range(of: "^[a-z][a-z0-9_-]{0,63}$", options: .regularExpression) != nil
		else { throw ScenarioFailure.message("XPC host is not staged or command is invalid") }
		let project = projectID.uuidString
		let session = sessionID.uuidString
		let requestID = UUID().uuidString
		let body = try JSONSerialization.data(withJSONObject: payload)
		let envelope = try JSONSerialization.data(withJSONObject: [
			"version": 1, "requestID": requestID, "projectID": project,
			"sessionID": session, "command": command, "payload": body.base64EncodedString(),
		])
		let reply = try XPCClientAdapter().call(
			client, request: envelope,
			environment: [
				"OPENXPC_PROJECT_ID": project, "OPENXPC_SESSION_ID": session,
			], maxResponseBytes: 131_072, timeoutSeconds: timeoutSeconds)
		return (reply, requestID, project)
	}

	private static func stageResources(_ resources: [TestHostResource], under root: URL) throws {
		let manager = FileManager.default
		var bytes = 0, entries = 0
		func validate(_ source: URL, depth: Int) throws {
			entries += 1
			let values = try source.resourceValues(forKeys: [
				.isRegularFileKey, .isDirectoryKey, .isSymbolicLinkKey, .fileSizeKey,
			])
			guard
				source.isFileURL,
				values.isSymbolicLink != true,
				depth <= 12,
				entries <= 1024
			else { throw ScenarioFailure.message("unsafe XPC host resource") }
			if values.isDirectory == true {
				for child in try manager.contentsOfDirectory(at: source, includingPropertiesForKeys: nil) {
					try validate(child, depth: depth + 1)
				}
			} else {
				guard
					values.isRegularFile == true,
					let size = values.fileSize,
					size <= 16_777_216 - bytes
				else { throw ScenarioFailure.message("oversized XPC host resource") }
				bytes += size
			}
		}
		for resource in resources {
			let components = resource.relativePath.split(separator: "/", omittingEmptySubsequences: false)
			guard
				resource.relativePath.utf8.count <= 1024,
				!resource.relativePath.contains("\\"),
				!resource.relativePath.unicodeScalars.contains(where: { $0.value < 32 }),
				components.allSatisfy({ !$0.isEmpty && $0 != "." && $0 != ".." })
			else { throw ScenarioFailure.message("invalid XPC host resource destination") }
			try validate(resource.source, depth: 0)
			let destination = root.appendingPathComponent(resource.relativePath)
			try manager.createDirectory(
				at: destination.deletingLastPathComponent(), withIntermediateDirectories: true)
			try manager.copyItem(at: resource.source, to: destination)
		}
	}

	private static func plist(_ url: URL) throws -> [String: Any] {
		let values = try url.resourceValues(forKeys: [
			.isRegularFileKey, .isSymbolicLinkKey, .fileSizeKey,
		])
		guard
			values.isRegularFile == true,
			values.isSymbolicLink != true,
			let size = values.fileSize,
			size <= 65_536,
			let info = try PropertyListSerialization.propertyList(
				from: Data(contentsOf: url), format: nil) as? [String: Any]
		else { throw ScenarioFailure.message("invalid XPC host plist") }
		return info
	}

	private static func save(_ plist: [String: Any], to url: URL) throws {
		try PropertyListSerialization.data(fromPropertyList: plist, format: .xml, options: 0).write(
			to: url)
	}
}
