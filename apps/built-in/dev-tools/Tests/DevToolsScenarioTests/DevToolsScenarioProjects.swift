// @frontmatter:start
// Creates and removes only UUID-scoped project fixtures required by the packaged DevTools service.
// @frontmatter:end
import Foundation
import Scenario

@MainActor final class DevToolsScenarioProjects {
	private let root = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(
		".mac-apper")
	private var rootCreated = false
	private var owned: [URL] = []

	func create() throws -> (id: UUID, url: URL) {
		let manager = FileManager.default
		if manager.fileExists(atPath: root.path) {
			let values = try root.resourceValues(forKeys: [.isDirectoryKey, .isSymbolicLinkKey])
			guard
				values.isDirectory == true,
				values.isSymbolicLink != true
			else { throw ScenarioFailure.message("unsafe DevTools projects root") }
		} else {
			try manager.createDirectory(at: root, withIntermediateDirectories: false)
			rootCreated = true
		}
		let id = UUID()
		let name = id.uuidString.lowercased()
		let url = root.appendingPathComponent(name)
		try manager.createDirectory(at: url, withIntermediateDirectories: false)
		owned.append(url)
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

	func remove() throws {
		let manager = FileManager.default
		for url in owned.reversed() {
			try manager.removeItem(at: url)
		}
		owned.removeAll()
		if rootCreated {
			let entries = try manager.contentsOfDirectory(atPath: root.path)
			if entries.isEmpty { try manager.removeItem(at: root) }
			rootCreated = false
		}
	}
}
