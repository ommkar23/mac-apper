import Foundation
import Scenario
import Testing

@Test func isolatedHomeRetainsHostOnUnconfirmedOrFailedCleanup() throws {
	let home = try IsolatedScenarioHome()
	defer { try? home.remove(cleanupConfirmed: true) }
	var events: [String] = []
	#expect(throws: (any Error).self) {
		try home.finishHost(
			cleanupConfirmed: false, removeFixtures: true, stopServices: { events.append("stop") },
			removeHost: { events.append("remove") })
	}
	#expect(events.isEmpty)
	#expect(
		try home.finishHost(
			cleanupConfirmed: true, removeFixtures: false, stopServices: { events.append("stop") },
			removeHost: { events.append("remove") }) == false)
	#expect(events == ["stop"])
	events = []
	#expect(throws: (any Error).self) {
		try home.finishHost(
			cleanupConfirmed: true, removeFixtures: true,
			stopServices: {
				events.append("stop"); throw ScenarioFailure.message("synthetic cleanup failure")
			}, removeHost: { events.append("remove") })
	}
	#expect(events == ["stop"])
	#expect(FileManager.default.fileExists(atPath: home.directory.path))
}

@Test func isolatedHomeScopesStorageAndCopiesOnlySelectedPrivateCredential() throws {
	let home = try IsolatedScenarioHome()
	defer { try? home.remove(cleanupConfirmed: true) }
	let fixture = home.directory.appendingPathComponent("fixture.json")
	try Data(
		#"{"wanted":{"type":"oauth","access":"synthetic"},"unrelated":{"key":"not-copied"}}"#.utf8
	).write(to: fixture)
	try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: fixture.path)
	let target = try home.stageCredentialEntry(
		from: fixture, key: "wanted", relativePath: ".pi/agent/auth.json")
	let data = try Data(contentsOf: target)
	let json = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
	#expect(Set(json.keys) == ["wanted"])
	#expect(home.environment["HOME"] == home.directory.path)
	#expect(home.environment["CFFIXED_USER_HOME"] == home.directory.path)
	#expect(throws: (any Error).self) { try home.remove(cleanupConfirmed: false) }
	#expect(FileManager.default.fileExists(atPath: home.directory.path))
	try home.scrubCredentials()
	#expect(!FileManager.default.fileExists(atPath: target.path))
	let projected = try home.stageCredentialEntry(
		from: fixture, key: "wanted", relativePath: "projected.json",
		project: { entry in ["type": entry["type"]!, "refresh": ""] })
	let projectedJSON = try #require(
		JSONSerialization.jsonObject(with: Data(contentsOf: projected)) as? [String: [String: String]])
	#expect(projectedJSON["wanted"] == ["type": "oauth", "refresh": ""])
	try home.scrubCredentials()
	#expect(!FileManager.default.fileExists(atPath: projected.path))
}

@Test func isolatedHomeRejectsUnsafeCredentialsAndPaths() throws {
	let home = try IsolatedScenarioHome()
	defer { try? home.remove(cleanupConfirmed: true) }
	let fixture = home.directory.appendingPathComponent("unsafe.json")
	try Data(#"{"wanted":{"type":"oauth","access":"synthetic"}}"#.utf8).write(to: fixture)
	try FileManager.default.setAttributes([.posixPermissions: 0o644], ofItemAtPath: fixture.path)
	#expect(throws: (any Error).self) {
		try home.stageCredentialEntry(from: fixture, key: "wanted", relativePath: "auth.json")
	}
	try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: fixture.path)
	let link = home.directory.appendingPathComponent("link.json")
	try FileManager.default.createSymbolicLink(at: link, withDestinationURL: fixture)
	#expect(throws: (any Error).self) {
		try home.stageCredentialEntry(from: link, key: "wanted", relativePath: "auth.json")
	}
	#expect(throws: (any Error).self) {
		try home.stageCredentialEntry(from: fixture, key: "wanted", relativePath: "../escape")
	}
	#expect(throws: (any Error).self) {
		try home.stageCredentialEntry(from: fixture, key: "absent", relativePath: "auth.json")
	}
	let linkedParent = home.directory.appendingPathComponent("linked-parent")
	try FileManager.default.createSymbolicLink(at: linkedParent, withDestinationURL: home.directory)
	#expect(throws: (any Error).self) {
		try home.stageCredentialEntry(
			from: linkedParent.appendingPathComponent("unsafe.json"), key: "wanted",
			relativePath: "other-auth.json")
	}
}
