// @frontmatter:start
// Calls a packaged headless XPC client with bounded JSONL request and response validation.
// @frontmatter:end
import Foundation

/// Invokes a packaged headless XPC client, not a service executable from the source tree.
public struct XPCClientAdapter {
	public struct Reply {
		public let status: Int32
		public let data: Data
	}

	public init() {}

	public func call(
		_ executable: URL, request: Data, arguments: [String] = [],
		environment: [String: String] = [:], maxResponseBytes: Int = 65_536,
		timeoutSeconds: Int = 75
	) throws -> Reply {
		guard
			(1...131_072).contains(maxResponseBytes),
			(1...360).contains(timeoutSeconds),
			request.count <= 65_536,
			!request.contains(10),
			JSONSerialization.isValidJSONObject(try JSONSerialization.jsonObject(with: request)),
			let attributes = try? executable.resourceValues(forKeys: [
				.isRegularFileKey, .isSymbolicLinkKey,
			]),
			attributes.isRegularFile == true,
			attributes.isSymbolicLink != true,
			FileManager.default.isExecutableFile(atPath: executable.path)
		else { throw ScenarioFailure.message("invalid XPC client or request") }
		let directory = try ProjectTemporaryDirectory.root().appendingPathComponent(
			"scenario-xpc-\(UUID().uuidString)", isDirectory: true)
		try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: false)
		defer { try? FileManager.default.removeItem(at: directory) }
		let output = directory.appendingPathComponent("output")
		let errors = directory.appendingPathComponent("errors")
		FileManager.default.createFile(atPath: output.path, contents: nil)
		FileManager.default.createFile(atPath: errors.path, contents: nil)
		let outputHandle = try FileHandle(forWritingTo: output)
		let errorHandle = try FileHandle(forWritingTo: errors)
		defer { try? outputHandle.close(); try? errorHandle.close() }
		let input = Pipe()
		let process = Process()
		process.executableURL = executable
		process.arguments = arguments
		process.environment = try ProjectTemporaryDirectory.environment(
			ProcessInfo.processInfo.environment.merging(environment) { _, value in value })
		process.standardInput = input
		process.standardOutput = outputHandle
		process.standardError = errorHandle
		let finished = DispatchSemaphore(value: 0)
		process.terminationHandler = { _ in finished.signal() }
		try process.run()
		do {
			try input.fileHandleForWriting.write(contentsOf: request + Data([10]))
			try input.fileHandleForWriting.close()
		} catch {
			process.terminate()
			_ = finished.wait(timeout: .now() + 5)
			throw error
		}
		if finished.wait(timeout: .now() + .seconds(timeoutSeconds)) == .timedOut {
			process.terminate()
			_ = finished.wait(timeout: .now() + 5)
			throw ScenarioFailure.message("XPC terminal client timed out")
		}
		let reader = try FileHandle(forReadingFrom: output)
		defer { try? reader.close() }
		let data = try reader.read(upToCount: maxResponseBytes + 2) ?? Data()
		guard
			data.count <= maxResponseBytes + 1,
			let errorSize = try? FileManager.default.attributesOfItem(atPath: errors.path)[.size]
				as? NSNumber,
			errorSize.intValue == 0
		else { throw ScenarioFailure.message("invalid or oversized XPC client response") }
		guard
			data.last == 10,
			data.filter({ $0 == 10 }).count == 1
		else { throw ScenarioFailure.message("invalid XPC client response") }
		return Reply(status: process.terminationStatus, data: Data(data.dropLast()))
	}
}
