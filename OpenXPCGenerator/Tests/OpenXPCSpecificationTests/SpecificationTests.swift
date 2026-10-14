import Foundation
import Scenario
import OpenXPCSpecification
import Testing

private func standaloneCompiler(_ arguments: [String]) throws -> Process {
	let sdk = Process(), output = Pipe()
	sdk.executableURL = URL(fileURLWithPath: "/usr/bin/xcrun")
	sdk.arguments = ["--show-sdk-path"]
	sdk.standardOutput = output
	try sdk.run()
	let data = output.fileHandleForReading.readDataToEndOfFile()
	sdk.waitUntilExit()
	let path = String(decoding: data, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
	guard
		sdk.terminationStatus == 0,
		path.hasPrefix("/"),
		data.count < 4096
	else { throw CocoaError(.fileReadNoSuchFile) }
	let process = Process()
	process.executableURL = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(
		"Library/Developer/Toolchains/swift-6.4.0-RELEASE.xctoolchain/usr/bin/swiftc")
	process.arguments = ["-sdk", path] + arguments
	return process
}

private let typedContract = """
	service:
	  identifier: com.example.openxpc
	  target: WebApplication
	  generate: service
	types:
	  - name: SearchRequest
	    fields:
	      - name: query
	        type: string
	        maxLength: 2048
	      - name: limit
	        type: int
	        optional: true
	  - name: SearchResponse
	    fields:
	      - name: results
	        type: string
	        array: true
	        maxItems: 10
	        maxLength: 4096
	      - name: metadata
	        type: SearchMetadata
	        optional: true
	  - name: SearchMetadata
	    fields:
	      - name: requestID
	        type: uuid
	      - name: raw
	        type: data
	        maxBytes: 4096
	  - name: ExtractRequest
	    fields:
	      - name: url
	        type: string
	        maxLength: 4096
	  - name: ExtractResponse
	    fields:
	      - name: content
	        type: string
	        maxLength: 65536
	operations:
	  - name: search
	    request: SearchRequest
	    response: SearchResponse
	  - name: extract
	    request: ExtractRequest
	    response: ExtractResponse
	clients:
	  - target: WebTerminalClient
	    generate: client
	    operations: [search, extract]
	  - target: WebAutomationClient
	    generate: client
	    operations: [search]
	"""

private let functionalContract = """
	service:
	  identifier: com.example.openxpc
	  target: ProbeService
	  generate: service
	types:
	  - name: PingRequest
	    fields:
	      - name: value
	        type: string
	        maxLength: 128
	  - name: PingResponse
	    fields:
	      - name: value
	        type: string
	        maxLength: 128
	operations:
	  - name: ping
	    request: PingRequest
	    response: PingResponse
	    tool:
	      label: Ping
	      description: Send a ping.
	clients:
	  - target: ProbeClient
	    generate: client
	    operations: [ping]
	  - target: ProbeAgentClient
	    generate: agentClient
	    operations: [ping]
	"""

@Test func toolDescriptionsSupportBoundedMultilineExamplesButRejectOtherControls() throws {
	func specification(_ description: String) throws -> OpenXPCSpecification {
		let quoted = String(
			decoding: try JSONSerialization.data(withJSONObject: description, options: .fragmentsAllowed),
			as: UTF8.self)
		return try OpenXPCSpecification(
			yaml: functionalContract.replacingOccurrences(
				of: "description: Send a ping.", with: "description: \(quoted)"))
	}
	let description =
		String(repeating: "Usage guidance. ", count: 100) + "\n```swift\npublic func example() {}\n```"
	let spec = try specification(description)
	#expect(spec.dataSchema.operations.first?.tool?.description == description)
	let generated = try OpenXPCSourceGenerator.generate(spec: spec, target: "ProbeAgentClient")
	#expect(generated.piExtension?.contains("public func example() {}") == true)
	#expect(generated.piExtension?.contains("\\n```swift\\n") == true)
	for invalid in [
		"", "bad\ttext", "bad\rtext", "bad\u{7}text", String(repeating: "x", count: 4097),
	] {
		#expect(throws: (any Error).self) { try specification(invalid) }
	}
}

@Test func imageArtifactToolsGenerateBoundedScopedPNGContent() throws {
	let contract =
		functionalContract
		.replacingOccurrences(
			of: "description: Send a ping.", with: "description: Send a ping.\n      imageArtifact: value"
		)
	let spec = try OpenXPCSpecification(yaml: contract)
	let files = try OpenXPCSourceGenerator.generate(spec: spec, target: "ProbeAgentClient")
	let source = try #require(files.piExtension)
	#expect(source.contains("await imageArtifact(result, \"value\")"))
	#expect(source.contains("type: \"image\" as const"))
	#expect(source.contains("O_NOFOLLOW"))
	#expect(source.contains("2097152"))
	#expect(source.contains("realpath"))
	#expect(source.contains(#"\.mac-apper\/Artifacts\/"#))
	#expect(throws: (any Error).self) {
		_ = try OpenXPCSpecification(
			yaml: contract.replacingOccurrences(
				of: "imageArtifact: value", with: "imageArtifact: missing.path"))
	}
}

