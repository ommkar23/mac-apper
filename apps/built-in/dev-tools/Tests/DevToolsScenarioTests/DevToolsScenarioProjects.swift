// @frontmatter:start
// Creates and removes only UUID-scoped project fixtures required by the packaged DevTools service.
// @frontmatter:end
import Foundation
import Scenario

@MainActor final class DevToolsScenarioProjects {
	private let root: URL

	init(
		root: URL = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".mac-apper")
	) {
		self.root = root
	}
	private var rootCreated = false
	private var owned: [URL] = []
	private var removed = Set<String>()

	func create(afterDirectory: (URL) throws -> Void = { _ in }) throws -> (id: UUID, url: URL) {
		let manager = FileManager.default
		if manager.fileExists(atPath: root.path) {
			let values = try root.resourceValues(forKeys: [.isDirectoryKey, .isSymbolicLinkKey])
			guard
				values.isDirectory == true,
				values.isSymbolicLink != true
			else { throw ScenarioFailure.message("unsafe DevTools projects root") }
		} else {
			try manager.createDirectory(
				at: root, withIntermediateDirectories: false, attributes: [.posixPermissions: 0o700])
			rootCreated = true
		}
		let id = UUID()
		let name = id.uuidString.lowercased()
		let url = root.appendingPathComponent(name)
		try manager.createDirectory(
			at: url, withIntermediateDirectories: false, attributes: [.posixPermissions: 0o700])
		owned.append(url)
		try afterDirectory(url)
		let manifest: [String: Any] = [
			"schemaVersion": 1, "appID": name, "executableTarget": "ProductionApp",
			"previewTarget": "PreviewApp", "devServiceID": "com.macapper.generated.\(name)",
		]
		try JSONSerialization.data(withJSONObject: manifest).write(
			to: url.appendingPathComponent("app-manifest.json"))
		try "// swift-tools-version: 6.1\n".write(
			to: url.appendingPathComponent("Package.swift"), atomically: true, encoding: .utf8)
		return (id, url)
	}

	func remove(_ url: URL) throws {
		let manager = FileManager.default
		guard
			url.isFileURL
		else { throw ScenarioFailure.message("unregistered DevTools project") }
		if removed.contains(url.path) {
			do {
				_ = try manager.attributesOfItem(atPath: url.path)
				throw ScenarioFailure.message("removed DevTools project reappeared")
			} catch let error as NSError
				where error.domain == NSCocoaErrorDomain
				&& [NSFileNoSuchFileError, NSFileReadNoSuchFileError].contains(error.code)
			{
				return
			}
		}
		guard
			let index = owned.firstIndex(where: { $0.path == url.path })
		else { throw ScenarioFailure.message("unregistered DevTools project") }
		for directory in [root, owned[index]] {
			let values = try URL(fileURLWithPath: directory.path).resourceValues(
				forKeys: [.isDirectoryKey, .isSymbolicLinkKey])
			guard
				values.isDirectory == true, values.isSymbolicLink != true
			else { throw ScenarioFailure.message("unsafe or disappeared DevTools project") }
		}
		try manager.removeItem(at: owned[index])
		owned.remove(at: index)
		removed.insert(url.path)
	}

	func remove() throws {
		let manager = FileManager.default
		while let url = owned.last { try remove(url) }
		if rootCreated {
			let entries = try manager.contentsOfDirectory(atPath: root.path)
			if entries.isEmpty { try manager.removeItem(at: root) }
			rootCreated = false
		}
	}
}
