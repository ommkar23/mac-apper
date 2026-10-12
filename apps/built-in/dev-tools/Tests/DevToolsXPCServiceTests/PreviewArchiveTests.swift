// @frontmatter:start
// Tests persistent session-scoped preview storage, retention, collision handling, and rejection of linked archive paths.
// @frontmatter:end
import Darwin
import Foundation
import ImageIO
import Testing
@testable import DevToolsApplication

// Equivalent to VisionCore.LocalFile's absolute, descriptor-relative no-follow read.
func readArchiveWithoutFollowingLinks(_ path: String) throws -> Data {
	let components = path.split(separator: "/", omittingEmptySubsequences: false).dropFirst()
	guard
		path.hasPrefix("/"),
		path.utf8.count <= 4096,
		!components.isEmpty,
		components.allSatisfy({ !$0.isEmpty && $0 != "." && $0 != ".." })
	else { throw POSIXError(.EINVAL) }
	var directory = open("/", O_RDONLY | O_DIRECTORY | O_CLOEXEC)
	guard
		directory >= 0
	else { throw POSIXError(.EIO) }
	defer { close(directory) }
	for component in components.dropLast() {
		let child = openat(
			directory, String(component), O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC)
		guard
			child >= 0
		else { throw POSIXError(.ENOTDIR) }
		close(directory); directory = child
	}
	let file = openat(
		directory, String(try #require(components.last)), O_RDONLY | O_NONBLOCK | O_NOFOLLOW | O_CLOEXEC
	)
	guard
		file >= 0
	else { throw POSIXError(.EIO) }
	defer { close(file) }
	var info = stat()
	guard
		fstat(file, &info) == 0,
		info.st_mode & S_IFMT == S_IFREG,
		info.st_size > 0,
		info.st_size <= 2_097_152
	else { throw POSIXError(.EINVAL) }
	let bytes =
		try FileHandle(fileDescriptor: file, closeOnDealloc: false).read(upToCount: 2_097_153) ?? Data()
	#expect(bytes.count == info.st_size)
	return bytes
}

@Test func previewArchiveReturnsCanonicalNoFollowReviewPath() throws {
	let homeName = "scenario-home-\(UUID().uuidString)"
	let home = URL(fileURLWithPath: "/private/tmp/\(homeName)")
	let root = home.appendingPathComponent(".mac-apper")
	try FileManager.default.createDirectory(
		at: root, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
	defer { try? FileManager.default.removeItem(at: home) }
	let png = try #require(
		Data(
			base64Encoded:
				"iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mNk+A8AAQUBAScY42YAAAAASUVORK5CYII="
		))
	let projectID = UUID(), sessionID = UUID()
	for prefix in ["/tmp", "/private/tmp"] {
		let input = URL(fileURLWithPath: "\(prefix)/\(homeName)/.mac-apper")
		let review = try PreviewArchive.save(
			png, projectsRoot: input, projectID: projectID, sessionID: sessionID)
		// Production PreviewRendering uses review.path unchanged in the typed artifact.
		let artifact = try PreviewArtifact(
			relativePath: ".mac-apper/Artifacts/render.png", reviewPath: review.path, kind: "png")
		let decoded = try JSONDecoder().decode(
			PreviewArtifact.self, from: JSONEncoder().encode(artifact))
		#expect(decoded.reviewPath.hasPrefix("/private/tmp/\(homeName)/.mac-apper/previews/"))
		let bytes = try readArchiveWithoutFollowingLinks(decoded.reviewPath)
		#expect(bytes == png)
		let source = try #require(CGImageSourceCreateWithData(bytes as CFData, nil))
		#expect(CGImageSourceCreateImageAtIndex(source, 0, nil) != nil)
		#expect(throws: (any Error).self) {
			try readArchiveWithoutFollowingLinks(
				"/tmp/\(homeName)/.mac-apper/previews/\(projectID.uuidString.lowercased())/\(sessionID.uuidString.lowercased())/\(review.lastPathComponent)"
			)
		}
	}
}

