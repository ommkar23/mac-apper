import Foundation
import Yams

public struct OpenXPCSpecification: Equatable, Sendable {
	public struct Service: Equatable, Sendable {
		public let identifier: String
		public let target: String
		public let maxPayloadBytes: Int
		public let timeoutSeconds: Int
	}

	public struct Subscription: Equatable, Sendable {
		public let name: String
		public let request: String
		public let response: String
		public let event: String
	}

	public struct Client: Equatable, Sendable {
		public let target: String
		public let operations: [String]
		public let subscriptions: [String]
		public let generation: Generation
	}

	public enum Generation: String, Equatable, Sendable {
		case service
		case client
		case agentClient
	}

	public enum Role: Equatable, Sendable {
		case service
		case client([String])
	}

	public let service: Service
	public let operations: [String]
	public let subscriptions: [Subscription]
	public let clients: [Client]
	public let dataSchema: OpenXPCDataSchema

	public static var schema: Data? {
		guard
			let url = Bundle.module.url(forResource: "openxpc.schema", withExtension: "json")
		else { return nil }
		return try? Data(contentsOf: url)
	}

	public static var generationSchema: Data? {
		guard let url = Bundle.module.url(forResource: "openxpc-gen.schema", withExtension: "json")
		else { return nil }
		return try? Data(contentsOf: url)
	}

	public init(contractYAML: String, generationYAML: String) throws {
		guard contractYAML.utf8.count <= 65_536, generationYAML.utf8.count <= 65_536
		else { throw SpecificationError.invalid("OpenXPC input exceeds 64 KiB") }
		let contract = try Self.mapping(
			Yams.load(yaml: contractYAML), required: ["service", "types", "operations"],
			allowed: ["service", "types", "operations", "subscriptions"])
		let generation = try Self.mapping(
			Yams.load(yaml: generationYAML), required: ["service", "clients"],
			allowed: ["service", "clients"])
		let contractService = try Self.mapping(
			contract["service"], required: ["identifier"],
			allowed: ["identifier", "maxPayloadBytes"])
		let generationService = try Self.mapping(
			generation["service"], required: ["target", "generate"],
			allowed: ["target", "generate", "timeoutSeconds"])
		var combined = contract
		combined["service"] = contractService.merging(generationService) { _, updated in updated }
		combined["clients"] = generation["clients"]
		try self.init(yaml: Yams.dump(object: combined), maxBytes: 131_072)
	}

	public init(yaml: String) throws {
		try self.init(yaml: yaml, maxBytes: 65_536)
	}

