// @frontmatter:start
// Tests exact executable discovery, bounded inventory failures and capture races without signaling processes.
// @frontmatter:end
import Darwin
import Foundation
@testable import Scenario
import Testing

private func discoveryOperations(
	pids: [Int32] = [41, 42], truncated: Bool = false,
	path: @escaping (Int32) -> String? = { $0 == 41 ? "/bin/sleep" : "/other/sleep" },
	capture: @escaping (Int32) throws -> OwnedProcessIdentity = {
		OwnedProcessIdentity(pid: $0, start: 10, path: "/bin/sleep")
	}
) -> OwnedExecutableProcess.Operations {
	OwnedExecutableProcess.Operations(
		inventory: { .init(pids: pids, truncated: truncated) }, path: path, capture: capture,
		now: { 0 }, wait: { _ in })
}

@Test func executableDiscoveryMatchesExactPathNotName() throws {
	let result = try OwnedExecutableProcess.capture(
		executable: URL(fileURLWithPath: "/bin/sleep"), timeout: 0,
		using: discoveryOperations())
	#expect(result.pid == 41)
	#expect(result.path == "/bin/sleep")
}

@Test func executableDiscoveryFailsClosed() throws {
	let binary = URL(fileURLWithPath: "/bin/sleep")
	let failures: [OwnedExecutableProcess.Operations] = [
		discoveryOperations(pids: []),
		discoveryOperations(path: { _ in "/bin/sleep" }),
		discoveryOperations(truncated: true),
		discoveryOperations(pids: [41, 41]),
		discoveryOperations(pids: Array(repeating: 0, count: 65_536)),
		discoveryOperations(path: { _ in nil }),
		discoveryOperations(capture: { _ in throw ScenarioFailure.message("exited before capture") }),
		discoveryOperations(capture: { OwnedProcessIdentity(pid: $0, start: 10, path: "/other/sleep") }
		),
		discoveryOperations(capture: { _ in OwnedProcessIdentity(pid: 99, start: 10, path: "/bin/sleep")
		}),
		.init(
			inventory: { throw ScenarioFailure.message("inventory failed") }, path: { _ in nil },
			capture: { _ in throw ScenarioFailure.message("must not capture") }, now: { 0 },
			wait: { _ in }),
	]
	for operations in failures {
		#expect(throws: (any Error).self) {
			try OwnedExecutableProcess.capture(executable: binary, timeout: 0, using: operations)
		}
	}
	for timeout in [-1.0, .infinity, .nan, 61] {
		#expect(throws: (any Error).self) {
			try OwnedExecutableProcess.capture(
				executable: binary, timeout: timeout, using: discoveryOperations())
		}
	}
}

@Test func executableDiscoveryPollsOnlyUntilDeadline() throws {
	var clock = 0.0, inventories = 0
	let operations = OwnedExecutableProcess.Operations(
		inventory: {
			inventories += 1; return .init(pids: [], truncated: false)
		},
		path: { _ in nil }, capture: { _ in throw ScenarioFailure.message("must not capture") },
		now: { clock }, wait: { clock += $0 })
	#expect(throws: (any Error).self) {
		try OwnedExecutableProcess.capture(
			executable: URL(fileURLWithPath: "/bin/sleep"), timeout: 0.1, using: operations)
	}
	#expect(clock == 0.1)
	#expect(inventories == 3)
}

@Test func executableDiscoveryCanonicalizesOSAliasAndRejectsLinkedLeaf() throws {
	let manager = FileManager.default
	let directory = try ProjectTemporaryDirectory.root().appendingPathComponent(UUID().uuidString)
	try manager.createDirectory(at: directory, withIntermediateDirectories: false)
	defer { try? manager.removeItem(at: directory) }
	let binary = directory.appendingPathComponent("owned")
	try manager.copyItem(at: URL(fileURLWithPath: "/bin/sleep"), to: binary)
	let canonicalPointer = try #require(realpath(binary.path, nil))
	defer { free(canonicalPointer) }
	let canonical = String(cString: canonicalPointer)
	let operations = discoveryOperations(
		pids: [41], path: { _ in canonical },
		capture: {
			OwnedProcessIdentity(pid: $0, start: 10, path: canonical)
		})
	// /var is the installed system alias; use the same existing executable through it.
	let alias = URL(fileURLWithPath: "/var/../.." + canonical)
	#expect(
		try OwnedExecutableProcess.capture(executable: alias, timeout: 0, using: operations).path
			== canonical)
	let link = directory.appendingPathComponent("link")
	try manager.createSymbolicLink(at: link, withDestinationURL: binary)
	#expect(throws: (any Error).self) {
		try OwnedExecutableProcess.capture(executable: link, timeout: 0, using: operations)
	}
	#expect(throws: (any Error).self) {
		try OwnedExecutableProcess.capture(
			executable: directory.appendingPathComponent("missing"), timeout: 0, using: operations)
	}
	let directoryLink = directory.appendingPathComponent("directory-link")
	try manager.createSymbolicLink(at: directoryLink, withDestinationURL: directory)
	#expect(throws: (any Error).self) {
		try OwnedExecutableProcess.capture(
			executable: directoryLink.appendingPathComponent("owned"), timeout: 0, using: operations)
	}
	let disappearing = discoveryOperations(
		pids: [41], path: { _ in canonical },
		capture: {
			try manager.removeItem(at: binary)
			return OwnedProcessIdentity(pid: $0, start: 10, path: canonical)
		})
	#expect(throws: (any Error).self) {
		try OwnedExecutableProcess.capture(executable: binary, timeout: 0, using: disappearing)
	}
}

@Test func executableDiscoveryCapturesRealPrivateChildWithoutSignalingOtherProcesses() throws {
	let manager = FileManager.default
	let directory = try ProjectTemporaryDirectory.root().appendingPathComponent(UUID().uuidString)
	try manager.createDirectory(at: directory, withIntermediateDirectories: false)
	defer { try? manager.removeItem(at: directory) }
	let binary = directory.appendingPathComponent("owned-sleep")
	try manager.copyItem(at: URL(fileURLWithPath: "/bin/sleep"), to: binary)
	let child = Process()
	child.executableURL = binary
	child.arguments = ["60"]
	try child.run()
	defer {
		if child.isRunning { child.terminate() }
		child.waitUntilExit()
	}
	let identity = try OwnedExecutableProcess.capture(executable: binary)
	#expect(identity.pid == child.processIdentifier)
	try identity.reap()
	try identity.requireReaped()
	// Cached identity exit races remain the unchanged OwnedProcessIdentity responsibility.
	try identity.reap()
}
