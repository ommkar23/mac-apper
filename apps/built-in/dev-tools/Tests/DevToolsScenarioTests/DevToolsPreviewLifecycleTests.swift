// @frontmatter:start
// Audits private Preview files by no-follow descriptors and tests archive identity and request retention offline.
// @frontmatter:end
import Darwin
import Foundation
import Scenario
import Testing

// Strict consumer paths never resolve links or reconstruct the returned archive pathname.
enum PreviewFixtureAudit {
	static func descriptor(_ path: String, directory: Bool) throws -> Int32 {
		let parts = path.dropFirst().split(separator: "/", omittingEmptySubsequences: false)
		guard
			path.hasPrefix("/"),
			path.utf8.count <= 4096,
			!path.contains("\0"),
			!path.contains("\\"),
			!parts.isEmpty,
			parts.allSatisfy({ !$0.isEmpty && $0 != "." && $0 != ".." })
		else { throw ScenarioFailure.message("unsafe Preview path") }
		var fd = open("/", O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC)
		guard
			fd >= 0
		else { throw ScenarioFailure.message("Preview root unavailable") }
		do {
			for (index, part) in parts.enumerated() {
				let flags = O_RDONLY | O_NOFOLLOW | O_CLOEXEC | O_NONBLOCK
				let next = openat(
					fd, String(part), flags | (directory || index < parts.count - 1 ? O_DIRECTORY : 0))
				guard
					next >= 0
				else { throw ScenarioFailure.message("linked or missing Preview path") }
				Darwin.close(fd); fd = next
			}
			return fd
		} catch { Darwin.close(fd); throw error }
	}
	static func sameDirectory(_ actual: URL, _ expected: URL) throws {
		let a = try descriptor(actual.path, directory: true)
		defer { Darwin.close(a) }
		let b = try descriptor(expected.path, directory: true)
		defer { Darwin.close(b) }
		var left = stat(), right = stat()
		guard
			fstat(a, &left) == 0,
			fstat(b, &right) == 0,
			left.st_dev == right.st_dev,
			left.st_ino == right.st_ino
		else { throw ScenarioFailure.message("foreign Preview archive directory") }
	}
	static func read(_ url: URL) throws -> Data {
		let fd = try descriptor(url.path, directory: false)
		defer { Darwin.close(fd) }
		var before = stat()
		guard
			fstat(fd, &before) == 0,
			before.st_mode & S_IFMT == S_IFREG,
			before.st_size > 0,
			before.st_size <= 2_097_152
		else { throw ScenarioFailure.message("invalid Preview file") }
		var data = Data(), buffer = [UInt8](repeating: 0, count: 8192)
		while true {
			let count = buffer.withUnsafeMutableBytes { Darwin.read(fd, $0.baseAddress, $0.count) }
			guard
				count >= 0
			else { throw ScenarioFailure.message("Preview read failed") }
			if count == 0 { break }
			data.append(contentsOf: buffer.prefix(count))
			guard
				data.count <= 2_097_152
			else { throw ScenarioFailure.message("Preview grew beyond bound") }
		}
		var after = stat()
		guard
			fstat(fd, &after) == 0,
			after.st_size == before.st_size,
			data.count == before.st_size,
			after.st_mtimespec.tv_sec == before.st_mtimespec.tv_sec,
			after.st_mtimespec.tv_nsec == before.st_mtimespec.tv_nsec
		else { throw ScenarioFailure.message("Preview changed during read") }
		return data
	}
	static func completed(_ result: [String: Any]) throws {
		guard
			let status = result["status"] as? String,
			["rendered", "error"].contains(status),
			!(result["summary"] as? String ?? "").contains("cleanupFailed"),
			!(result["summary"] as? String ?? "").contains("reapFailed")
		else { throw ScenarioFailure.message("Preview completion uncertain") }
	}
}

