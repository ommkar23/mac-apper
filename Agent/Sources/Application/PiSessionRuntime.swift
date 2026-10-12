// @frontmatter:start
// Defines the service-owned Pi session runtime interface.
// @frontmatter:end
import Foundation

@MainActor public protocol PiSessionRuntime: AnyObject {
	func sessionDirectory(in project: URL) -> URL
	func start(in project: URL) async throws -> AsyncThrowingStream<PiRPCEvent, any Error>
	func start(in project: URL, sessionFile: URL, title: String?) async throws -> AsyncThrowingStream<
		PiRPCEvent, any Error
	>
	func start(in project: URL, sessionFile: URL, title: String?, createApp: Bool) async throws
		-> AsyncThrowingStream<PiRPCEvent, any Error>
	func start(agentID: String, in project: URL, sessionFile: URL, title: String?, firstRequest: Bool)
		async throws -> AsyncThrowingStream<PiRPCEvent, any Error>
	func start(
		agentID: String, in project: URL, sessionFile: URL, title: String?, firstRequest: Bool,
		replayHistory: Bool
	) async throws -> AsyncThrowingStream<PiRPCEvent, any Error>
	func prompt(_ message: String) async throws
	func abort() async throws
	func startChat(in project: URL, sessionFile: URL, title: String?) async throws
		-> AsyncThrowingStream<PiRPCEvent, any Error>
	@discardableResult func stop() async -> Bool
	@discardableResult func detach() async -> Bool
	func attach(sessionFile: URL) async throws -> AsyncThrowingStream<PiRPCEvent, any Error>?
}

extension PiSessionRuntime {
	@discardableResult public func detach() async -> Bool { await stop() }
	public func attach(sessionFile: URL) async throws
		-> AsyncThrowingStream<PiRPCEvent, any Error>?
	{ nil }

	public func start(
		agentID: String, in project: URL, sessionFile: URL, title: String?,
		firstRequest: Bool, replayHistory: Bool
	) async throws
		-> AsyncThrowingStream<PiRPCEvent, any Error>
	{
		try await start(
			agentID: agentID, in: project, sessionFile: sessionFile,
			title: title, firstRequest: firstRequest)
	}

	public func sessionDirectory(in project: URL) -> URL {
		project.appendingPathComponent(".pi/sessions", isDirectory: true)
	}

	public func start(
		agentID: String, in project: URL, sessionFile: URL, title: String?, firstRequest: Bool
	) async throws -> AsyncThrowingStream<PiRPCEvent, any Error> {
		if agentID == "chat" {
			return try await startChat(in: project, sessionFile: sessionFile, title: title)
		}
		return try await start(
			in: project, sessionFile: sessionFile, title: title, createApp: firstRequest)
	}

	public func start(in project: URL, sessionFile: URL, title: String?, createApp: Bool) async throws
		-> AsyncThrowingStream<PiRPCEvent, any Error>
	{
		try await start(in: project, sessionFile: sessionFile, title: title)
	}

	public func startChat(in project: URL, sessionFile: URL, title: String?) async throws
		-> AsyncThrowingStream<PiRPCEvent, any Error>
	{
		throw PiRPCError.unavailable
	}
}
