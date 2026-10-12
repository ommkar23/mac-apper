import Foundation

/// Emits self-contained XPC service, client, and Pi terminal sources for OpenXPC contracts.
internal enum OpenXPCFunctionalGenerator {
	static func generate(
		_ spec: OpenXPCSpecification, target: String, mode: OpenXPCSpecification.Generation,
		operations: [String], serviceDispatch: OpenXPCSourceGenerator.ServiceDispatch
	) throws -> OpenXPCSourceGenerator.GeneratedFiles {
		let schema = spec.dataSchema
		let selectedSubscriptions = spec.subscriptions.filter { item in
			target == spec.service.target
				|| spec.clients.first(where: { $0.target == target })?.subscriptions.contains(item.name)
					== true
		}
		let types = OpenXPCTypedSwiftGenerator.render(
			schema, operations: operations,
			additionalTypes: selectedSubscriptions.flatMap { [$0.request, $0.response, $0.event] })
		let limit = spec.service.maxPayloadBytes > 32_768 ? 131_072 : 65_536
		let wire = wireSource(
			identifier: spec.service.identifier,
			limit: limit, payloadLimit: spec.service.maxPayloadBytes,
			includesSubscriptions: !spec.subscriptions.isEmpty)
		let implementation: String
		switch mode {
		case .service:
			implementation =
				!spec.subscriptions.isEmpty
				? OpenXPCSubscriptionGenerator.serviceSource(
					schema, operations: operations,
					subscriptions: selectedSubscriptions, dispatch: serviceDispatch)
				: serviceSource(schema, operations: operations, dispatch: serviceDispatch)
		case .client, .agentClient:
			let base = clientSource(
				schema, operations: operations,
				timeout: spec.service.timeoutSeconds)
			implementation =
				!spec.subscriptions.isEmpty
				? base + "\n\n"
					+ OpenXPCSubscriptionGenerator.clientSource(
						schema,
						subscriptions: selectedSubscriptions, timeout: spec.service.timeoutSeconds)
				: base
		}
		let terminal =
			mode == .agentClient
			? terminalSource(
				schema, operations: operations, limit: limit,
				serviceTarget: spec.service.target) : ""
		let extensionSource =
			mode == .agentClient
			? try piSource(spec, target: target, operations: operations, limit: limit) : nil
		return .init(
			swift: [types, wire, implementation, terminal].filter { !$0.isEmpty }
				.joined(separator: "\n\n"), piExtension: extensionSource)
	}

	private static func wireSource(
		identifier: String, limit: Int, payloadLimit: Int,
		includesSubscriptions: Bool
	) -> String {
		"""
		@objc protocol OpenXPCGeneratedProtocol: NSObjectProtocol {
			func execute(_ data: Data, reply: @escaping @Sendable (Data) -> Void)
		\(includesSubscriptions ? "\tfunc subscribe(_ data: Data, reply: @escaping @Sendable (Data) -> Void)" : "")
		}
		\(includesSubscriptions ? OpenXPCSubscriptionGenerator.wireSource() : "")

		private struct OpenXPCGeneratedRequest: Codable {
			let version: Int
			let requestID: UUID
			let projectID: UUID
			let sessionID: UUID
			let command: String
			let payload: Data
		}
		private struct OpenXPCGeneratedResponse: Codable {
			let version: Int
			let requestID: UUID
			let projectID: UUID
			let success: Bool
			let payload: Data?
			let error: String?
		}
		private enum OpenXPCGeneratedWire {
			static let identifier = \(String(reflecting: identifier))
			static let limit = \(limit)
			static let payloadLimit = \(payloadLimit)
			static func decode<T: Decodable>(_ data: Data, as type: T.Type, keys: Set<String>) throws -> T {
				guard data.count <= limit,
					let object = try JSONSerialization.jsonObject(with: data) as? [String: Any],
					Set(object.keys).isSubset(of: keys)
				else { throw OpenXPCGeneratedFailure.invalidResponse }
				return try JSONDecoder().decode(T.self, from: data)
			}
			static func encode<T: Encodable>(_ value: T) throws -> Data {
				let data = try JSONEncoder().encode(value)
				guard data.count <= limit else { throw OpenXPCGeneratedFailure.invalidResponse }
				return data
			}
		}
		public enum OpenXPCGeneratedFailure: Error {
			case invalidRequest, invalidResponse, unavailable, timedOut, remoteFailure
		}
		"""
	}

