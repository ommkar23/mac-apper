// @frontmatter:start
// Tests signed XPC host resource staging, scoped destination validation, and rejection of linked resources.
// @frontmatter:end
import Foundation
import Scenario
import Testing

@MainActor private func resourceHost(_ fixture: URL, resource: TestHostResource) throws
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
			], format: .xml, options: 0
		).write(to: url)
		return url
	}
	return try PackagedXPCHost(
		XPCHostDefinition(
			appName: "ResourceFixture", clientExecutable: executable, serviceExecutable: executable,
			appPlist: plist("app.plist", package: "APPL"),
			servicePlist: plist("service.plist", package: "XPC!"),
			appResources: [resource], serviceResources: [resource]))
}

@Test @MainActor func xpcHostStagesDeclaredResourcesBeforeSigning() throws {
	let manager = FileManager.default
	let fixture = manager.temporaryDirectory.appendingPathComponent(UUID().uuidString)
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
		let fixture = manager.temporaryDirectory.appendingPathComponent(UUID().uuidString)
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