	private init(yaml: String, maxBytes: Int) throws {
		guard yaml.utf8.count <= maxBytes
		else { throw SpecificationError.invalid("specification exceeds size limit") }
		let rawDocument = try Yams.load(yaml: yaml)
		let document = try Self.mapping(
			rawDocument, required: ["service", "types", "operations", "clients"],
			allowed: ["service", "types", "operations", "subscriptions", "clients"])
		let serviceFields = try Self.mapping(
			document["service"], required: ["identifier", "target", "generate"],
			allowed: ["identifier", "target", "generate", "maxPayloadBytes", "timeoutSeconds"])
		guard
			serviceFields["generate"] as? String == Generation.service.rawValue
		else { throw SpecificationError.invalid("invalid service generation mode") }
		guard
			let identifier = serviceFields["identifier"] as? String,
			identifier.count <= 255,
			identifier.split(separator: ".", omittingEmptySubsequences: false).count >= 2,
			identifier.split(separator: ".", omittingEmptySubsequences: false).allSatisfy({ part in
				!part.isEmpty
					&& part.utf8.allSatisfy({
						(65...90).contains($0) || (97...122).contains($0)
							|| (48...57).contains($0) || $0 == 45
					})
			}),
			let serviceTarget = serviceFields["target"] as? String,
			Self.validName(serviceTarget)
		else { throw SpecificationError.invalid("invalid service") }
		guard
			(serviceFields["maxPayloadBytes"] == nil || serviceFields["maxPayloadBytes"] is Int),
			(serviceFields["timeoutSeconds"] == nil || serviceFields["timeoutSeconds"] is Int)
		else { throw SpecificationError.invalid("invalid service limits") }
		let payloadLimit = serviceFields["maxPayloadBytes"] as? Int ?? 32_768
		let timeout = serviceFields["timeoutSeconds"] as? Int ?? 30
		guard
			(1...65_536).contains(payloadLimit),
			(1...600).contains(timeout)
		else { throw SpecificationError.invalid("invalid service limits") }
		service = Service(
			identifier: identifier, target: serviceTarget,
			maxPayloadBytes: payloadLimit, timeoutSeconds: timeout)

		guard
			let rawOperations = document["operations"] as? [Any],
			!rawOperations.isEmpty,
			rawOperations.count <= 128
		else { throw SpecificationError.invalid("invalid operations") }
		let schema = try OpenXPCDataSchema(types: document["types"], operations: rawOperations)
		dataSchema = schema
		let names = schema.operations.map(\.name)
		operations = names

		let entries: [Any]
		if let raw = document["subscriptions"] {
			guard
				let values = raw as? [Any],
				!values.isEmpty,
				values.count <= 64
			else { throw SpecificationError.invalid("invalid subscriptions") }
			entries = values
		} else {
			entries = []
		}
		let typeNames = Set(schema.types.map(\.name))
		let reserved: Set<String> = [
			"OpenXPCGeneratedEvent", "OpenXPCGeneratedEventSinkProtocol",
			"OpenXPCGeneratedEmitter", "OpenXPCGeneratedSubscription",
		]
		if !entries.isEmpty {
			guard
				reserved.isDisjoint(with: typeNames),
				reserved.isDisjoint(with: names)
			else { throw SpecificationError.invalid("reserved generated subscription name") }
		}
		var parsedSubscriptions: [Subscription] = []
		for entry in entries {
			let fields = try Self.mapping(
				entry, required: ["name", "request", "response", "event"],
				allowed: ["name", "request", "response", "event"])
			guard
				let name = fields["name"] as? String,
				OpenXPCDataSchema.validIdentifier(name),
				!reserved.contains(name),
				!parsedSubscriptions.contains(where: { $0.name == name }),
				!names.contains(name),
				let request = fields["request"] as? String,
				typeNames.contains(request),
				let response = fields["response"] as? String,
				typeNames.contains(response),
				let event = fields["event"] as? String,
				typeNames.contains(event)
			else { throw SpecificationError.invalid("invalid subscription") }
			parsedSubscriptions.append(
				.init(name: name, request: request, response: response, event: event))
		}
		subscriptions = parsedSubscriptions

		let subscriptionNames = Set(subscriptions.map(\.name))
		guard
			let rawClients = document["clients"] as? [Any],
			!rawClients.isEmpty,
			rawClients.count <= 64
		else { throw SpecificationError.invalid("invalid clients") }
		var parsed: [Client] = []
		for entry in rawClients {
			let fields = try Self.mapping(
				entry, required: ["target", "generate", "operations"],
				allowed: ["target", "generate", "operations", "subscriptions"])
			guard
				let generation = (fields["generate"] as? String).flatMap(Generation.init(rawValue:)),
				generation != .service,
				let target = fields["target"] as? String,
				Self.validName(target),
				target != serviceTarget,
				!parsed.contains(where: { $0.target == target }),
				let allowed = fields["operations"] as? [String],
				allowed.count <= names.count,
				Set(allowed).count == allowed.count,
				allowed.allSatisfy(names.contains),
				let subscribed = fields["subscriptions"] == nil
					? [] : fields["subscriptions"] as? [String],
				!allowed.isEmpty || !subscribed.isEmpty,
				Set(subscribed).count == subscribed.count,
				subscribed.allSatisfy(subscriptionNames.contains),
				generation != .agentClient || subscribed.isEmpty
			else { throw SpecificationError.invalid("invalid client profile") }
			if generation == .agentClient {
				guard
					allowed.allSatisfy({ name in
						schema.operations.first(where: { $0.name == name })?.tool != nil
					})
				else { throw SpecificationError.invalid("agent client requires tool metadata") }
			}
			parsed.append(
				Client(
					target: target, operations: allowed,
					subscriptions: subscribed, generation: generation))
		}
		clients = parsed
	}

	public func role(for target: String) -> Role? {
		if target == service.target { return .service }
		guard
			let client = clients.first(where: { $0.target == target })
		else { return nil }
		return .client(client.operations)
	}

	public func generation(for target: String) -> Generation? {
		if target == service.target { return .service }
		return clients.first(where: { $0.target == target })?.generation
	}

	internal static func validName(_ value: String) -> Bool {
		let bytes = Array(value.utf8)
		guard
			!bytes.isEmpty,
			bytes.count <= 128
		else { return false }
		func letter(_ byte: UInt8) -> Bool {
			(65...90).contains(byte) || (97...122).contains(byte) || byte == 95
		}
		return letter(bytes[0])
			&& bytes.dropFirst().allSatisfy {
				letter($0) || (48...57).contains($0)
			}
	}

	private static func mapping(
		_ value: Any?, required: Set<String>, allowed: Set<String>
	) throws -> [String: Any] {
		guard
			let fields = value as? [String: Any],
			required.isSubset(of: Set(fields.keys)),
			Set(fields.keys).isSubset(of: allowed)
		else { throw SpecificationError.invalid("missing or unknown fields") }
		return fields
	}
}

public enum SpecificationError: Error, Equatable {
	case invalid(String)
}