	private static func serviceSource(
		_ schema: OpenXPCDataSchema, operations: [String],
		dispatch: OpenXPCSourceGenerator.ServiceDispatch
	) -> String {
		let selected = schema.operations.filter { operations.contains($0.name) }
		let usesControllers = dispatch == .controllers
		func controllerName(_ name: String) -> String {
			"OpenXPC" + name.prefix(1).uppercased() + name.dropFirst() + "Controller"
		}
		let protocols =
			usesControllers
			? selected.map { operation in
				"""
				public protocol \(controllerName(operation.name)): Sendable {
					func handle(_ projectID: UUID, _ sessionID: UUID, _ request: \(operation.request)) async throws -> \(operation.response)
				}
				"""
			}.joined(separator: "\n") : ""
		let properties = selected.map { operation in
			usesControllers
				? "\t\tpublic let \(operation.name): any \(controllerName(operation.name))"
				: "\t\tpublic let \(operation.name): @Sendable (UUID, UUID, \(operation.request)) async throws -> \(operation.response)"
		}.joined(separator: "\n")
		let parameters = selected.map { operation in
			usesControllers
				? "\(operation.name): any \(controllerName(operation.name))"
				: "\(operation.name): @escaping @Sendable (UUID, UUID, \(operation.request)) async throws -> \(operation.response)"
		}.joined(separator: ", ")
		let assignments = selected.map { "\t\t\tself.\($0.name) = \($0.name)" }.joined(separator: "\n")
		let binding = usesControllers ? "Controllers" : "Handlers"
		let member = usesControllers ? "controllers" : "handlers"
		let cases = selected.map { operation in
			let call =
				usesControllers
				? "\(member).\(operation.name).handle(request.projectID, request.sessionID, value)"
				: "\(member).\(operation.name)(request.projectID, request.sessionID, value)"
			return """
				case \(String(reflecting: operation.name)):
					let value = try OpenXPCGeneratedWire.decode(request.payload, as: \(operation.request).self,
						keys: \(fieldSet(schema, type: operation.request)))
					let result = try await \(call)
					payload = try OpenXPCGeneratedWire.encode(result)
				"""
		}.joined(separator: "\n")
		return """
			\(protocols)
			public final class OpenXPCGeneratedService: NSObject, OpenXPCGeneratedProtocol, @unchecked Sendable {
				public struct \(binding): Sendable {
			\(properties)
					public init(\(parameters)) {
			\(assignments)
					}
				}
				private let \(member): \(binding)
				public init(\(member): \(binding)) { self.\(member) = \(member) }
				func execute(_ data: Data, reply: @escaping @Sendable (Data) -> Void) {
					Task { reply(await dispatch(data)) }
				}
				private func dispatch(_ data: Data) async -> Data {
					guard let request = try? OpenXPCGeneratedWire.decode(data,
						as: OpenXPCGeneratedRequest.self,
						keys: ["version", "requestID", "projectID", "sessionID", "command", "payload"]),
						request.version == 1, request.payload.count <= OpenXPCGeneratedWire.payloadLimit
					else { return Data() }
					let payload: Data?
					let failureCode: String?
					do {
						switch request.command {
			\(cases)
						default: throw OpenXPCGeneratedFailure.unavailable
						}
						failureCode = nil
					} catch {
						payload = nil
						failureCode = "operationFailed"
					}
					let response = OpenXPCGeneratedResponse(version: 1, requestID: request.requestID,
						projectID: request.projectID, success: failureCode == nil, payload: payload, error: failureCode)
					return (try? OpenXPCGeneratedWire.encode(response)) ?? Data()
				}
				public static func listen(\(member): \(binding)) -> Never {
					let delegate = OpenXPCGeneratedListener(service: .init(\(member): \(member)))
					let listener = NSXPCListener.service()
					listener.delegate = delegate
					listener.resume()
					withExtendedLifetime((listener, delegate)) { RunLoop.current.run() }
					fatalError("XPC listener stopped")
				}
			}
			private final class OpenXPCGeneratedListener: NSObject, NSXPCListenerDelegate {
				let service: OpenXPCGeneratedService
				init(service: OpenXPCGeneratedService) { self.service = service }
				func listener(_ listener: NSXPCListener, shouldAcceptNewConnection connection: NSXPCConnection) -> Bool {
					connection.exportedInterface = NSXPCInterface(with: OpenXPCGeneratedProtocol.self)
					connection.exportedObject = service
					connection.resume()
					return true
				}
			}
			"""
	}