@Test func previewArchiveRetainsImagesAfterProjectRemovalWithoutOverwriting() throws {
	let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
	try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
	defer { try? FileManager.default.removeItem(at: root) }
	let projectID = UUID(), sessionID = UUID()
	let project = root.appendingPathComponent(projectID.uuidString.lowercased())
	try FileManager.default.createDirectory(at: project, withIntermediateDirectories: true)
	let date = Date(timeIntervalSince1970: 1_700_000_000)
	let bytes = Data("validated PNG fixture".utf8)
	let first = try PreviewArchive.save(
		bytes, projectsRoot: root, projectID: projectID, sessionID: sessionID, timestamp: date)
	let second = try PreviewArchive.save(
		Data("second PNG".utf8), projectsRoot: root, projectID: projectID, sessionID: sessionID,
		timestamp: date)
	let other = try PreviewArchive.save(
		bytes, projectsRoot: root, projectID: projectID, sessionID: UUID(), timestamp: date)
	#expect(first != second && first.deletingLastPathComponent() != other.deletingLastPathComponent())
	#expect(
		first.path.hasSuffix(
			"/previews/\(projectID.uuidString.lowercased())/\(sessionID.uuidString.lowercased())/preview-1700000000000000.png"
		))
	try FileManager.default.removeItem(at: project)
	#expect(try readArchiveWithoutFollowingLinks(first.path) == bytes)
	#expect(try readArchiveWithoutFollowingLinks(second.path) == Data("second PNG".utf8))
	let attributes = try FileManager.default.attributesOfItem(atPath: first.path)
	#expect((attributes[.posixPermissions] as? NSNumber)?.intValue == 0o600)
}

@Test func previewArchiveRejectsRootLinksBoundsAndPreservesLeafCollisions() throws {
	let root = URL(fileURLWithPath: "/private/tmp/archive-safety-\(UUID().uuidString)")
	try FileManager.default.createDirectory(at: root, withIntermediateDirectories: false)
	defer { try? FileManager.default.removeItem(at: root) }
	let projectID = UUID(), sessionID = UUID(), date = Date(timeIntervalSince1970: 1_700_000_000)
	let external = root.appendingPathComponent("external.png")
	try Data([7]).write(to: external)
	let first = try PreviewArchive.save(
		Data([1]), projectsRoot: root, projectID: projectID, sessionID: sessionID, timestamp: date)
	try FileManager.default.removeItem(at: first)
	try FileManager.default.createSymbolicLink(at: first, withDestinationURL: external)
	let next = try PreviewArchive.save(
		Data([2]), projectsRoot: root, projectID: projectID, sessionID: sessionID, timestamp: date)
	#expect(next.lastPathComponent == "preview-1700000000000001.png")
	#expect(try readArchiveWithoutFollowingLinks(next.path) == Data([2]))
	#expect(try Data(contentsOf: external) == Data([7]))
	let link = root.appendingPathComponent("linked-root")
	try FileManager.default.createSymbolicLink(at: link, withDestinationURL: root)
	#expect(throws: (any Error).self) {
		try PreviewArchive.save(
			Data([1]), projectsRoot: link, projectID: projectID, sessionID: sessionID)
	}
	for data in [Data(), Data(repeating: 1, count: 2_097_153)] {
		#expect(throws: (any Error).self) {
			try PreviewArchive.save(data, projectsRoot: root, projectID: projectID, sessionID: sessionID)
		}
	}
	#expect(throws: (any Error).self) {
		try PreviewArchive.save(
			Data([1]), projectsRoot: root, projectID: projectID, sessionID: sessionID,
			timestamp: Date(timeIntervalSince1970: -1))
	}
	let attributes = try FileManager.default.attributesOfItem(
		atPath: next.deletingLastPathComponent().path)
	#expect((attributes[.posixPermissions] as? NSNumber)?.intValue == 0o700)
}

@Test func previewArchiveRejectsLinksAtEveryDirectoryLevel() throws {
	for level in 0...2 {
		let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
		try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
		defer { try? FileManager.default.removeItem(at: root) }
		let projectID = UUID(), sessionID = UUID()
		let components = [
			"previews", projectID.uuidString.lowercased(), sessionID.uuidString.lowercased(),
		]
		var parent = root
		for component in components.prefix(level) {
			parent.appendPathComponent(component)
			try FileManager.default.createDirectory(at: parent, withIntermediateDirectories: false)
		}
		let external = root.appendingPathComponent("external")
		try FileManager.default.createDirectory(at: external, withIntermediateDirectories: false)
		try FileManager.default.createSymbolicLink(
			at: parent.appendingPathComponent(components[level]), withDestinationURL: external)
		#expect(throws: (any Error).self) {
			try PreviewArchive.save(
				Data([1]), projectsRoot: root, projectID: projectID, sessionID: sessionID)
		}
		#expect(try FileManager.default.contentsOfDirectory(atPath: external.path).isEmpty)
	}
}
