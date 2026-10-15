// @frontmatter:start
// Tests scoped naming through generated routing, Unicode sanitation, and unchanged metadata on rejection.
// @frontmatter:end
import Darwin
import Foundation
import Scenario
import Testing

@testable import DevToolsApplication

@Test func setAppNameRoutesCanonicalBrandingAndPreservesMetadata() async throws {
	let fixture = try NamingFixture()
	defer { fixture.remove() }
	let router = OpenXPCGeneratedService(
		controllers: ControllerFactory(projectsRoot: fixture.root).controllers())
	let response = try await fixture.call(router, name: "  Full / Name: & \"Quotes\".app.APP  ")
	#expect(response["success"] as? Bool == true)
	let encoded = try #require(response["payload"] as? String)
	let payload = try #require(Data(base64Encoded: encoded))
	let result = try #require(JSONSerialization.jsonObject(with: payload) as? [String: Any])
	#expect(result["name"] as? String == "Full Name & \"Quotes\"")
	#expect(result["summary"] as? String == "App name set to Full Name & \"Quotes\".")
	let plist = try fixture.plist()
	#expect(plist["CFBundleDisplayName"] as? String == "Full Name & \"Quotes\"")
	#expect(plist["CFBundleName"] as? String == "Full Name & \"Quotes\"")
	#expect(plist["CFBundleIdentifier"] as? String == "com.fixture.identity")
	#expect(plist["CFBundleExecutable"] as? String == "ProductionApp")
	#expect(plist["CFBundleVersion"] as? String == "27")
	#expect(plist["Unrelated"] as? [String: [Int]] == ["values": [1, 2, 3]])
	let names = try FileManager.default.contentsOfDirectory(atPath: fixture.project.path)
	#expect(Set(names) == ["Package.swift", "app-manifest.json", "Info.plist"])
}

@Test func setAppNamePreservesUnicodeCodePointSemantics() async throws {
	let fixture = try NamingFixture()
	defer { fixture.remove() }
	let router = OpenXPCGeneratedService(
		controllers: ControllerFactory(projectsRoot: fixture.root).controllers())
	for (input, expected) in [
		(String(repeating: "界", count: 64), String(repeating: "界", count: 64)),
		(String(repeating: "😀", count: 64), String(repeating: "😀", count: 64)),
		(String(repeating: "e\u{301}", count: 32), String(repeating: "e\u{301}", count: 32)),
		("\u{FEFF}One\u{A0}Two\u{2028}Three\u{FEFF}.app", "One Two Three"),
		("A\u{85}B", "A\u{85}B"),
		("A\u{0}\u{7F}B", "A B"),
	] {
		let response = try await fixture.call(router, name: input)
		#expect(response["success"] as? Bool == true)
		#expect(try fixture.plist()["CFBundleDisplayName"] as? String == expected)
	}
	let before = try Data(contentsOf: fixture.metadata)
	for invalid in [String(repeating: "e\u{301}", count: 33), String(repeating: "😀", count: 65)] {
		let response = try await fixture.call(router, name: invalid)
		#expect(response["success"] as? Bool == false)
		#expect(try Data(contentsOf: fixture.metadata) == before)
	}
}

@Test func setAppNameRejectsInvalidNamesAndScopeWithoutMutation() async throws {
	let fixture = try NamingFixture()
	defer { fixture.remove() }
	let router = OpenXPCGeneratedService(
		controllers: ControllerFactory(projectsRoot: fixture.root).controllers())
	let before = try Data(contentsOf: fixture.metadata)
	for invalid in ["", " / : ", ".", "..", ".hidden", String(repeating: "B", count: 65)] {
		let response = try await fixture.call(router, name: invalid)
		#expect(response["success"] as? Bool == false)
		#expect(try Data(contentsOf: fixture.metadata) == before)
	}
	let foreign = try await fixture.call(router, name: "Foreign", projectRoot: fixture.root.path)
	#expect(foreign["success"] as? Bool == false)
	#expect(try Data(contentsOf: fixture.metadata) == before)
}

@Test func setAppNameRejectsUnsafeOrMalformedMetadataWithoutMutation() async throws {
	let fixture = try NamingFixture()
	defer { fixture.remove() }
	let router = OpenXPCGeneratedService(
		controllers: ControllerFactory(projectsRoot: fixture.root).controllers())
	let array = try PropertyListSerialization.data(
		fromPropertyList: ["not a dictionary"], format: .xml, options: 0)
	for data in [Data(), Data("not a plist".utf8), array, Data(repeating: 32, count: 16_385)] {
		try data.write(to: fixture.metadata)
		let response = try await fixture.call(router, name: "Changed")
		#expect(response["success"] as? Bool == false)
		#expect(try Data(contentsOf: fixture.metadata) == data)
	}
	try FileManager.default.removeItem(at: fixture.metadata)
	let missing = try await fixture.call(router, name: "Changed")
	#expect(missing["success"] as? Bool == false)
	#expect(!FileManager.default.fileExists(atPath: fixture.metadata.path))
	let external = fixture.root.appendingPathComponent("external.plist")
	try Data("external unchanged".utf8).write(to: external)
	try FileManager.default.createSymbolicLink(at: fixture.metadata, withDestinationURL: external)
	let linked = try await fixture.call(router, name: "Changed")
	#expect(linked["success"] as? Bool == false)
	#expect(try Data(contentsOf: external) == Data("external unchanged".utf8))
	#expect(try fixture.metadata.resourceValues(forKeys: [.isSymbolicLinkKey]).isSymbolicLink == true)
	try FileManager.default.removeItem(at: fixture.metadata)
	try FileManager.default.createDirectory(at: fixture.metadata, withIntermediateDirectories: false)
	let directory = try await fixture.call(router, name: "Changed")
	#expect(directory["success"] as? Bool == false)
	#expect(try FileManager.default.contentsOfDirectory(atPath: fixture.metadata.path).isEmpty)
	try FileManager.default.removeItem(at: fixture.metadata)
	try #require(mkfifo(fixture.metadata.path, 0o600) == 0)
	let fifo = try await fixture.call(router, name: "Changed")
	#expect(fifo["success"] as? Bool == false)
	var status = stat()
	#expect(lstat(fixture.metadata.path, &status) == 0)
	#expect((status.st_mode & S_IFMT) == S_IFIFO)
}

