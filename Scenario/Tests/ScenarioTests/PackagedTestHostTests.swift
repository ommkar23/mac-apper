// @frontmatter:start
// Tests scoped Swift test hosting, nested provider resources, isolated identities, and cleanup without invoking live services.
// @frontmatter:end
import Foundation
import Scenario
import Testing

@Test @MainActor func testHostStagesOnlyItsDeclaredInputsAndCleansUp() throws {
	let manager = FileManager.default
	let fixture = try ProjectTemporaryDirectory.root().appendingPathComponent(
		"scenario-test-fixture-\(UUID().uuidString)")
	try manager.createDirectory(at: fixture, withIntermediateDirectories: false)
	defer { try? manager.removeItem(at: fixture) }
	func plist(_ name: String, executable: String, package: String) throws -> URL {
		let url = fixture.appendingPathComponent(name)
		try PropertyListSerialization.data(
			fromPropertyList: [
				"CFBundleIdentifier": "com.macapper.fixture", "CFBundleExecutable": executable,
				"CFBundlePackageType": package,
			], format: .xml, options: 0
		).write(to: url)
		return url
	}
	let executable = fixture.appendingPathComponent("FixtureService")
	try manager.copyItem(at: URL(fileURLWithPath: "/usr/bin/true"), to: executable)
	let service = TestHostService(
		bundleName: "FixtureService.xpc", executable: executable,
		infoPlist: try plist("service.plist", executable: "FixtureService", package: "XPC!"),
		environment: ["HOME": fixture.path, "CFFIXED_USER_HOME": fixture.path])
	let resource = fixture.appendingPathComponent("Extension.ts")
	try Data("fixture".utf8).write(to: resource)
	let provider = TestHostApplication(
		bundleName: "Web.app", executable: executable,
		infoPlist: try plist("app.plist", executable: "FixtureService", package: "APPL"),
		services: [service],
		resources: [TestHostResource(source: resource, relativePath: "PiExtension/Extension.ts")])
	let host = PackagedTestHost(
		testBundleExecutable: executable, loader: URL(fileURLWithPath: "/usr/bin/true"),
		services: [service], applications: [provider], resources: [])
	#expect(throws: (any Error).self) { try host.runTest(filter: "unused") }
	try host.prepare()
	defer { try? host.remove() }
	let app = try #require(host.app)
	#expect(
		manager.fileExists(atPath: app.appendingPathComponent("Contents/Resources/TestBundle").path))
	#expect(
		try Data(
			contentsOf: app.appendingPathComponent(
				"Contents/Applications/Web.app/Contents/Resources/PiExtension/Extension.ts"))
			== Data("fixture".utf8))
	var identifiers = Set<String>()
	for path in [
		"Contents/Info.plist", "Contents/XPCServices/FixtureService.xpc/Contents/Info.plist",
		"Contents/Applications/Web.app/Contents/Info.plist",
		"Contents/Applications/Web.app/Contents/XPCServices/FixtureService.xpc/Contents/Info.plist",
	] {
		let info = try #require(
			PropertyListSerialization.propertyList(
				from: Data(contentsOf: app.appendingPathComponent(path)), format: nil) as? [String: Any])
		let identifier = try #require(info["CFBundleIdentifier"] as? String)
		#expect(identifier.hasPrefix("com.macapper.scenario."))
		#expect(identifiers.insert(identifier).inserted)
		if path.contains(".xpc/") {
			let xpc = try #require(info["XPCService"] as? [String: Any])
			let environment = try #require(xpc["EnvironmentVariables"] as? [String: String])
			#expect(environment["HOME"] == fixture.path)
			#expect(environment["CFFIXED_USER_HOME"] == fixture.path)
		}
	}
	#expect(
		!manager.fileExists(
			atPath: app.appendingPathComponent("Contents/Applications/DevTools.app").path))
	#expect(throws: (any Error).self) { try host.prepare() }
	try host.remove()
	try host.remove()
	#expect(host.app == nil)
	#expect(!manager.fileExists(atPath: app.path))
	#expect(manager.fileExists(atPath: fixture.path))
}

@Test @MainActor func testHostRejectsTraversingResourceDestinationsAndRemovesPartialSetup() throws {
	let host = PackagedTestHost(
		testBundleExecutable: URL(fileURLWithPath: "/usr/bin/true"),
		loader: URL(fileURLWithPath: "/usr/bin/true"), services: [], applications: [],
		resources: [
			TestHostResource(source: URL(fileURLWithPath: "/usr/bin/true"), relativePath: "../escape")
		])
	#expect(throws: (any Error).self) { try host.prepare() }
	#expect(host.app == nil)
	try host.remove()
}
