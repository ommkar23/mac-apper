import Foundation

/// Adds typed, per-connection XPC event subscriptions without owning domain replay or storage.
internal enum OpenXPCSubscriptionGenerator {
	static func wireSource() -> String {
		"""
		@objc protocol OpenXPCGeneratedEventSinkProtocol: NSObjectProtocol {
			func receive(_ event: Data)
			func finished(_ failure: String?)
		}
		private struct OpenXPCGeneratedEvent: Codable {
			let version: Int
			let subscriptionID: UUID
			let sequence: Int
			let projectID: UUID
			let sessionID: UUID
			let payload: Data
		}
		"""
	}

	static func serviceSource(
		_ schema: OpenXPCDataSchema, operations: [String],
		subscriptions: [OpenXPCSpecification.Subscription],
		dispatch: OpenXPCSourceGenerator.ServiceDispatch
	) -> String {
		let selected = schema.operations.filter { operations.contains($0.name) }
		let usesControllers = dispatch == .controllers
		func controllerName(_ name: String) -> String {
			"OpenXPC" + name.prefix(1).uppercased() + name.dropFirst() + "Controller"
		}
		let protocols =
			usesControllers
			? (selected.map { operation in
				"""
				public protocol \(controllerName(operation.name)): Sendable {
					func handle(_ projectID: UUID, _ sessionID: UUID, _ request: \(operation.request)) async throws -> \(operation.response)
				}
				"""
			}
				+ subscriptions.map { subscription in
					"""
					public protocol \(controllerName(subscription.name)): Sendable {
						func handle(_ projectID: UUID, _ sessionID: UUID, _ request: \(subscription.request), _ emitter: OpenXPCGeneratedEmitter<\(subscription.event)>) async throws -> \(subscription.response)
					}
					"""
				}).joined(separator: "\n") : ""
		let operationProperties = selected.map {
			usesControllers
				? "\t\tpublic let \($0.name): any \(controllerName($0.name))"
				: "\t\tpublic let \($0.name): @Sendable (UUID, UUID, \($0.request)) async throws -> \($0.response)"
		}.joined(separator: "\n")
		let subscriptionProperties = subscriptions.map {
			usesControllers
				? "\t\tpublic let \($0.name): any \(controllerName($0.name))"
				: "\t\tpublic let \($0.name): @Sendable (UUID, UUID, \($0.request), OpenXPCGeneratedEmitter<\($0.event)>) async throws -> \($0.response)"
		}.joined(separator: "\n")
		let parameters =
			selected.map {
				usesControllers
					? "\($0.name): any \(controllerName($0.name))"
					: "\($0.name): @escaping @Sendable (UUID, UUID, \($0.request)) async throws -> \($0.response)"
			}
			+ subscriptions.map {
				usesControllers
					? "\($0.name): any \(controllerName($0.name))"
					: "\($0.name): @escaping @Sendable (UUID, UUID, \($0.request), OpenXPCGeneratedEmitter<\($0.event)>) async throws -> \($0.response)"
			}
		let assignments = (selected.map(\.name) + subscriptions.map(\.name))
			.map { "\t\t\tself.\($0) = \($0)" }.joined(separator: "\n")
		let binding = usesControllers ? "Controllers" : "Handlers"
		let member = usesControllers ? "controllers" : "handlers"
		let cases = selected.map { operation in
			"""
			case \(String(reflecting: operation.name)):
				let value = try OpenXPCGeneratedWire.decode(request.payload, as: \(operation.request).self,
					keys: \(OpenXPCFunctionalGenerator.fieldSet(schema, type: operation.request)))
				let result = try await \(usesControllers ? "controllers.\(operation.name).handle" : "handlers.\(operation.name)")(request.projectID, request.sessionID, value)
				payload = try OpenXPCGeneratedWire.encode(result)
			"""
		}.joined(separator: "\n")
		let subscriptionCases = subscriptions.map { subscription in
			"""
			case \(String(reflecting: subscription.name)):
				let value = try OpenXPCGeneratedWire.decode(request.payload, as: \(subscription.request).self,
					keys: \(OpenXPCFunctionalGenerator.fieldSet(schema, type: subscription.request)))
				let emitter = OpenXPCGeneratedEmitter<\(subscription.event)>(
					remote: remote, requestID: request.requestID,
					projectID: request.projectID, sessionID: request.sessionID)
				guard claim({ emitter.disconnected() }) else { throw OpenXPCGeneratedFailure.unavailable }
				do {
					let result = try await \(usesControllers ? "controllers.\(subscription.name).handle" : "handlers.\(subscription.name)")(
						request.projectID, request.sessionID, value, emitter)
					payload = try OpenXPCGeneratedWire.encode(result)
				} catch {
					emitter.finish("operationFailed")
					throw error
				}
			"""
		}.joined(separator: "\n")
		return """
			\(usesControllers ? protocols + "\n" : "")public final class OpenXPCGeneratedEmitter<Event: Codable & Sendable>: @unchecked Sendable {
				private let lock = NSLock()
				private var remote: OpenXPCGeneratedEventSinkProtocol?
				private let requestID: UUID
				private let projectID: UUID
				private let sessionID: UUID
				private var nextSequence = 1
				private var closed = false
				private var closeHandler: (@Sendable () -> Void)?
				fileprivate init(remote: OpenXPCGeneratedEventSinkProtocol, requestID: UUID,
					projectID: UUID, sessionID: UUID) {
					self.remote = remote
					self.requestID = requestID
					self.projectID = projectID
					self.sessionID = sessionID
				}
				public func onClose(_ handler: @escaping @Sendable () -> Void) {
					let alreadyClosed = lock.withLock { () -> Bool in
						if closed { return true }
						closeHandler = handler
						return false
					}
					if alreadyClosed { handler() }
				}
				@discardableResult public func send(_ event: Event) -> Bool {
					guard let payload = try? OpenXPCGeneratedWire.encode(event),
						payload.count <= OpenXPCGeneratedWire.payloadLimit
					else { return false }
					return lock.withLock {
						guard !closed, nextSequence < Int.max, let remote else { return false }
						let envelope = OpenXPCGeneratedEvent(version: 1, subscriptionID: requestID,
							sequence: nextSequence, projectID: projectID, sessionID: sessionID, payload: payload)
						guard let data = try? OpenXPCGeneratedWire.encode(envelope) else { return false }
						remote.receive(data)
						nextSequence += 1
						return true
					}
				}
				public func finish(_ failure: String? = nil) {
					let bounded = failure.flatMap { $0.utf8.count <= 128 ? $0 : "operationFailed" }
					close(failure: bounded, notify: true)
				}
				fileprivate func disconnected() { close(failure: nil, notify: false) }
				private func close(failure: String?, notify: Bool) {
					let state = lock.withLock { () -> (OpenXPCGeneratedEventSinkProtocol?, (@Sendable () -> Void)?) in
						guard !closed else { return (nil, nil) }
						closed = true
						let previous = remote
						remote = nil
						let handler = closeHandler
						closeHandler = nil
						return (previous, handler)
					}
					if notify { state.0?.finished(failure) }
					state.1?()
				}
			}
			public final class OpenXPCGeneratedService: NSObject, OpenXPCGeneratedProtocol, @unchecked Sendable {
				public struct \(binding): Sendable {
			\(operationProperties)
			\(subscriptionProperties)
					public init(\(parameters.joined(separator: ", "))) {
			\(assignments)
					}
				}
				private let \(member): \(binding)
				private weak var connection: NSXPCConnection?
				private let lock = NSLock()
				private var closed = false
				private var closeSubscription: (@Sendable () -> Void)?
				public init(\(member): \(binding)) { self.\(member) = \(member) }
				fileprivate init(\(member): \(binding), connection: NSXPCConnection) {
					self.\(member) = \(member)
					self.connection = connection
				}
				private func claim(_ cleanup: @escaping @Sendable () -> Void) -> Bool {
					lock.withLock {
						guard !closed, closeSubscription == nil else { return false }
						closeSubscription = cleanup
						return true
					}
				}
				fileprivate func disconnected() {
					let cleanup = lock.withLock { () -> (@Sendable () -> Void)? in
						closed = true
						defer { closeSubscription = nil }
						return closeSubscription
					}
					cleanup?()
				}
				func execute(_ data: Data, reply: @escaping @Sendable (Data) -> Void) {
					Task { reply(await dispatch(data, isSubscription: false)) }
				}
				func subscribe(_ data: Data, reply: @escaping @Sendable (Data) -> Void) {
					Task { reply(await dispatch(data, isSubscription: true)) }
				}
				private func dispatch(_ data: Data, isSubscription: Bool) async -> Data {
					guard let request = try? OpenXPCGeneratedWire.decode(data,
						as: OpenXPCGeneratedRequest.self,
						keys: ["version", "requestID", "projectID", "sessionID", "command", "payload"]),
						request.version == 1, request.payload.count <= OpenXPCGeneratedWire.payloadLimit
					else { return Data() }
					let payload: Data?
					let failure: String?
					do {
						if isSubscription {
							guard let connection,
								let remote = connection.remoteObjectProxyWithErrorHandler({ [weak self] _ in
									self?.disconnected()
								}) as? OpenXPCGeneratedEventSinkProtocol
							else { throw OpenXPCGeneratedFailure.unavailable }
							switch request.command {
			\(subscriptionCases)
							default: throw OpenXPCGeneratedFailure.unavailable
							}
						} else {
							switch request.command {
			\(cases)
							default: throw OpenXPCGeneratedFailure.unavailable
							}
						}
						failure = nil
					} catch {
						payload = nil
						failure = "operationFailed"
					}
					return (try? OpenXPCGeneratedWire.encode(OpenXPCGeneratedResponse(
						version: 1, requestID: request.requestID, projectID: request.projectID,
						success: failure == nil, payload: payload, error: failure))) ?? Data()
				}
				public static func listen(\(member): \(binding)) -> Never {
					let delegate = OpenXPCGeneratedListener(\(member): \(member))
					let listener = NSXPCListener.service()
					listener.delegate = delegate
					listener.resume()
					withExtendedLifetime((listener, delegate)) { RunLoop.current.run() }
					fatalError("XPC listener stopped")
				}
			}
			private final class OpenXPCGeneratedListener: NSObject, NSXPCListenerDelegate {
				let \(member): OpenXPCGeneratedService.\(binding)
				init(\(member): OpenXPCGeneratedService.\(binding)) { self.\(member) = \(member) }
				func listener(_ listener: NSXPCListener, shouldAcceptNewConnection connection: NSXPCConnection) -> Bool {
					let endpoint = OpenXPCGeneratedService(\(member): \(member), connection: connection)
					connection.exportedInterface = NSXPCInterface(with: OpenXPCGeneratedProtocol.self)
					connection.remoteObjectInterface = NSXPCInterface(with: OpenXPCGeneratedEventSinkProtocol.self)
					connection.exportedObject = endpoint
					connection.invalidationHandler = { [weak endpoint] in endpoint?.disconnected() }
					connection.interruptionHandler = { [weak endpoint] in endpoint?.disconnected() }
					connection.resume()
					return true
				}
			}
			"""
	}