private let subscriptionContract = """
	service:
	  identifier: com.example.events.xpc
	  target: EventService
	  generate: service
	types:
	  - name: SubscribeRequest
	    fields:
	      - { name: sessionID, type: uuid }
	  - name: SubscribeAck
	    fields:
	      - { name: cursor, type: int }
	  - name: SessionEvent
	    fields:
	      - { name: text, type: string, maxLength: 128 }
	  - name: PingRequest
	    fields:
	      - { name: text, type: string, maxLength: 128 }
	  - name: PingResponse
	    fields:
	      - { name: text, type: string, maxLength: 128 }
	operations:
	  - { name: ping, request: PingRequest, response: PingResponse }
	subscriptions:
	  - { name: events, request: SubscribeRequest, response: SubscribeAck, event: SessionEvent }
	clients:
	  - target: EventClient
	    generate: client
	    operations: [ping]
	    subscriptions: [events]
	"""

@Test func contractAndGenerationConfigHaveDistinctStrictFields() throws {
	let contract =
		functionalContract
		.replacingOccurrences(of: "  target: ProbeService\n  generate: service\n", with: "")
		.replacingOccurrences(
			of:
				"clients:\n  - target: ProbeClient\n    generate: client\n    operations: [ping]\n  - target: ProbeAgentClient\n    generate: agentClient\n    operations: [ping]",
			with: "")
	let generation = """
		service:
		  target: ProbeService
		  generate: service
		clients:
		  - target: ProbeAgentClient
		    generate: agentClient
		    operations: [ping]
		  - target: ProbeClient
		    generate: client
		    operations: [ping]
		"""
	let spec = try OpenXPCSpecification(contractYAML: contract, generationYAML: generation)
	#expect(spec.service.target == "ProbeService")
	#expect(spec.clients.count == 2)
	#expect(OpenXPCSpecification.generationSchema != nil)
	#expect(throws: (any Error).self) {
		try OpenXPCSpecification(contractYAML: contract + "\nclients: []\n", generationYAML: generation)
	}
	#expect(throws: (any Error).self) {
		try OpenXPCSpecification(
			contractYAML: contract,
			generationYAML: generation + "\ntypes: []\n")
	}
}

@Test func singleSchemaAcceptsOperationsWithOptionalSubscriptions() throws {
	let operationsOnly = functionalContract
	let service = try OpenXPCSpecification(yaml: operationsOnly)
	#expect(service.subscriptions.isEmpty)
	let withSubscriptions = subscriptionContract
	let events = try OpenXPCSpecification(yaml: withSubscriptions)
	#expect(events.subscriptions.map(\.name) == ["events"])
	#expect(try !#require(OpenXPCSpecification.schema).isEmpty)
	#expect(throws: (any Error).self) {
		try OpenXPCSpecification(yaml: "schemaVersion: 5\n" + withSubscriptions)
	}
}

