// @frontmatter:start
// Prepares Create's isolated home and selective Codex credential, validates home scope, and archives only owned history and preview evidence.
// @frontmatter:end
import Foundation
import Scenario
import Testing

@MainActor enum CreateScenarioIsolation {
	static let confirmation = "CREATE_CLEANUP_CONFIRMED: Pi and development processes reaped"
	static func prepareHome() throws -> IsolatedScenarioHome {
		let home = try IsolatedScenarioHome()
		do {
			try home.linkInstalledToolchain()
			_ = try home.privateDirectory(".mac-apper")
			let environment = ProcessInfo.processInfo.environment
			let original =
				environment["PI_CODING_AGENT_DIR"].map { URL(fileURLWithPath: $0) }
				?? FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".pi/agent")
			_ = try home.stageCredentialEntry(
				from: original.appendingPathComponent("auth.json"), key: "openai-codex",
				relativePath: ".pi/agent/auth.json", project: { try credentialSnapshot($0) })
			return home
		} catch {
			try home.remove(cleanupConfirmed: true)
			throw error
		}
	}
	static func credentialSnapshot(_ entry: [String: Any], now: Date = Date()) throws -> [String: Any]
	{
		guard
			entry["type"] as? String == "oauth",
			let access = entry["access"] as? String,
			!access.isEmpty,
			let expires = entry["expires"] as? Double,
			expires.isFinite && expires > (now.timeIntervalSince1970 + 1500) * 1000
		else {
			throw ScenarioFailure.message(
				"Codex OAuth snapshot needs at least 1500 seconds remaining; no refresh or login is attempted"
			)
		}
		// AuthStorage requires a string refresh field. Empty is deliberately non-refreshable:
		// a private scenario must never rotate the user's original refresh credential.
		var snapshot: [String: Any] = [
			"type": "oauth", "access": access, "expires": expires, "refresh": "",
		]
		if let account = entry["accountId"] as? String { snapshot["accountId"] = account }
		return snapshot
	}
	static func requireHome() throws -> URL {
		let path = try #require(ProcessInfo.processInfo.environment["AGENT_CREATE_HOME"])
		try #require(path.hasPrefix("/private/tmp/scenario-home-"))
		let home = URL(fileURLWithPath: path)
		let values = try home.resourceValues(forKeys: [.isDirectoryKey, .isSymbolicLinkKey])
		try #require(values.isDirectory == true && values.isSymbolicLink != true)
		try #require(
			FileManager.default.homeDirectoryForCurrentUser.resolvingSymlinksInPath()
				== home.resolvingSymlinksInPath())
		return home
	}
	static func archive(project: URL, home: URL) throws {
		let manager = FileManager.default
		let archive = URL(
			fileURLWithPath: "/private/tmp/mac-apper-create-evidence-\(UUID().uuidString)")
		try manager.createDirectory(
			at: archive, withIntermediateDirectories: false, attributes: [.posixPermissions: 0o700])
		print("CREATE_EVIDENCE_RETAINED: \(archive.path)")
		for (source, target) in [
			(project.appendingPathComponent(".pi/sessions"), archive.appendingPathComponent("sessions")),
			(
				project.appendingPathComponent(".pi/agent-events"),
				archive.appendingPathComponent("agent-events")
			),
			(
				home.appendingPathComponent(".mac-apper/previews/\(project.lastPathComponent)"),
				archive.appendingPathComponent("previews")
			),
		] where manager.fileExists(atPath: source.path) {
			var count = 0
			func copy(_ source: URL, _ target: URL) throws {
				count += 1
				try #require(count <= 256)
				let values = try source.resourceValues(forKeys: [
					.isDirectoryKey, .isRegularFileKey, .isSymbolicLinkKey, .fileSizeKey,
				])
				try #require(values.isSymbolicLink != true)
				if values.isDirectory == true {
					try manager.createDirectory(
						at: target, withIntermediateDirectories: false, attributes: [.posixPermissions: 0o700])
					for child in try manager.contentsOfDirectory(at: source, includingPropertiesForKeys: nil)
					{ try copy(child, target.appendingPathComponent(child.lastPathComponent)) }
				} else {
					try #require(values.isRegularFile == true && (values.fileSize ?? Int.max) <= 16_777_216)
					try #require(
						manager.createFile(
							atPath: target.path, contents: Data(contentsOf: source),
							attributes: [.posixPermissions: 0o600]))
				}
			}
			try copy(source, target)
		}
	}
}