	static func clientSource(
		_ schema: OpenXPCDataSchema,
		subscriptions: [OpenXPCSpecification.Subscription], timeout: Int
	) -> String {
		let methods = subscriptions.map { subscription in
			"""
			public func subscribe\(subscription.name.prefix(1).uppercased() + subscription.name.dropFirst())(
				_ input: \(subscription.request)
			) async throws -> (\(subscription.response), AsyncThrowingStream<\(subscription.event), any Error>) {
				let payload = try OpenXPCGeneratedWire.encode(input)
				guard payload.count <= OpenXPCGeneratedWire.payloadLimit else {
					throw OpenXPCGeneratedFailure.invalidRequest
				}
				let id = UUID()
				let request = OpenXPCGeneratedRequest(version: 1, requestID: id,
					projectID: projectID, sessionID: sessionID,
					command: \(String(reflecting: subscription.name)), payload: payload)
				let data = try OpenXPCGeneratedWire.encode(request)
				let connection = NSXPCConnection(serviceName: serviceName)
				connection.remoteObjectInterface = NSXPCInterface(with: OpenXPCGeneratedProtocol.self)
				connection.exportedInterface = NSXPCInterface(with: OpenXPCGeneratedEventSinkProtocol.self)
				let events = AsyncThrowingStream<\(subscription.event), any Error>.makeStream(
					bufferingPolicy: .bufferingNewest(2_048))
				let stream = OpenXPCGeneratedSubscription<\(subscription.event)>(
					id: id, projectID: projectID, sessionID: sessionID,
					onEvent: { value in
						if case .dropped = events.continuation.yield(value) {
							events.continuation.finish(throwing: OpenXPCGeneratedFailure.invalidResponse)
						}
					},
					onFinish: { reason in
						if let reason, reason != "cancelled" {
							events.continuation.finish(throwing: OpenXPCGeneratedFailure.unavailable)
						} else { events.continuation.finish() }
					})
				connection.exportedObject = stream
				stream.attach(connection)
				let pending = OpenXPCPendingReply(connection: connection, invalidateOnSuccess: false)
				connection.invalidationHandler = { [weak stream, weak pending] in
					pending?.finish(.failure(OpenXPCGeneratedFailure.unavailable))
					stream?.finished("disconnected")
				}
				connection.interruptionHandler = { [weak stream, weak pending] in
					pending?.finish(.failure(OpenXPCGeneratedFailure.unavailable))
					stream?.finished("disconnected")
				}
				let answer: Data
				do {
					answer = try await withTaskCancellationHandler {
						try await withCheckedThrowingContinuation { continuation in
							pending.attach(continuation)
							guard !Task.isCancelled else {
								pending.finish(.failure(CancellationError()))
								return
							}
							connection.resume()
							pending.scheduleTimeout(\(timeout))
							guard let remote = connection.remoteObjectProxyWithErrorHandler({ _ in
								pending.finish(.failure(OpenXPCGeneratedFailure.unavailable))
							}) as? OpenXPCGeneratedProtocol else {
								pending.finish(.failure(OpenXPCGeneratedFailure.unavailable))
								return
							}
							remote.subscribe(data) { pending.finish(.success($0)) }
						}
					} onCancel: { pending.finish(.failure(CancellationError())) }
				} catch {
					stream.cancel()
					throw error
				}
				guard let response = try? OpenXPCGeneratedWire.decode(answer,
						as: OpenXPCGeneratedResponse.self,
						keys: ["version", "requestID", "projectID", "success", "payload", "error"]),
					response.version == 1, response.requestID == id, response.projectID == projectID,
					response.success, response.error == nil,
					let body = response.payload, body.count <= OpenXPCGeneratedWire.payloadLimit,
					let ack = try? OpenXPCGeneratedWire.decode(body, as: \(subscription.response).self,
						keys: \(OpenXPCFunctionalGenerator.fieldSet(schema, type: subscription.response)))
				else {
					stream.cancel()
					throw OpenXPCGeneratedFailure.invalidResponse
				}
				events.continuation.onTermination = { @Sendable _ in stream.cancel() }
				guard !Task.isCancelled else {
					stream.cancel()
					throw CancellationError()
				}
				stream.activate()
				return (ack, events.stream)
			}
			"""
		}.joined(separator: "\n")
		return """
			public final class OpenXPCGeneratedSubscription<Event: Codable & Sendable>:
				NSObject, OpenXPCGeneratedEventSinkProtocol, @unchecked Sendable {
				private let lock = NSLock()
				private let delivery = DispatchQueue(label: "OpenXPC.subscription.delivery")
				private let id: UUID
				private let projectID: UUID
				private let sessionID: UUID
				private let onEvent: @Sendable (Event) -> Void
				private let onFinish: @Sendable (String?) -> Void
				private var connection: NSXPCConnection?
				private var nextSequence = 1
				private var active = false
				private var closed = false
				private var buffered: [Event] = []
				private var bufferedBytes = 0
				private var pendingFinish = false
				private var pendingFailure: String?
				fileprivate init(id: UUID, projectID: UUID, sessionID: UUID,
					onEvent: @escaping @Sendable (Event) -> Void,
					onFinish: @escaping @Sendable (String?) -> Void) {
					self.id = id
					self.projectID = projectID
					self.sessionID = sessionID
					self.onEvent = onEvent
					self.onFinish = onFinish
				}
				fileprivate func attach(_ value: NSXPCConnection) {
					lock.withLock { connection = value }
				}
				fileprivate func activate() {
					let finish = lock.withLock { () -> (Bool, String?) in
						guard !closed else { return (false, nil) }
						active = true
						for event in buffered { delivery.async { [onEvent] in onEvent(event) } }
						buffered.removeAll()
						bufferedBytes = 0
						return (pendingFinish, pendingFailure)
					}
					if finish.0 { terminate(finish.1) }
				}
				func receive(_ data: Data) {
					guard let record = try? OpenXPCGeneratedWire.decode(data, as: OpenXPCGeneratedEvent.self,
						keys: ["version", "subscriptionID", "sequence", "projectID", "sessionID", "payload"]),
						record.version == 1, record.subscriptionID == id,
						record.projectID == projectID, record.sessionID == sessionID,
						record.payload.count <= OpenXPCGeneratedWire.payloadLimit,
						let value = try? OpenXPCGeneratedWire.decode(record.payload, as: Event.self,
							keys: \(subscriptionFieldSet(schema, subscriptions: subscriptions)))
					else { terminate("invalidEvent"); return }
					let accepted = lock.withLock { () -> Bool in
						guard !closed else { return true }
						guard record.sequence == nextSequence, nextSequence < Int.max else { return false }
						nextSequence += 1
						if active {
							delivery.async { [onEvent] in onEvent(value) }
							return true
						}
						guard buffered.count < 256,
							bufferedBytes + data.count <= OpenXPCGeneratedWire.limit
						else { return false }
						buffered.append(value)
						bufferedBytes += data.count
						return true
					}
					if !accepted { terminate("invalidEvent") }
				}
				func finished(_ failure: String?) {
					guard failure == nil || failure!.utf8.count <= 128 else {
						terminate("invalidEvent")
						return
					}
					let deferred = lock.withLock { () -> Bool in
						guard !active, !closed else { return false }
						pendingFinish = true
						pendingFailure = failure
						return true
					}
					if !deferred { terminate(failure) }
				}
				public func cancel() { terminate("cancelled") }
				private func terminate(_ failure: String?) {
					let previous = lock.withLock { () -> NSXPCConnection? in
						guard !closed else { return nil }
						closed = true
						buffered.removeAll()
						bufferedBytes = 0
						defer { connection = nil }
						return connection
					}
					if let previous {
						previous.invalidate()
						delivery.async { [onFinish] in onFinish(failure) }
					}
				}
			}
			extension OpenXPCGeneratedClient {
			\(methods)
			}
			"""
	}

	private static func subscriptionFieldSet(
		_ schema: OpenXPCDataSchema,
		subscriptions: [OpenXPCSpecification.Subscription]
	) -> String {
		// A subscription's event type is fixed by its exported sink instance.
		let names = subscriptions.flatMap { item in
			schema.types.first(where: { $0.name == item.event })?.fields.map(\.name) ?? []
		}
		return "[" + Set(names).sorted().map { String(reflecting: $0) }.joined(separator: ", ") + "]"
	}
}
