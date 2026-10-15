// @frontmatter:start
// Tests XPC host resource staging, pre-signing environment precedence, client overrides and unsafe-input rejection.
// @frontmatter:end
import Foundation
@testable import Scenario
import Testing

@MainActor private func resourceHost(
	_ fixture: URL, resource: TestHostResource,
	serviceEnvironment: [String: String] = [:], clientEnvironment: [String: String] = [:]
) throws
	-> PackagedXPCHost
{
	let executable = fixture.appendingPathComponent("FixtureClient")
	try FileManager.default.copyItem(at: URL(fileURLWithPath: "/usr/bin/true"), to: executable)
	func plist(_ name: String, package: String) throws -> URL {
		let url = fixture.appendingPathComponent(name)
		try PropertyListSerialization.data(
			fromPropertyList: [
				"CFBundleIdentifier": "com.macapper.fixture", "CFBundleExecutable": "FixtureClient",
				"CFBundlePackageType": package,
				"XPCService": [
					"ServiceType": "Application",
					"EnvironmentVariables": [
						"HOME": "inherited", "KEEP": "preserved", "TMPDIR": "/wrong-plist",
					],
				],
			], format: .xml, options: 0
		).write(to: url)
		return url
	}
	return try PackagedXPCHost(
		XPCHostDefinition(
			appName: "ResourceFixture", clientExecutable: executable, serviceExecutable: executable,
			appPlist: plist("app.plist", package: "APPL"),
			servicePlist: plist("service.plist", package: "XPC!"),
			appResources: [resource], serviceResources: [resource],
			serviceEnvironment: serviceEnvironment, clientEnvironment: clientEnvironment))
}

@Test @MainActor func xpcHostEnvironmentPrecedenceBeforeSigningAndSending() throws {
	let manager = FileManager.default
	let fixture = try ProjectTemporaryDirectory.root().appendingPathComponent(UUID().uuidString)
	try manager.createDirectory(at: fixture, withIntermediateDirectories: false)
	defer { try? manager.removeItem(at: fixture) }
	let source = fixture.appendingPathComponent("resource")
	try Data().write(to: source)
	let host = try resourceHost(
		fixture, resource: TestHostResource(source: source, relativePath: "resource"),
		serviceEnvironment: [
			"HOME": fixture.path, "CFFIXED_USER_HOME": fixture.path, "TMPDIR": "/wrong",
		],
		clientEnvironment: [
			"HOME": fixture.path, "CFFIXED_USER_HOME": fixture.path,
			"OPENXPC_PROJECT_ID": "wrong", "OPENXPC_SESSION_ID": "wrong", "TMPDIR": "/wrong",
		])
	try host.prepare()
	defer { try? host.remove() }
	let app = try #require(host.app)
	let info = try #require(
		PropertyListSerialization.propertyList(
			from: Data(
				contentsOf: app.appendingPathComponent(
					"Contents/XPCServices/FixtureClient.xpc/Contents/Info.plist")),
			format: nil) as? [String: Any])
	let xpc = try #require(info["XPCService"] as? [String: Any])
	let env = try #require(xpc["EnvironmentVariables"] as? [String: String])
	#expect(xpc["ServiceType"] as? String == "Application")
	#expect(env["HOME"] == fixture.path)
	#expect(env["CFFIXED_USER_HOME"] == fixture.path)
	#expect(env["KEEP"] == "preserved")
	#expect(env["TMPDIR"] == (try ProjectTemporaryDirectory.environment())["TMPDIR"])
	let project = UUID(), session = UUID()
	host.clientCall = { _, request, environment, _ in
		#expect(environment["HOME"] == fixture.path)
		#expect(environment["CFFIXED_USER_HOME"] == fixture.path)
		#expect(environment["OPENXPC_PROJECT_ID"] == project.uuidString)
		#expect(environment["OPENXPC_SESSION_ID"] == session.uuidString)
		// Exercise the existing adapter's final TMPDIR precedence with a local double, not XPC.
		let script = fixture.appendingPathComponent("environment-client")
		try Data(
			"""
			#!/bin/sh
			IFS= read -r line
			[ "$HOME" = "$EXPECTED_HOME" ] && [ "$CFFIXED_USER_HOME" = "$EXPECTED_HOME" ] || exit 2
			[ "$OPENXPC_PROJECT_ID" = "$EXPECTED_PROJECT" ] && [ "$OPENXPC_SESSION_ID" = "$EXPECTED_SESSION" ] || exit 3
			printf '%s\\n' "$TMPDIR"

			""".utf8
		).write(to: script)
		try manager.setAttributes([.posixPermissions: 0o700], ofItemAtPath: script.path)
		let result = try XPCClientAdapter().call(
			script, request: Data("{}".utf8),
			environment: environment.merging([
				"EXPECTED_HOME": fixture.path, "EXPECTED_PROJECT": project.uuidString,
				"EXPECTED_SESSION": session.uuidString,
			]) { _, expected in expected })
		#expect(result.status == 0)
		#expect(
			String(decoding: result.data, as: UTF8.self)
				== (try ProjectTemporaryDirectory.environment())["TMPDIR"])
		var record = try #require(JSONSerialization.jsonObject(with: request) as? [String: Any])
		record["success"] = true
		record["payload"] = Data("{}".utf8).base64EncodedString()
		return XPCClientAdapter.Reply(
			status: 0, data: try JSONSerialization.data(withJSONObject: record))
	}
	_ = try host.request("fixture", payload: [:], projectID: project, sessionID: session)
}

