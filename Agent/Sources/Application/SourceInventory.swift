// @frontmatter:start
// Collects bounded generated-project source inventories while rejecting unsafe paths and file types.
// @frontmatter:end
import Foundation

#if canImport(Darwin)
	import Darwin
#else
	import Glibc
#endif

/// Supported source inputs, including trusted infrastructure, not build outputs.
public struct SourceInventory: Sendable {
	public static let maximumFiles = 1000
	public static let maximumEntries = 2000
	public static let maximumBytes = 8_388_608
	public static let maximumFileBytes = 65_536
	public static let maximumDepth = 16
	public static let maximumPathBytes = 1024
	public let files: [String: Data]
	public let entryCount: Int
	public let byteCount: Int

	public static func collect(_ root: URL) throws -> Self {
		let scope = try WorkspaceScope(root: root)
		var files: [String: Data] = [:]
		var entries = 0
		var bytes = 0
		func visit(_ relative: String) throws {
			try Task.checkCancellation()
			entries += 1
			guard
				entries <= maximumEntries,
				relative.split(separator: "/").count <= maximumDepth,
				relative.utf8.count <= maximumPathBytes
			else { throw SessionError.streamLimit }
			let url = try scope.resolve(relative)
			let attributes = try FileManager.default.attributesOfItem(atPath: url.path)
			if attributes[.type] as? FileAttributeType == .typeDirectory {
				try DirectoryEntries.forEach(url) { try visit(relative + "/" + $0) }
			} else {
				guard
					files.count < maximumFiles,
					attributes[.type] as? FileAttributeType == .typeRegular,
					let size = attributes[.size] as? Int,
					size >= 0,
					size <= maximumFileBytes,
					size <= maximumBytes - bytes
				else { throw SessionError.streamLimit }
				let data = try readFile(url, expectedSize: size)
				bytes += data.count
				files[relative] = data
			}
		}
		for relative in [
			"Sources", "Tests", "Package.swift", "Package.resolved", "Scaffold.version",
			"app-manifest.json", "Info.plist",
		] {
			try visit(relative)
		}
		return Self(files: files, entryCount: entries, byteCount: bytes)
	}

	/// Read no more than the observed size plus one; growth/replacement cannot cause an unbounded load.
	static func readFile(_ url: URL, expectedSize: Int) throws -> Data {
		let fd = open(url.path, O_RDONLY | O_NOFOLLOW | O_NONBLOCK)
		guard
			fd >= 0
		else { throw WorkspaceError.invalidPath }
		let handle = FileHandle(fileDescriptor: fd, closeOnDealloc: true)
		defer { try? handle.close() }
		var info = stat()
		guard
			fstat(fd, &info) == 0,
			info.st_mode & S_IFMT == S_IFREG,
			info.st_size == expectedSize
		else { throw WorkspaceError.invalidPath }
		var data = Data()
		while data.count <= expectedSize {
			try Task.checkCancellation()
			let chunk = try handle.read(upToCount: expectedSize + 1 - data.count) ?? Data()
			if chunk.isEmpty { break }
			data.append(chunk)
		}
		guard
			data.count == expectedSize,
			fstat(fd, &info) == 0,
			info.st_size == expectedSize
		else { throw SessionError.streamLimit }
		return data
	}
}

/// readdir streams even a single flooded directory; no subtree/per-directory arrays.
enum DirectoryEntries {
	static func forEach(_ url: URL, _ body: (String) throws -> Void) throws {
		guard
			let directory = opendir(url.path)
		else { throw WorkspaceError.invalidPath }
		defer { closedir(directory) }
		while true {
			try Task.checkCancellation()
			errno = 0
			guard
				let entry = readdir(directory)
			else {
				guard
					errno == 0
				else { throw WorkspaceError.invalidPath }
				return
			}
			let name = withUnsafePointer(to: &entry.pointee.d_name) {
				$0.withMemoryRebound(
					to: CChar.self, capacity: MemoryLayout.size(ofValue: entry.pointee.d_name)
				) { String(cString: $0) }
			}
			if name != "." && name != ".." { try body(name) }
		}
	}
}
