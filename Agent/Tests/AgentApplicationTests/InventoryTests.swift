// @frontmatter:start
// Tests source inventory size, depth, entry, and file-read boundaries.
// @frontmatter:end
import Foundation
import Scenario
import Testing

@testable import AgentApplication

@Test func inventoryRejectsEmptyDirectoriesAndAggregateBytes() throws {
	let parent = try ProjectTemporaryDirectory.root().appendingPathComponent(UUID().uuidString)
	defer { try? FileManager.default.removeItem(at: parent) }
	let directories = try ProjectScaffold.create(under: parent)
	for index in 0..<2000 {
		try FileManager.default.createDirectory(
			at: directories.appendingPathComponent("Sources/AppModel/Empty\(index)"),
			withIntermediateDirectories: true)
	}
	#expect(throws: (any Error).self) { try ProjectScaffold.validate(directories) }
	let bytes = try ProjectScaffold.create(under: parent)
	for index in 0..<128 {
		try Data(repeating: 32, count: 65_536).write(
			to: bytes.appendingPathComponent("Sources/AppModel/Extra\(index).swift"))
	}
	#expect(throws: (any Error).self) { try ProjectScaffold.validate(bytes) }
}

@Test @MainActor func inventoryExactBoundariesCountTrustedTemplateAndExcludeOutputs() throws {
	let parent = try ProjectTemporaryDirectory.root().appendingPathComponent(UUID().uuidString)
	defer { try? FileManager.default.removeItem(at: parent) }
	let root = try ProjectScaffold.create(under: parent)
	let base = try ProjectScaffold.validate(root)
	#expect(base.files.count == 16)
	#expect(base.files["Sources/AppModel/Persistence.swift"] != nil)
	#expect(base.files["Sources/AppModel/ApplicationState.swift"] != nil)
	#expect(base.byteCount == base.files.values.reduce(0) { $0 + $1.count })
	print(
		"BASE_INVENTORY files=\(base.files.count) entries=\(base.entryCount) bytes=\(base.byteCount)")
	for index in 0..<(SourceInventory.maximumFiles - base.files.count) {
		try Data().write(to: root.appendingPathComponent("Sources/AppModel/F\(index).swift"))
	}
	#expect(try ProjectScaffold.validate(root).files.count == SourceInventory.maximumFiles)
	let fullFiles = try SourceInventory.collect(root)
	for index in 0..<(SourceInventory.maximumEntries - fullFiles.entryCount) {
		try FileManager.default.createDirectory(
			at: root.appendingPathComponent("Sources/AppModel/D\(index)"),
			withIntermediateDirectories: true)
	}
	#expect(try ProjectScaffold.validate(root).entryCount == SourceInventory.maximumEntries)
	try Data(repeating: 0, count: 65_537).write(to: root.appendingPathComponent("dist/ignored"))
	#expect(try ProjectScaffold.validate(root).byteCount == base.byteCount)
	try FileManager.default.createDirectory(
		at: root.appendingPathComponent("Sources/AppModel/TooMany"), withIntermediateDirectories: true)
	#expect(throws: (any Error).self) { try SourceInventory.collect(root) }

	let bytesRoot = try ProjectScaffold.create(under: parent)
	var remaining = SourceInventory.maximumBytes - base.byteCount
	var index = 0
	while remaining > 0 {
		let count = min(remaining, SourceInventory.maximumFileBytes)
		try Data(repeating: 32, count: count).write(
			to: bytesRoot.appendingPathComponent("Sources/AppModel/B\(index).swift"))
		remaining -= count
		index += 1
	}
	#expect(try ProjectScaffold.validate(bytesRoot).byteCount == SourceInventory.maximumBytes)
	try Data([0]).write(to: bytesRoot.appendingPathComponent("Sources/AppModel/Overflow.swift"))
	#expect(throws: (any Error).self) { try ProjectScaffold.validate(bytesRoot) }
}

@Test @MainActor func inventoryBoundedReadAndDepthRejectStaleSizes() throws {
	let parent = try ProjectTemporaryDirectory.root().appendingPathComponent(UUID().uuidString)
	defer { try? FileManager.default.removeItem(at: parent) }
	let root = try ProjectScaffold.create(under: parent)
	let file = root.appendingPathComponent("Sources/AppModel/Growth.swift")
	try Data(repeating: 0, count: 65_537).write(to: file)
	#expect(throws: (any Error).self) { try SourceInventory.readFile(file, expectedSize: 0) }
	#expect(throws: (any Error).self) { try SourceInventory.collect(root) }
	try FileManager.default.removeItem(at: file)
	let directory = root.appendingPathComponent(
		"Sources/AppModel/" + String(repeating: "D/", count: 13))
	try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
	try Data().write(to: directory.appendingPathComponent("At16.swift"))
	_ = try ProjectScaffold.validate(root)
	try FileManager.default.createDirectory(
		at: directory.appendingPathComponent("D"), withIntermediateDirectories: true)
	try Data().write(to: directory.appendingPathComponent("D/At17.swift"))
	#expect(throws: (any Error).self) { try SourceInventory.collect(root) }
}

@Test func inventoryCancellationBeforeTraversal() async throws {
	let task = Task {
		while !Task.isCancelled { await Task.yield() }
		return try SourceInventory.collect(try ProjectTemporaryDirectory.root())
	}
	task.cancel()
	await #expect(throws: CancellationError.self) { try await task.value }
}

@Test func inventoryRejectsEmptyFileFlood() throws {
	let parent = try ProjectTemporaryDirectory.root().appendingPathComponent(UUID().uuidString)
	defer { try? FileManager.default.removeItem(at: parent) }
	let root = try ProjectScaffold.create(under: parent)
	for index in 0..<1000 {
		try Data().write(to: root.appendingPathComponent("Sources/AppModel/Extra\(index).swift"))
	}
	#expect(throws: (any Error).self) { try ProjectScaffold.validate(root) }
}