	private static func clientSource(_ schema: OpenXPCDataSchema, operations: [String], timeout: Int)
		-> String
	{
		let methods = schema.operations.filter { operations.contains($0.name) }.map { operation in
			"""
			public func \(operation.name)(_ input: \(operation.request)) async throws -> \(operation.response) {
				let payload = try OpenXPCGeneratedWire.encode(input)
				let response = try await send(command: \(String(reflecting: operation.name)), payload: payload)
				return try OpenXPCGeneratedWire.decode(response, as: \(operation.response).self,
					keys: \(fieldSet(schema, type: operation.response)))
			}
			"""
		}.joined(separator: "\n")
		return """
			private final class OpenXPCPendingReply: @unchecked Sendable {
				private let lock = NSLock()
				private let connection: NSXPCConnection
				private let invalidateOnSuccess: Bool
				private var continuation: CheckedContinuation<Data, any Error>?
				private var result: Result<Data, any Error>?
				private var timeout: Task<Void, Never>?
				init(connection: NSXPCConnection, invalidateOnSuccess: Bool = true) {
					self.connection = connection
					self.invalidateOnSuccess = invalidateOnSuccess
				}
				func attach(_ value: CheckedContinuation<Data, any Error>) {
					let completed = lock.withLock { () -> Result<Data, any Error>? in
						if let result { return result }
						continuation = value
						return nil
					}
					if let completed { value.resume(with: completed) }
				}
				func scheduleTimeout(_ seconds: Int) {
					let task = Task { [self] in
						try? await Task.sleep(for: .seconds(seconds))
						if !Task.isCancelled { finish(.failure(OpenXPCGeneratedFailure.timedOut)) }
					}
					lock.withLock {
						if result == nil { timeout = task } else { task.cancel() }
					}
				}
				func finish(_ value: Result<Data, any Error>) {
					let pending = lock.withLock { () -> CheckedContinuation<Data, any Error>? in
						guard result == nil else { return nil }
						result = value
						timeout?.cancel()
						timeout = nil
						defer { continuation = nil }
						return continuation
					}
					if case .failure = value { connection.invalidate() }
					else if invalidateOnSuccess { connection.invalidate() }
					pending?.resume(with: value)
				}
			}
			public struct OpenXPCGeneratedClient: Sendable {
				public let projectID: UUID
				public let sessionID: UUID
				public let serviceName: String
				public init(projectID: UUID, sessionID: UUID, serviceName: String? = nil) {
					self.projectID = projectID
					self.sessionID = sessionID
					self.serviceName = serviceName ?? OpenXPCGeneratedWire.identifier
				}
			\(methods)
				func send(command: String, payload: Data, requestID: UUID = UUID()) async throws -> Data {
					let response = try await sendResponse(command: command, payload: payload, requestID: requestID)
					guard response.success, let body = response.payload
					else { throw OpenXPCGeneratedFailure.remoteFailure }
					return body
				}
				fileprivate func sendResponse(command: String, payload: Data, requestID: UUID) async throws
					-> OpenXPCGeneratedResponse {
					guard [\(operations.map { String(reflecting: $0) }.joined(separator: ", "))].contains(command),
						payload.count <= OpenXPCGeneratedWire.payloadLimit else {
						throw OpenXPCGeneratedFailure.invalidRequest
					}
					let request = OpenXPCGeneratedRequest(version: 1, requestID: requestID,
						projectID: projectID, sessionID: sessionID, command: command, payload: payload)
					let data = try OpenXPCGeneratedWire.encode(request)
					let connection = NSXPCConnection(serviceName: serviceName)
					connection.remoteObjectInterface = NSXPCInterface(with: OpenXPCGeneratedProtocol.self)
					let pending = OpenXPCPendingReply(connection: connection)
					let answer = try await withTaskCancellationHandler {
						try await withCheckedThrowingContinuation { continuation in
							pending.attach(continuation)
							guard !Task.isCancelled else {
								pending.finish(.failure(CancellationError()))
								return
							}
							connection.invalidationHandler = { [weak pending] in
								pending?.finish(.failure(OpenXPCGeneratedFailure.unavailable))
							}
							connection.interruptionHandler = { [weak pending] in
								pending?.finish(.failure(OpenXPCGeneratedFailure.unavailable))
							}
							connection.resume()
							pending.scheduleTimeout(\(timeout))
							guard let remote = connection.remoteObjectProxyWithErrorHandler({ _ in
								pending.finish(.failure(OpenXPCGeneratedFailure.unavailable))
							}) as? OpenXPCGeneratedProtocol else {
								pending.finish(.failure(OpenXPCGeneratedFailure.unavailable))
								return
							}
							remote.execute(data) { pending.finish(.success($0)) }
						}
					} onCancel: { pending.finish(.failure(CancellationError())) }
					let response = try OpenXPCGeneratedWire.decode(answer,
						as: OpenXPCGeneratedResponse.self,
						keys: ["version", "requestID", "projectID", "success", "payload", "error"])
					guard response.version == 1, response.requestID == requestID,
						response.projectID == projectID,
						response.success == (response.error == nil),
						response.success == (response.payload != nil)
					else { throw OpenXPCGeneratedFailure.invalidResponse }
					guard !response.success || (response.payload?.count ?? 0) <= OpenXPCGeneratedWire.payloadLimit,
						response.success || (response.error?.utf8.count ?? 0) <= 128
					else { throw OpenXPCGeneratedFailure.invalidResponse }
					return response
				}
			}
			"""
	}

