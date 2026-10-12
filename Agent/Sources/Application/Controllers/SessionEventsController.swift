// @frontmatter:start
// Subscribes to a scoped session and detaches its observer when the XPC emitter closes.
// @frontmatter:end
import Foundation

struct SessionEventsController: OpenXPCSessionEventsController {
	let sessions: any AgentSessionManaging

	func handle(
		_ projectID: UUID, _ sessionID: UUID, _ request: SessionSubscriptionRequest,
		_ emitter: OpenXPCGeneratedEmitter<SessionEvent>
	) async throws -> SessionAttachment {
		try await AgentOpenXPCService.checkSession(
			projectID, sessionID, request.sessionID, sessions: sessions)
		let (id, cursor) = try await sessions.subscribe(
			sessionID: request.sessionID,
			observer: { item in
				do { _ = emitter.send(try AgentOpenXPCService.event(item)) } catch {
					emitter.finish("invalidEvent")
				}
			},
			onFinished: { emitter.finish($0) })
		emitter.onClose {
			Task { @MainActor in sessions.unsubscribe(sessionID: request.sessionID, id: id) }
		}
		return try SessionAttachment(cursor: cursor)
	}
}