@Test func generatesTypedBidirectionalSubscription() throws {
	let spec = try OpenXPCSpecification(yaml: subscriptionContract)
	let service = try OpenXPCSourceGenerator.generate(spec: spec, target: "EventService")
	let client = try OpenXPCSourceGenerator.generate(spec: spec, target: "EventClient")
	#expect(service.swift.contains("OpenXPCGeneratedEventSinkProtocol"))
	#expect(service.swift.contains("func subscribe(_ data: Data"))
	#expect(service.swift.contains("connection.invalidationHandler"))
	#expect(service.swift.contains("SessionEvent"))
	#expect(client.swift.contains("func subscribeEvents("))
	#expect(
		client.swift.contains(
			"async throws -> (SubscribeAck, AsyncThrowingStream<SessionEvent, any Error>)"))
	#expect(client.swift.contains("func ping(_ input: PingRequest) async throws"))
	#expect(!client.swift.contains("DispatchSemaphore"))
	#expect(client.swift.contains("events.continuation.onTermination"))
	#expect(client.swift.contains("SubscribeAck"))
	#expect(OpenXPCSpecification.schema != nil)
}

@Test func generatedSubscriptionTargetsTypecheck() throws {
	let spec = try OpenXPCSpecification(yaml: subscriptionContract)
	let root = try ProjectTemporaryDirectory.root().appendingPathComponent(UUID().uuidString)
	try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
	defer { try? FileManager.default.removeItem(at: root) }
	for target in ["EventService", "EventClient"] {
		let source = try OpenXPCSourceGenerator.generate(spec: spec, target: target)
		let file = root.appendingPathComponent("\(target).swift")
		try source.swift.write(to: file, atomically: true, encoding: .utf8)
		let process = try standaloneCompiler(["-parse-as-library", "-typecheck", file.path])
		let errors = Pipe()
		process.standardError = errors
		try process.run()
		process.waitUntilExit()
		let diagnostic = String(
			decoding: errors.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
		#expect(process.terminationStatus == 0, "\(target): \(diagnostic)")
	}
}

@Test func rejectsUnsafeSubscriptionReferences() {
	#expect(throws: (any Error).self) {
		try OpenXPCSpecification(
			yaml: subscriptionContract.replacingOccurrences(
				of: "event: SessionEvent", with: "event: UnknownEvent"))
	}
	#expect(throws: (any Error).self) {
		try OpenXPCSpecification(
			yaml: subscriptionContract.replacingOccurrences(
				of: "subscriptions: [events]", with: "subscriptions: [missing]"))
	}
	#expect(throws: (any Error).self) {
		try OpenXPCSpecification(
			yaml: subscriptionContract.replacingOccurrences(
				of: "subscriptions: [events]", with: "subscriptions: [events, events]"))
	}
	#expect(throws: (any Error).self) {
		try OpenXPCSpecification(
			yaml: subscriptionContract.replacingOccurrences(
				of: "generate: client", with: "generate: agentClient"))
	}
	#expect(throws: (any Error).self) {
		try OpenXPCSpecification(
			yaml: subscriptionContract.replacingOccurrences(
				of: "name: events, request:", with: "name: ping, request:"))
	}
	#expect(throws: (any Error).self) {
		try OpenXPCSpecification(
			yaml: subscriptionContract.replacingOccurrences(
				of: "name: SessionEvent", with: "name: OpenXPCGeneratedEmitter"
			)
			.replacingOccurrences(of: "event: SessionEvent", with: "event: OpenXPCGeneratedEmitter"))
	}
}

@Test func projectRootIsInjectedIntoAgentRequestsWithoutBecomingAToolParameter() throws {
	let yaml = functionalContract.replacingOccurrences(
		of: "        maxLength: 128\n  - name: PingResponse",
		with:
			"        maxLength: 128\n      - { name: projectRoot, type: string, maxLength: 4096, injected: projectRoot }\n  - name: PingResponse"
	).replacingOccurrences(
		of: "      description: Send a ping.",
		with:
			"      description: Send a ping.\n      parameters:\n        type: object\n        additionalProperties: false\n        required: [value]\n        properties:\n          value: { type: string, maxLength: 128 }"
	)
	let spec = try OpenXPCSpecification(yaml: yaml)
	let agent = try OpenXPCSourceGenerator.generate(spec: spec, target: "ProbeAgentClient")
	#expect(agent.piExtension?.contains("OPENXPC_PROJECT_ROOT") == true)
	#expect(agent.piExtension?.contains("projectRoot: projectRoot") == true)
	#expect(agent.piExtension?.contains("\"required\":[\"value\"]") == true)
	#expect(throws: (any Error).self) {
		try OpenXPCSpecification(
			yaml: yaml.replacingOccurrences(
				of: "injected: projectRoot", with: "injected: untrusted"))
	}
	#expect(throws: (any Error).self) {
		try OpenXPCSpecification(
			yaml: yaml.replacingOccurrences(
				of: "injected: projectRoot", with: "optional: true, injected: projectRoot"))
	}
}