	private static func terminalSource(
		_ schema: OpenXPCDataSchema, operations: [String],
		limit: Int, serviceTarget: String
	) -> String {
		let cases = schema.operations.filter { operations.contains($0.name) }.map { operation in
			"""
			case \(String(reflecting: operation.name)):
				let value = try OpenXPCGeneratedWire.decode(payload, as: \(operation.response).self,
					keys: \(fieldSet(schema, type: operation.response)))
				return try OpenXPCGeneratedWire.encode(value)
			"""
		}.joined(separator: "\n")
		return """
			@main enum OpenXPCGeneratedTerminalMain {
				static func main() async {
					let silentErrors: Bool
					switch Array(CommandLine.arguments.dropFirst()) {
					case []: silentErrors = false
					case ["--silent-errors"]: silentErrors = true
					default: invalidInput(false)
					}
					var line = Data()
					do {
						while let chunk = try FileHandle.standardInput.read(upToCount: 8_192), !chunk.isEmpty {
							line.append(chunk)
							guard line.count <= \(limit + 1) else { invalidInput(silentErrors) }
						}
					} catch { invalidInput(silentErrors) }
					guard line.count >= 2, line.last == 10, !line.dropLast().contains(10)
					else { invalidInput(silentErrors) }
					guard let project = ProcessInfo.processInfo.environment["OPENXPC_PROJECT_ID"].flatMap(UUID.init(uuidString:)),
						let session = ProcessInfo.processInfo.environment["OPENXPC_SESSION_ID"].flatMap(UUID.init(uuidString:)),
						let request = try? OpenXPCGeneratedWire.decode(Data(line.dropLast()),
							as: OpenXPCGeneratedRequest.self,
							keys: ["version", "requestID", "projectID", "sessionID", "command", "payload"]),
						request.version == 1, request.projectID == project, request.sessionID == session
					else { invalidInput(silentErrors) }
					let plist = Bundle.main.bundleURL.appendingPathComponent(
						"Contents/XPCServices/\(serviceTarget).xpc/Contents/Info.plist")
					var serviceName: String?
					if let data = try? Data(contentsOf: plist),
						let values = try? PropertyListSerialization.propertyList(
							from: data, format: nil) as? [String: Any] {
						serviceName = values["CFBundleIdentifier"] as? String
					}
					let client = OpenXPCGeneratedClient(projectID: project, sessionID: session,
						serviceName: serviceName)
					do {
						let response = try await client.sendResponse(command: request.command,
							payload: request.payload, requestID: request.requestID)
						if response.success, let payload = response.payload {
							let typed = try validate(command: request.command, payload: payload)
							emit(OpenXPCGeneratedResponse(
								version: 1, requestID: request.requestID, projectID: project,
								success: true, payload: typed, error: nil), silentErrors: silentErrors)
						} else {
							emit(response, silentErrors: silentErrors)
						}
					} catch {
						let failureCode: String
						switch error {
						case OpenXPCGeneratedFailure.invalidRequest: failureCode = "invalidRequest"
						case OpenXPCGeneratedFailure.unavailable: failureCode = "unavailable"
						case OpenXPCGeneratedFailure.timedOut: failureCode = "timedOut"
						default: failureCode = "invalidResponse"
						}
						emit(OpenXPCGeneratedResponse(
							version: 1, requestID: request.requestID, projectID: project,
							success: false, payload: nil, error: failureCode), silentErrors: silentErrors)
					}
				}
				private static func invalidInput(_ silentErrors: Bool) -> Never {
					if !silentErrors {
						FileHandle.standardError.write(Data("OpenXPC agent client: invalid request\\n".utf8))
					}
					exit(2)
				}
				private static func emit(_ response: OpenXPCGeneratedResponse, silentErrors: Bool) {
					if !response.success && silentErrors { exit(1) }
					guard let data = try? OpenXPCGeneratedWire.encode(response)
					else { invalidInput(silentErrors) }
					FileHandle.standardOutput.write(data + Data([10]))
					if !response.success { exit(1) }
				}
				private static func validate(command: String, payload: Data) throws -> Data {
					switch command {
				\(cases)
					default: throw OpenXPCGeneratedFailure.invalidResponse
					}
				}
			}
			"""
	}