@Suite @MainActor struct DevToolsPreviewLifecycleTests {
	@Test func strictArchiveIdentityAndDeletedProjectReads() throws {
		let home = try IsolatedScenarioHome()
		var passed = false
		defer {
			if !passed { print("OFFLINE_PREVIEW_FIXTURE_RETAINED \(home.directory.path)") }
		}
		let archive = try home.privateDirectory(".mac-apper/previews/project/session")
		let project = try home.privateDirectory(".mac-apper/project")
		let file = archive.appendingPathComponent("preview-1.png")
		let bytes = Data([1, 2, 3]); try bytes.write(to: file)
		try PreviewFixtureAudit.sameDirectory(file.deletingLastPathComponent(), archive)
		try #require(PreviewFixtureAudit.read(file) == bytes)
		try FileManager.default.removeItem(at: project)
		try #require(PreviewFixtureAudit.read(file) == bytes)
		try #require(throws: (any Error).self) {
			try PreviewFixtureAudit.sameDirectory(archive, home.directory)
		}
		let linked = home.directory.appendingPathComponent("linked")
		try FileManager.default.createSymbolicLink(at: linked, withDestinationURL: archive)
		try #require(throws: (any Error).self) {
			try PreviewFixtureAudit.read(linked.appendingPathComponent(file.lastPathComponent))
		}
		try #require(throws: (any Error).self) {
			try PreviewFixtureAudit.sameDirectory(linked, archive)
		}
		let leaf = archive.appendingPathComponent("linked.png")
		try FileManager.default.createSymbolicLink(at: leaf, withDestinationURL: file)
		try #require(throws: (any Error).self) { try PreviewFixtureAudit.read(leaf) }
		try #require(throws: (any Error).self) {
			try PreviewFixtureAudit.read(archive.appendingPathComponent("../session/preview-1.png"))
		}
		try home.remove(cleanupConfirmed: true)
		passed = true
	}
	@Test func privatePreviewProjectsNeverBorrowDefaultHome() throws {
		let first = try IsolatedScenarioHome(), second = try IsolatedScenarioHome()
		var passed = false
		defer {
			if !passed {
				print("OFFLINE_PREVIEW_FIXTURES_RETAINED \(first.directory.path) \(second.directory.path)")
			}
		}
		let left = DevToolsScenarioProjects(root: try first.privateDirectory(".mac-apper"))
		let right = DevToolsScenarioProjects(root: try second.privateDirectory(".mac-apper"))
		let a = try left.create(), b = try right.create()
		let temporaryRoot = try ProjectTemporaryDirectory.root().path + "/"
		try #require(a.id != b.id && first.directory != second.directory)
		for (home, project) in [(first, a), (second, b)] {
			try PreviewFixtureAudit.sameDirectory(
				project.url.deletingLastPathComponent().deletingLastPathComponent(), home.directory)
			try #require(home.environment["HOME"] == home.directory.path)
			try #require(home.environment["CFFIXED_USER_HOME"] == home.directory.path)
			try #require(home.environment["TMPDIR"] == temporaryRoot)
			let descriptor = try PreviewFixtureAudit.descriptor(home.directory.path, directory: true)
			defer { Darwin.close(descriptor) }
			var info = stat()
			try #require(
				fstat(descriptor, &info) == 0 && info.st_uid == geteuid() && info.st_mode & 0o077 == 0)
			_ = try PreviewFixtureAudit.read(project.url.appendingPathComponent("app-manifest.json"))
		}
		try left.remove(); try right.remove()
		try first.remove(cleanupConfirmed: true); try second.remove(cleanupConfirmed: true)
		passed = true
	}
	@Test func uncertainRenderingCannotResetRequestCompletion() throws {
		for summary in ["cleanupFailed", "reapFailed"] {
			let state = DevToolsScenarioLifecycle.RequestState()
			#expect(throws: (any Error).self) {
				try state.perform(classifyCompletion: PreviewFixtureAudit.completed, capture: {}) {
					["status": "error", "summary": summary] as [String: Any]
				}
			}
			#expect(throws: (any Error).self) { try state.requireRequestAllowed() }
			#expect(throws: (any Error).self) { try state.stop {} }
		}
		let state = DevToolsScenarioLifecycle.RequestState()
		for status in ["error", "rendered"] {
			_ = try state.perform(classifyCompletion: PreviewFixtureAudit.completed, capture: {}) {
				["status": status, "summary": "processFailed"] as [String: Any]
			}
		}
		try state.stop {}
		try #require(state.serviceStopped)
	}
}