@Test func explicitPiSchemaPreservesProviderConstraints() throws {
	let yaml = functionalContract.replacingOccurrences(
		of: "      description: Send a ping.",
		with:
			"      description: Send a ping.\n      parameters:\n        type: object\n        additionalProperties: false\n        required: [value]\n        properties:\n          value: { type: string, minLength: 1, maxLength: 128 }"
	)
	let spec = try OpenXPCSpecification(yaml: yaml)
	let agent = try OpenXPCSourceGenerator.generate(spec: spec, target: "ProbeAgentClient")
	#expect(agent.piExtension?.contains("\"minLength\":1") == true)
}

@Test func rejectsMalformedServiceLimitsInsteadOfUsingDefaults() {
	for invalid in [
		functionalContract.replacingOccurrences(
			of: "  generate: service", with: "  generate: service\n  maxPayloadBytes: unbounded"),
		functionalContract.replacingOccurrences(
			of: "  generate: service", with: "  generate: service\n  timeoutSeconds: never"),
	] {
		#expect(throws: (any Error).self) { try OpenXPCSpecification(yaml: invalid) }
	}
}

@Test func serviceLimitsPropagateToAllGeneratedTransports() throws {
	let yaml = functionalContract.replacingOccurrences(
		of: "  generate: service",
		with:
			"  generate: service\n  maxPayloadBytes: 65536\n  timeoutSeconds: 330")
	let spec = try OpenXPCSpecification(yaml: yaml)
	let service = try OpenXPCSourceGenerator.generate(spec: spec, target: "ProbeService")
	let agent = try OpenXPCSourceGenerator.generate(spec: spec, target: "ProbeAgentClient")
	#expect(service.swift.contains("payloadLimit = 65536"))
	#expect(agent.swift.contains("limit = 131072"))
	#expect(agent.swift.contains("pending.scheduleTimeout(330)"))
	#expect(!agent.swift.contains("DispatchSemaphore"))
	#expect(agent.piExtension?.contains("setTimeout") == true)
	#expect(agent.piExtension?.contains("335000") == true)
}

@Test func generatesFunctionalServiceClientAndAgentClient() throws {
	let spec = try OpenXPCSpecification(yaml: functionalContract)
	let service = try OpenXPCSourceGenerator.generate(spec: spec, target: "ProbeService")
	#expect(service.swift.contains("NSXPCListener.service()"))
	#expect(service.swift.contains("PingRequest"))
	#expect(service.piExtension == nil)
	let client = try OpenXPCSourceGenerator.generate(spec: spec, target: "ProbeClient")
	#expect(client.swift.contains("NSXPCConnection(serviceName:"))
	#expect(client.swift.contains("serviceName: String? = nil"))
	#expect(client.swift.contains("func ping(_ input: PingRequest) async throws"))
	#expect(client.swift.contains("withCheckedThrowingContinuation"))
	#expect(client.swift.contains("withTaskCancellationHandler"))
	#expect(!client.swift.contains("DispatchSemaphore"))
	#expect(!client.swift.contains("@main"))
	#expect(client.piExtension == nil)
	let agent = try OpenXPCSourceGenerator.generate(spec: spec, target: "ProbeAgentClient")
	#expect(agent.swift.contains("@main"))
	#expect(agent.swift.contains("static func main() async"))
	#expect(agent.swift.contains("try await client.sendResponse("))
	#expect(agent.swift.contains("ProbeService.xpc/Contents/Info.plist"))
	#expect(agent.piExtension?.contains("pi.registerTool") == true)
	#expect(agent.piExtension?.contains("name: \"ping\"") == true)
	#expect(agent.piExtension?.contains("spawn(") == true)
}