	static func fieldSet(_ schema: OpenXPCDataSchema, type: String) -> String {
		let names = schema.types.first(where: { $0.name == type })?.fields.map(\.name) ?? []
		return "[" + names.map { String(reflecting: $0) }.joined(separator: ", ") + "]"
	}

	private static func piSource(
		_ spec: OpenXPCSpecification, target: String, operations allowed: [String], limit: Int
	) throws -> String {
		let schema = spec.dataSchema
		let lookup = Dictionary(uniqueKeysWithValues: schema.types.map { ($0.name, $0) })
		func jsonSchema(_ name: String) -> [String: Any] {
			let definition = lookup[name]!
			var properties: [String: Any] = [:]
			for field in definition.fields where field.injected == nil {
				var value: [String: Any]
				switch field.type {
				case "string": value = ["type": "string", "maxLength": field.maxLength!]
				case "data": value = ["type": "string", "maxLength": ((field.maxBytes! + 2) / 3) * 4]
				case "uuid": value = ["type": "string", "pattern": "^[0-9a-fA-F-]{36}$"]
				case "int": value = ["type": "integer"]
				case "double": value = ["type": "number"]
				case "bool": value = ["type": "boolean"]
				default: value = jsonSchema(field.type)
				}
				if field.array { value = ["type": "array", "items": value, "maxItems": field.maxItems!] }
				properties[field.name] = value
			}
			return [
				"type": "object", "properties": properties,
				"required": definition.fields.filter { !$0.optional && $0.injected == nil }.map(\.name),
				"additionalProperties": false,
			]
		}
		func literal(_ value: [String: Any]) throws -> String {
			let data = try JSONSerialization.data(withJSONObject: value, options: [.sortedKeys])
			return String(decoding: data, as: UTF8.self)
		}
		let selected = schema.operations.filter { allowed.contains($0.name) }
		let injectedCommands = selected.filter { operation in
			lookup[operation.request]?.fields.contains(where: { $0.injected == "projectRoot" }) == true
		}.map { String(reflecting: $0.name) }.joined(separator: ", ")
		let registrations = try selected.map { operation -> String in
			guard
				let tool = operation.tool
			else { throw SpecificationError.invalid("missing Pi tool") }
			return """
				pi.registerTool({
				  name: \(String(reflecting: operation.name)),
				  label: \(String(reflecting: tool.label)),
				  description: \(String(reflecting: tool.description)),
				  parameters: \(try tool.parametersJSON ?? literal(jsonSchema(operation.request))) as const,
				  async execute(_id, params, signal) {
				    try {
				      const result = await call(\(String(reflecting: operation.name)), params as Record<string, unknown>, signal);
				      const text = result && typeof result === "object" && "content" in result && typeof result.content === "string"
				        ? result.content : JSON.stringify(result);
				      \(tool.imageArtifact.map { "const image = await imageArtifact(result, " + String(reflecting: $0) + ");" } ?? "")
				      return { content: [{ type: "text" as const, text }\(tool.imageArtifact == nil ? "" : ", image")], details: { result } };
				    } catch (error) {
				      return { content: [{ type: "text" as const, text: String(error) }], details: {}, isError: true };
				    }
				  },
				});
				"""
		}.joined(separator: "\n")
		let key = "OPENXPC_" + target.uppercased() + "_CLIENT_PATH"
		return """
				// Generated by OpenXPCGenerator. Do not edit.
				import type { ExtensionAPI } from "@earendil-works/pi-coding-agent";
				import { spawn } from "node:child_process";
				import { randomUUID } from "node:crypto";
				\(selected.contains(where: { $0.tool?.imageArtifact != nil }) ? piImageArtifactSource : "")
				async function call(command: string, payload: Record<string, unknown>, signal?: AbortSignal): Promise<unknown> {
				  const executable = process.env[\(String(reflecting: key))];
				  const projectID = process.env.OPENXPC_PROJECT_ID;
				  const sessionID = process.env.OPENXPC_SESSION_ID;
				  if (!executable || !projectID || !sessionID) throw new Error("OpenXPC client is not bound.");
				  const requestID = randomUUID();
				  const injectProjectRoot = [\(injectedCommands)].includes(command);
				  const projectRoot = process.env.OPENXPC_PROJECT_ROOT;
				  if (injectProjectRoot && (!projectRoot || !projectRoot.startsWith("/") ||
				      Buffer.byteLength(projectRoot) > 4096 || Object.prototype.hasOwnProperty.call(payload, "projectRoot")))
				    throw new Error("OpenXPC project root is not bound.");
				  const body = JSON.stringify(injectProjectRoot ? { ...payload, projectRoot: projectRoot } : payload);
				  if (Buffer.byteLength(body) > \(spec.service.maxPayloadBytes)) throw new Error("Payload exceeds limit.");
				  const record = JSON.stringify({ version: 1, requestID, projectID, sessionID, command,
				    payload: Buffer.from(body).toString("base64") }) + "\\n";
				  if (Buffer.byteLength(record) > \(limit)) throw new Error("Request exceeds limit.");
				  return await new Promise((resolve, reject) => {
				    const child = spawn(executable, [], { shell: false, stdio: ["pipe", "pipe", "pipe"],
				      env: { OPENXPC_PROJECT_ID: projectID, OPENXPC_SESSION_ID: sessionID } });
				    let stdout = "", stderr = "", settled = false;
				    const finish = (error?: Error, value?: unknown) => {
				      if (settled) return;
				      settled = true;
				      clearTimeout(timer);
				      signal?.removeEventListener("abort", abort);
				      if (error) reject(error); else resolve(value);
				    };
				    const abort = () => { child.kill("SIGTERM"); finish(new Error("Request cancelled.")); };
				    const timer = setTimeout(() => { child.kill("SIGKILL"); finish(new Error("Request timed out.")); }, \((spec.service.timeoutSeconds + 5) * 1_000));
				    signal?.addEventListener("abort", abort, { once: true });
				    if (signal?.aborted) abort();
				    child.stdout.on("data", chunk => { stdout += chunk.toString();
				      if (Buffer.byteLength(stdout) > \(limit)) { child.kill("SIGKILL"); finish(new Error("Response exceeds limit.")); }
				    });
				    child.stderr.on("data", chunk => { stderr += chunk.toString();
				      if (Buffer.byteLength(stderr) > 8192) { child.kill("SIGKILL"); finish(new Error("Client stderr exceeds limit.")); }
				    });
				    child.stdin.on("error", error => finish(error));
				    child.on("error", error => finish(error));
				    child.on("exit", status => {
				      try {
				        const lines = stdout.split("\\n").filter(Boolean);
				        if (status !== 0 || stderr || lines.length !== 1) throw new Error("Client failed.");
				        const response = JSON.parse(lines[0]);
				        if (!response || typeof response !== "object" || Array.isArray(response) ||
				            Object.keys(response).some(key => !["version", "requestID", "projectID", "success", "payload", "error"].includes(key)))
				          throw new Error("Invalid response envelope.");
				        if (response.version !== 1 || response.requestID?.toLowerCase() !== requestID ||
				            response.projectID?.toLowerCase() !== projectID.toLowerCase() ||
				            response.success !== true || response.error != null || typeof response.payload !== "string")
				          throw new Error("Invalid response.");
				        const bytes = Buffer.from(response.payload, "base64");
				        if (bytes.toString("base64") !== response.payload) throw new Error("Invalid payload.");
				        const decoded = bytes.toString("utf8");
				        if (Buffer.byteLength(decoded) > \(spec.service.maxPayloadBytes)) throw new Error("Payload exceeds limit.");
				        finish(undefined, JSON.parse(decoded));
				      } catch (error) { finish(error instanceof Error ? error : new Error(String(error))); }
				    });
				    if (!settled) child.stdin.end(record);
				  });
				}
				export default function registerOpenXPCTools(pi: ExtensionAPI) {
			\(registrations)
			}
			""" + "\n"
	}
}