@Test func xpcHostDefinitionDefaultsRemainEmpty() throws {
	let url = URL(fileURLWithPath: "/unused")
	let definition = try XPCHostDefinition(
		appName: "Defaults", clientExecutable: url,
		serviceExecutable: url, appPlist: url, servicePlist: url)
	#expect(definition.serviceEnvironment.isEmpty)
	#expect(definition.clientEnvironment.isEmpty)
}

@Test @MainActor func xpcHostStagesDeclaredResourcesBeforeSigning() throws {
	let manager = FileManager.default
	let fixture = try ProjectTemporaryDirectory.root().appendingPathComponent(UUID().uuidString)
	try manager.createDirectory(at: fixture, withIntermediateDirectories: false)
	defer { try? manager.removeItem(at: fixture) }
	let source = fixture.appendingPathComponent("Renderer.swift")
	try Data("fixture-renderer".utf8).write(to: source)
	let host = try resourceHost(
		fixture, resource: TestHostResource(source: source, relativePath: "Renderer.swift"))
	try host.prepare()
	defer { try? host.remove() }
	let app = try #require(host.app)
	for path in [
		"Contents/Resources/Renderer.swift",
		"Contents/XPCServices/FixtureClient.xpc/Contents/Resources/Renderer.swift",
	] {
		#expect(try Data(contentsOf: app.appendingPathComponent(path)) == Data("fixture-renderer".utf8))
	}
	try host.remove()
	#expect(!manager.fileExists(atPath: app.path))
	#expect(manager.fileExists(atPath: source.path))
}

@Test @MainActor func xpcHostRejectsUnsafeResourcesAndCleansPartialSetup() throws {
	for linked in [false, true] {
		let manager = FileManager.default
		let fixture = try ProjectTemporaryDirectory.root().appendingPathComponent(UUID().uuidString)
		try manager.createDirectory(at: fixture, withIntermediateDirectories: false)
		defer { try? manager.removeItem(at: fixture) }
		let source = fixture.appendingPathComponent("resource")
		if linked {
			try manager.createSymbolicLink(
				at: source, withDestinationURL: URL(fileURLWithPath: "/usr/bin/true"))
		} else {
			try Data("fixture".utf8).write(to: source)
		}
		let host = try resourceHost(
			fixture,
			resource: TestHostResource(source: source, relativePath: linked ? "resource" : "../escape"))
		#expect(throws: (any Error).self) { try host.prepare() }
		#expect(host.app == nil)
		try host.remove()
	}
}