@Test func functionalOutputsTypecheckAsStandaloneTargets() throws {
	let spec = try OpenXPCSpecification(yaml: functionalContract)
	let root = try ProjectTemporaryDirectory.root().appendingPathComponent(UUID().uuidString)
	try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
	defer { try? FileManager.default.removeItem(at: root) }
	for target in ["ProbeService", "ProbeClient", "ProbeAgentClient"] {
		let source = try OpenXPCSourceGenerator.generate(spec: spec, target: target)
		let file = root.appendingPathComponent("\(target).swift")
		try source.swift.write(to: file, atomically: true, encoding: .utf8)
		let process = try standaloneCompiler(["-parse-as-library", "-typecheck", file.path])
		let errors = Pipe()
		process.standardError = errors
		try process.run()
		process.waitUntilExit()
		let diagnostic = String(
			decoding: errors.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
		#expect(process.terminationStatus == 0, "\(target): \(diagnostic)")
	}
}

@Test func generatedServiceDispatchesTypedPayloads() throws {
	let spec = try OpenXPCSpecification(yaml: functionalContract)
	let source = try OpenXPCSourceGenerator.generate(spec: spec, target: "ProbeService")
	let root = try ProjectTemporaryDirectory.root().appendingPathComponent(UUID().uuidString)
	try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
	defer { try? FileManager.default.removeItem(at: root) }
	let generated = root.appendingPathComponent("OpenXPCGenerated.swift")
	try source.swift.write(to: generated, atomically: true, encoding: .utf8)
	let harness = root.appendingPathComponent("Harness.swift")
	try """
	import Foundation
	struct PingController: OpenXPCPingController {
		func handle(_ projectID: UUID, _ sessionID: UUID, _ value: PingRequest) async throws -> PingResponse {
			try PingResponse(value: value.value)
		}
	}
	@main struct Harness {
		static func main() throws {
			let service = OpenXPCGeneratedService(controllers: .init(ping: PingController()))
			let id = UUID()
			let project = UUID()
			let payload = Data(#"{"value":"ok"}"#.utf8).base64EncodedString()
			let record: [String: Any] = ["version": 1, "requestID": id.uuidString,
				"projectID": project.uuidString, "sessionID": UUID().uuidString,
				"command": "ping", "payload": payload]
			let done = DispatchSemaphore(value: 0)
			service.execute(try JSONSerialization.data(withJSONObject: record)) { response in
				defer { done.signal() }
				guard let result = try? JSONSerialization.jsonObject(with: response) as? [String: Any],
					result["success"] as? Bool == true,
					result["requestID"] as? String == id.uuidString,
					let encoded = result["payload"] as? String,
					let body = Data(base64Encoded: encoded),
					String(decoding: body, as: UTF8.self) == #"{"value":"ok"}"#
				else { exit(1) }
			}
			guard done.wait(timeout: .now() + 2) == .success else { exit(2) }
		}
	}
	""".write(to: harness, atomically: true, encoding: .utf8)
	let binary = root.appendingPathComponent("service-test")
	let compiler = try standaloneCompiler([
		"-parse-as-library", generated.path, harness.path, "-o", binary.path,
	])
	let diagnostics = Pipe()
	compiler.standardError = diagnostics
	try compiler.run()
	compiler.waitUntilExit()
	let errors = String(
		decoding: diagnostics.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
	#expect(compiler.terminationStatus == 0, "\(errors)")
	guard
		compiler.terminationStatus == 0
	else { return }
	let runner = Process()
	runner.executableURL = binary
	try runner.run()
	runner.waitUntilExit()
	#expect(runner.terminationStatus == 0)
}

@Test func generatedAgentClientReportsFailureByDefaultAndSilencesOnlyWithFlag() throws {
	let spec = try OpenXPCSpecification(yaml: functionalContract)
	let source = try OpenXPCSourceGenerator.generate(spec: spec, target: "ProbeAgentClient")
	let root = try ProjectTemporaryDirectory.root().appendingPathComponent(UUID().uuidString)
	try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
	defer { try? FileManager.default.removeItem(at: root) }
	let generated = root.appendingPathComponent("Generated.swift")
	try source.swift.write(to: generated, atomically: true, encoding: .utf8)
	let executable = root.appendingPathComponent("ProbeAgentClient")
	let compiler = try standaloneCompiler([
		"-parse-as-library", generated.path, "-o", executable.path,
	])
	compiler.standardError = FileHandle.nullDevice
	try compiler.run()
	compiler.waitUntilExit()
	let status = compiler.terminationStatus
	#expect(status == 0)
	guard
		status == 0
	else { return }
	let project = UUID().uuidString
	let session = UUID().uuidString
	let requestID = UUID().uuidString
	let envelope =
		try JSONSerialization.data(withJSONObject: [
			"version": 1, "projectID": project, "sessionID": session, "requestID": requestID,
			"command": "unknown", "payload": Data("{}".utf8).base64EncodedString(),
		]) + Data([10])
	func invoke(_ arguments: [String], input request: Data = envelope) throws -> (Int32, Data, Data) {
		let process = Process()
		process.executableURL = executable
		process.arguments = arguments
		process.environment = ProcessInfo.processInfo.environment.merging([
			"OPENXPC_PROJECT_ID": project, "OPENXPC_SESSION_ID": session,
		]) { _, new in new }
		let input = Pipe()
		let output = Pipe()
		let errors = Pipe()
		process.standardInput = input
		process.standardOutput = output
		process.standardError = errors
		try process.run()
		try input.fileHandleForWriting.write(contentsOf: request)
		try input.fileHandleForWriting.close()
		let data = output.fileHandleForReading.readDataToEndOfFile()
		let diagnostic = errors.fileHandleForReading.readDataToEndOfFile()
		process.waitUntilExit()
		return (process.terminationStatus, data, diagnostic)
	}
	let normal = try invoke([])
	#expect(normal.0 == 1)
	let record = try #require(JSONSerialization.jsonObject(with: normal.1) as? [String: Any])
	#expect(record["requestID"] as? String == requestID)
	#expect(record["projectID"] as? String == project)
	#expect(record["success"] as? Bool == false)
	#expect(record["error"] as? String == "invalidRequest")
	let quiet = try invoke(["--silent-errors"])
	#expect(quiet.0 == 1)
	#expect(quiet.1.isEmpty)
	#expect(quiet.2.isEmpty)
	let malformed = try invoke([], input: Data([10]))
	#expect(malformed.0 == 2)
	#expect(malformed.1.isEmpty)
	#expect(!malformed.2.isEmpty)
	let silentMalformed = try invoke(["--silent-errors"], input: Data([10]))
	#expect(silentMalformed.0 == 2)
	#expect(silentMalformed.1.isEmpty)
	#expect(silentMalformed.2.isEmpty)
}

@Test func generatedAgentClientEmitsBoundedFailureEnvelopeUnlessSilenced() throws {
	let spec = try OpenXPCSpecification(yaml: functionalContract)
	let source = try OpenXPCSourceGenerator.generate(spec: spec, target: "ProbeAgentClient").swift
	#expect(source.contains("func sendResponse(command: String, payload: Data, requestID: UUID)"))
	#expect(source.contains("case [\"--silent-errors\"]: silentErrors = true"))
	#expect(source.contains("error: failureCode"))
	#expect(source.contains("FileHandle.standardOutput.write(data + Data([10]))"))
}

@Test func rejectsAgentClientWithoutToolSchema() {
	#expect(throws: (any Error).self) {
		try OpenXPCSpecification(
			yaml: functionalContract.replacingOccurrences(
				of: "    tool:\n      label: Ping\n      description: Send a ping.\n", with: ""))
	}
}

@Test func generatesBoundedTypedPayloadsOnlyForAllowedOperations() throws {
	let spec = try OpenXPCSpecification(yaml: typedContract)
	let client = try OpenXPCSourceGenerator.generate(spec: spec, target: "WebAutomationClient")
	#expect(client.swift.contains("public struct SearchRequest: Codable, Equatable, Sendable"))
	#expect(client.swift.contains("public let query: String"))
	#expect(client.swift.contains("public let limit: Int?"))
	#expect(client.swift.contains("public let results: [String]"))
	#expect(client.swift.contains("public struct SearchMetadata: Codable, Equatable, Sendable"))
	#expect(client.swift.contains("public let metadata: SearchMetadata?"))
	#expect(client.swift.contains("raw.count <= 4096"))
	#expect(client.swift.contains("query.utf8.count <= 2048"))
	#expect(client.swift.contains("results.count <= 10"))
	#expect(!client.swift.contains("ExtractRequest"))
	#expect(client.piExtension == nil)
	let service = try OpenXPCSourceGenerator.generate(spec: spec, target: "WebApplication")
	#expect(service.swift.contains("ExtractRequest"))
	let piClient = try OpenXPCSourceGenerator.generate(spec: spec, target: "WebTerminalClient")
	#expect(piClient.swift.contains("ExtractResponse"))
	#expect(piClient.piExtension == nil)
}

@Test func rejectsUnsafeTypedContracts() {
	for invalid in [
		typedContract.replacingOccurrences(
			of: "type: string\n        maxLength: 2048", with: "type: string"),
		typedContract.replacingOccurrences(of: "response: SearchResponse", with: "response: Unknown"),
		typedContract.replacingOccurrences(of: "type: int", with: "type: Mystery"),
		typedContract.replacingOccurrences(of: "name: limit", with: "name: class"),
		typedContract.replacingOccurrences(of: "name: limit", with: "name: CodingKeys"),
		typedContract.replacingOccurrences(
			of: "name: SearchResponse", with: "name: OpenXPCGeneratedClientContract"),
		typedContract.replacingOccurrences(of: "maxItems: 10", with: "maxItems: 0"),
		typedContract.replacingOccurrences(of: "optional: true", with: "optional: invalid"),
		typedContract.replacingOccurrences(
			of: "type: int\n        optional: true", with: "type: SearchRequest\n        optional: true"),
	] {
		#expect(throws: (any Error).self) { try OpenXPCSpecification(yaml: invalid) }
	}
}

@Test func perTargetGenerationModeControlsOutputs() throws {
	let spec = try OpenXPCSpecification(yaml: functionalContract)
	#expect(spec.generation(for: "ProbeService") == .service)
	#expect(spec.generation(for: "ProbeClient") == .client)
	#expect(spec.generation(for: "ProbeAgentClient") == .agentClient)
	#expect(spec.generation(for: "Unknown") == nil)
	#expect(spec.role(for: "ProbeClient") == .client(["ping"]))
	let terminal = try OpenXPCSourceGenerator.generate(spec: spec, target: "ProbeAgentClient")
	#expect(terminal.swift.contains("\"ping\""))
	#expect(terminal.piExtension?.contains("pi.registerTool") == true)
	let client = try OpenXPCSourceGenerator.generate(spec: spec, target: "ProbeClient")
	#expect(client.piExtension == nil)
}

@Test func rejectsInvalidGenerationModesAndUnknownFields() {
	for invalid in [
		functionalContract.replacingOccurrences(of: "generate: service", with: "generate: client"),
		functionalContract.replacingOccurrences(of: "generate: agentClient", with: "generate: service"),
		functionalContract.replacingOccurrences(of: "generate: client\n", with: ""),
		functionalContract.replacingOccurrences(
			of: "generate: agentClient", with: "generate: unrecognized"),
		functionalContract.replacingOccurrences(
			of: "operations: [ping]", with: "operations: [missing]"),
		functionalContract + "\nextra: unexpected\n",
		functionalContract + "\nschemaVersion: 5\n",
		functionalContract + String(repeating: " ", count: 65_536),
	] {
		#expect(throws: (any Error).self) { try OpenXPCSpecification(yaml: invalid) }
	}
}

@Test func includesSingleMachineReadableSchema() throws {
	let data = try #require(OpenXPCSpecification.schema)
	let value = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
	#expect(value["title"] as? String == "OpenXPC contract")
	let required = try #require(value["required"] as? [String])
	#expect(!required.contains("schemaVersion"))
	let properties = try #require(value["properties"] as? [String: Any])
	#expect(properties["subscriptions"] != nil)
}