@Test func setAppNameRejectsBusyGateWithoutMutation() async throws {
	let fixture = try NamingFixture()
	defer { fixture.remove() }
	let gate = DevToolsOperationGate()
	let controller = SetAppNameController(
		projects: ProjectResolver(projectsRoot: fixture.root), gate: gate)
	let request = try SetAppNameRequest(projectRoot: fixture.project.path, name: "Changed")
	let before = try Data(contentsOf: fixture.metadata)
	await #expect(throws: (any Error).self) {
		try await gate.run {
			try await controller.handle(fixture.projectID, fixture.sessionID, request)
		}
	}
	#expect(try Data(contentsOf: fixture.metadata) == before)
	let result = try await controller.handle(fixture.projectID, fixture.sessionID, request)
	#expect(result.name == "Changed")
}

@Test func setAppNameBoundsReplacementAndPreservesXMLAndPrivatePermissions() async throws {
	let fixture = try NamingFixture()
	defer { fixture.remove() }
	let router = OpenXPCGeneratedService(
		controllers: ControllerFactory(projectsRoot: fixture.root).controllers())
	let xml = try PropertyListSerialization.data(
		fromPropertyList: ["Unrelated": "retain"], format: .xml, options: 0)
	try xml.write(to: fixture.metadata)
	let response = try await fixture.call(router, name: "Changed")
	#expect(response["success"] as? Bool == true)
	#expect(try fixture.plist()["Unrelated"] as? String == "retain")
	#expect(try String(contentsOf: fixture.metadata, encoding: .utf8).contains("<?xml"))
	let attributes = try FileManager.default.attributesOfItem(atPath: fixture.metadata.path)
	#expect((attributes[.posixPermissions] as? NSNumber)?.intValue == 0o600)
	let large = try PropertyListSerialization.data(
		fromPropertyList: ["Unrelated": String(repeating: "x", count: 16_300)], format: .binary,
		options: 0)
	try #require(large.count <= 16_384)
	try large.write(to: fixture.metadata)
	let overflow = try await fixture.call(router, name: String(repeating: "😀", count: 64))
	#expect(overflow["success"] as? Bool == false)
	#expect(try Data(contentsOf: fixture.metadata) == large)
	#expect(try FileManager.default.contentsOfDirectory(atPath: fixture.project.path).count == 3)
}

private struct NamingFixture {
	let root: URL
	let projectID = UUID()
	let sessionID = UUID()
	var project: URL { root.appendingPathComponent(projectID.uuidString.lowercased()) }
	var metadata: URL { project.appendingPathComponent("Info.plist") }

	init() throws {
		root = try ProjectTemporaryDirectory.root().appendingPathComponent(UUID().uuidString)
		try FileManager.default.createDirectory(
			at: project, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
		try Data("// swift-tools-version: 6.0\n".utf8).write(
			to: project.appendingPathComponent("Package.swift"))
		let id = projectID.uuidString.lowercased()
		try Data(
			"{\"schemaVersion\":1,\"appID\":\"\(id)\",\"executableTarget\":\"ProductionApp\",\"previewTarget\":\"PreviewApp\",\"devServiceID\":\"com.macapper.generated.\(id)\"}"
				.utf8
		)
		.write(to: project.appendingPathComponent("app-manifest.json"))
		try PropertyListSerialization.data(
			fromPropertyList: [
				"CFBundleDisplayName": "Generated App", "CFBundleName": "Generated App",
				"CFBundleIdentifier": "com.fixture.identity", "CFBundleExecutable": "ProductionApp",
				"CFBundleVersion": "27", "Unrelated": ["values": [1, 2, 3]],
			], format: .binary, options: 0
		).write(to: metadata)
	}

	func plist() throws -> [String: Any] {
		try #require(
			PropertyListSerialization.propertyList(
				from: Data(contentsOf: metadata), options: [], format: nil) as? [String: Any])
	}

	func call(_ router: OpenXPCGeneratedService, name: String, projectRoot: String? = nil)
		async throws -> [String: Any]
	{
		let requestID = UUID()
		let payload = try JSONSerialization.data(withJSONObject: [
			"projectRoot": projectRoot ?? project.path, "name": name,
		])
		let request = try JSONSerialization.data(withJSONObject: [
			"version": 1, "requestID": requestID.uuidString, "projectID": projectID.uuidString,
			"sessionID": sessionID.uuidString, "command": "set_app_name",
			"payload": payload.base64EncodedString(),
		])
		let reply = await withCheckedContinuation { continuation in
			router.execute(request) { continuation.resume(returning: $0) }
		}
		let response = try #require(JSONSerialization.jsonObject(with: reply) as? [String: Any])
		#expect(response["requestID"] as? String == requestID.uuidString)
		return response
	}

	func remove() { try? FileManager.default.removeItem(at: root) }
}
