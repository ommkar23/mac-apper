// @frontmatter:start
// Tests deployed-app scenario host rejection and cleanup without running XPC or live APIs.
// @frontmatter:end
import Foundation
@testable import Scenario
import Testing

@Test @MainActor func deployedHostPreservesResourcesIsolatesIdentitiesAndCleansOnlyItsCopy() throws
{
	let manager = FileManager.default
	let directory = manager.temporaryDirectory.appendingPathComponent(UUID().uuidString)
	try manager.createDirectory(at: directory, withIntermediateDirectories: false)
	defer { try? manager.removeItem(at: directory) }
	let source = directory.appendingPathComponent("Fixture.app")
	let service = source.appendingPathComponent("Contents/XPCServices/FixtureService.xpc")
	for bundle in [service, source] {
		let macOS = bundle.appendingPathComponent("Contents/MacOS")
		try manager.createDirectory(at: macOS, withIntermediateDirectories: true)
		try manager.copyItem(
			at: URL(fileURLWithPath: "/usr/bin/true"), to: macOS.appendingPathComponent("FixtureClient"))
		let info = [
			"CFBundleIdentifier": "com.macapper.fixture", "CFBundleExecutable": "FixtureClient",
			"CFBundlePackageType": bundle.pathExtension == "xpc" ? "XPC!" : "APPL",
		]
		try PropertyListSerialization.data(fromPropertyList: info, format: .xml, options: 0)
			.write(to: bundle.appendingPathComponent("Contents/Info.plist"))
		let resources = bundle.appendingPathComponent("Contents/Resources")
		try manager.createDirectory(at: resources, withIntermediateDirectories: true)
		try Data("fixture resource".utf8).write(to: resources.appendingPathComponent("fixture.txt"))
		try ScenarioProcess.run("/usr/bin/codesign", ["--force", "--sign", "-", bundle.path])
	}
	let host = PackagedApplicationHost(
		deployedApp: source, clientExecutable: URL(fileURLWithPath: "/usr/bin/true"))
	try host.prepare()
	defer { try? host.remove() }
	let staged = try #require(host.app)
	#expect(staged != source)
	#expect(
		try Data(contentsOf: staged.appendingPathComponent("Contents/Resources/fixture.txt"))
			== Data(contentsOf: source.appendingPathComponent("Contents/Resources/fixture.txt")))
	#expect(
		manager.isExecutableFile(atPath: staged.appendingPathComponent("Contents/MacOS/true").path))
	var ids = Set<String>()
	for relative in [
		"Contents/Info.plist", "Contents/XPCServices/FixtureService.xpc/Contents/Info.plist",
	] {
		let original = try #require(
			PropertyListSerialization.propertyList(
				from: Data(contentsOf: source.appendingPathComponent(relative)), format: nil)
				as? [String: String])
		let copied = try #require(
			PropertyListSerialization.propertyList(
				from: Data(contentsOf: staged.appendingPathComponent(relative)), format: nil)
				as? [String: String])
		#expect(original["CFBundleIdentifier"] == "com.macapper.fixture")
		let id = try #require(copied["CFBundleIdentifier"])
		#expect(id.hasPrefix("com.macapper.scenario."))
		#expect(ids.insert(id).inserted)
	}
	#expect(throws: (any Error).self) { try host.prepare() }
	try host.remove()
	#expect(!manager.fileExists(atPath: staged.path))
	#expect(manager.fileExists(atPath: source.path))
	#expect(host.app == nil)
	let retained = PackagedApplicationHost(deployedApp: source)
	try retained.prepare()
	defer { try? retained.remove() }
	let retainedApp = try #require(retained.app)
	let retainedInfo = try #require(
		PropertyListSerialization.propertyList(
			from: Data(contentsOf: retainedApp.appendingPathComponent("Contents/Info.plist")), format: nil
		) as? [String: String])
	#expect(retainedInfo["CFBundleExecutable"] == "FixtureClient")
	#expect(
		manager.isExecutableFile(
			atPath: retainedApp.appendingPathComponent("Contents/MacOS/FixtureClient").path))
	#expect(
		!manager.fileExists(atPath: retainedApp.appendingPathComponent("Contents/MacOS/true").path))
	try retained.remove()
	#expect(!manager.fileExists(atPath: retainedApp.path))
}

@Test @MainActor func deployedHostRejectsCallsBeforePreparation() throws {
	let host = PackagedApplicationHost(
		deployedApp: URL(fileURLWithPath: "/tmp/unused.app"),
		clientExecutable: URL(fileURLWithPath: "/usr/bin/true"))
	#expect(throws: (any Error).self) { try host.run(arguments: []) }
	try host.remove()
	try host.remove()
	#expect(host.app == nil)
}

@Test @MainActor func deployedHostRejectsLinkedAppWithoutDeletingItsSource() throws {
	let manager = FileManager.default
	let directory = manager.temporaryDirectory.appendingPathComponent(UUID().uuidString)
	try manager.createDirectory(at: directory, withIntermediateDirectories: false)
	defer { try? manager.removeItem(at: directory) }
	let source = directory.appendingPathComponent("Source.app")
	try manager.createDirectory(at: source, withIntermediateDirectories: false)
	let linked = directory.appendingPathComponent("Linked.app")
	try manager.createSymbolicLink(at: linked, withDestinationURL: source)
	let host = PackagedApplicationHost(
		deployedApp: linked,
		clientExecutable: URL(fileURLWithPath: "/usr/bin/true"))
	#expect(throws: (any Error).self) { try host.prepare() }
	try host.remove()
	#expect(host.app == nil)
	#expect(manager.fileExists(atPath: source.path))
}

@Test @MainActor func deployedHostRejectsUnsignedAppAndLeavesSourceIntact() throws {
	let manager = FileManager.default
	let directory = manager.temporaryDirectory.appendingPathComponent(UUID().uuidString)
	try manager.createDirectory(at: directory, withIntermediateDirectories: false)
	defer { try? manager.removeItem(at: directory) }
	let source = directory.appendingPathComponent("Unsigned.app")
	try manager.createDirectory(at: source, withIntermediateDirectories: false)
	let host = PackagedApplicationHost(
		deployedApp: source,
		clientExecutable: URL(fileURLWithPath: "/usr/bin/true"))
	#expect(throws: (any Error).self) { try host.prepare() }
	try host.remove()
	#expect(host.app == nil)
	#expect(manager.fileExists(atPath: source.path))
}
