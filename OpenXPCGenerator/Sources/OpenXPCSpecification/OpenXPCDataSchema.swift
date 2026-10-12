import Foundation

public struct OpenXPCDataSchema: Equatable, Sendable {
	public struct Field: Equatable, Sendable {
		public let name: String
		public let type: String
		public let optional: Bool
		public let array: Bool
		public let maxLength: Int?
		public let maxBytes: Int?
		public let maxItems: Int?
		public let injected: String?
	}

	public struct Definition: Equatable, Sendable {
		public let name: String
		public let fields: [Field]
	}

	public struct Operation: Equatable, Sendable {
		public struct Tool: Equatable, Sendable {
			public let label: String
			public let description: String
			public let parametersJSON: String?
			public let imageArtifact: String?
		}
		public let name: String
		public let request: String
		public let response: String
		public let tool: Tool?
	}

	public let types: [Definition]
	public let operations: [Operation]

	private static let scalars: Set<String> = ["string", "int", "bool", "double", "data", "uuid"]
	private static let keywords: Set<String> = [
		"Any", "Bool", "Data", "Double", "Int", "String", "UUID", "Self", "Type", "Protocol",
		"as", "associatedtype", "break", "case", "catch", "class", "continue", "default", "defer",
		"do", "else", "enum", "extension", "false", "fileprivate", "for", "func", "guard", "if",
		"import", "in", "init", "inout", "internal", "is", "let", "nil", "operator", "private",
		"protocol", "public", "repeat", "rethrows", "return", "self", "static", "struct", "subscript",
		"super", "switch", "throw", "throws", "true", "try", "typealias", "var", "where", "while",
		"actor", "any", "async", "await", "borrowing", "consuming", "distributed", "dynamic",
		"final", "isolated", "macro", "mutating", "nonisolated", "nonmutating", "open", "override",
		"package", "required", "sending", "some", "unowned", "weak", "CodingKeys",
		"OpenXPCGeneratedClientContract", "OpenXPCGeneratedServiceContract",
		"OpenXPCGeneratedDataError", "_OpenXPCAnyCodingKey",
		"OpenXPCGeneratedService", "OpenXPCGeneratedListener", "OpenXPCGeneratedClient",
		"OpenXPCGeneratedProtocol", "OpenXPCGeneratedWire", "OpenXPCGeneratedRequest",
		"OpenXPCGeneratedResponse", "OpenXPCGeneratedFailure", "OpenXPCReplyBox",
		"OpenXPCGeneratedTerminalMain",
	]

	internal init(types rawTypes: Any?, operations rawOperations: [Any]) throws {
		guard
			let entries = rawTypes as? [Any],
			!entries.isEmpty,
			entries.count <= 256
		else { throw SpecificationError.invalid("invalid types") }
		var parsed: [Definition] = []
		var fieldCount = 0
		for entry in entries {
			let mapping = try Self.mapping(
				entry, required: ["name", "fields"], allowed: ["name", "fields"])
			guard
				let name = mapping["name"] as? String,
				Self.validIdentifier(name),
				!Self.scalars.contains(name),
				!parsed.contains(where: { $0.name == name }),
				let rawFields = mapping["fields"] as? [Any],
				rawFields.count <= 64
			else { throw SpecificationError.invalid("invalid or duplicate type") }
			var fields: [Field] = []
			for raw in rawFields {
				let value = try Self.mapping(
					raw, required: ["name", "type"],
					allowed: [
						"name", "type", "optional", "array", "maxLength", "maxBytes", "maxItems", "injected",
					])
				guard
					let fieldName = value["name"] as? String,
					Self.validIdentifier(fieldName),
					!fields.contains(where: { $0.name == fieldName }),
					let type = value["type"] as? String,
					OpenXPCSpecification.validName(type)
				else { throw SpecificationError.invalid("invalid field") }
				let optional = try Self.boolean(value, key: "optional")
				let array = try Self.boolean(value, key: "array")
				let length = try Self.bound(
					value, key: "maxLength", required: type == "string", allowed: type == "string",
					maximum: 65_536)
				let bytes = try Self.bound(
					value, key: "maxBytes", required: type == "data", allowed: type == "data", maximum: 65_536
				)
				let items = try Self.bound(
					value, key: "maxItems", required: array, allowed: array, maximum: 128)
				let injected = value["injected"] as? String
				guard
					value["injected"] == nil
						|| (injected == "projectRoot"
							&& type == "string" && !optional && !array && length == 4096)
				else { throw SpecificationError.invalid("invalid injected field") }
				fields.append(
					Field(
						name: fieldName, type: type, optional: optional, array: array,
						maxLength: length, maxBytes: bytes, maxItems: items, injected: injected))
			}
			fieldCount += fields.count
			guard
				fieldCount <= 2_048
			else { throw SpecificationError.invalid("too many fields") }
			parsed.append(Definition(name: name, fields: fields))
		}
		let known = Set(parsed.map(\.name))
		for definition in parsed {
			for field in definition.fields where !Self.scalars.contains(field.type) {
				guard
					known.contains(field.type)
				else { throw SpecificationError.invalid("unknown field type") }
			}
		}
		let lookup = Dictionary(uniqueKeysWithValues: parsed.map { ($0.name, $0) })
		var visited: Set<String> = []
		var visiting: Set<String> = []
		func visit(_ name: String) throws {
			if visited.contains(name) { return }
			guard
				visiting.insert(name).inserted
			else { throw SpecificationError.invalid("recursive type") }
			for field in lookup[name]?.fields ?? [] where known.contains(field.type) {
				try visit(field.type)
			}
			visiting.remove(name)
			visited.insert(name)
		}
		for definition in parsed { try visit(definition.name) }
		var operations: [Operation] = []
		for entry in rawOperations {
			let value = try Self.mapping(
				entry, required: ["name", "request", "response"],
				allowed: ["name", "request", "response", "tool"])
			guard
				let name = value["name"] as? String,
				Self.validIdentifier(name),
				!operations.contains(where: { $0.name == name }),
				let request = value["request"] as? String,
				known.contains(request),
				let response = value["response"] as? String,
				known.contains(response)
			else { throw SpecificationError.invalid("invalid typed operation") }
			var tool: Operation.Tool?
			if let raw = value["tool"] {
				let fields = try Self.mapping(
					raw, required: ["label", "description"],
					allowed: ["label", "description", "parameters", "imageArtifact"])
				guard
					let label = fields["label"] as? String,
					(1...80).contains(label.count),
					let description = fields["description"] as? String,
					(1...4096).contains(description.count),
					!label.unicodeScalars.contains(where: CharacterSet.controlCharacters.contains),
					!description.unicodeScalars.contains(where: {
						$0.value != 10 && CharacterSet.controlCharacters.contains($0)
					})
				else { throw SpecificationError.invalid("invalid tool metadata") }
				var parametersJSON: String?
				if let parameters = fields["parameters"] {
					guard
						let object = parameters as? [String: Any],
						object["type"] as? String == "object",
						object["additionalProperties"] as? Bool == false,
						let properties = object["properties"] as? [String: Any],
						let requestFields = lookup[request]?.fields,
						Set(properties.keys) == Set(requestFields.filter { $0.injected == nil }.map(\.name)),
						let required = object["required"] as? [String],
						Set(required)
							== Set(requestFields.filter { !$0.optional && $0.injected == nil }.map(\.name)),
						JSONSerialization.isValidJSONObject(object)
					else { throw SpecificationError.invalid("invalid Pi parameter schema") }
					let data = try JSONSerialization.data(withJSONObject: object, options: [.sortedKeys])
					guard
						data.count <= 16_384
					else { throw SpecificationError.invalid("oversized Pi parameter schema") }
					parametersJSON = String(decoding: data, as: UTF8.self)
				}
				let imageArtifact = fields["imageArtifact"] as? String
				if fields["imageArtifact"] != nil {
					guard
						let imageArtifact,
						imageArtifact.utf8.count <= 256
					else { throw SpecificationError.invalid("invalid image artifact path") }
					let components = imageArtifact.split(separator: ".", omittingEmptySubsequences: false)
					guard
						(1...4).contains(components.count)
					else { throw SpecificationError.invalid("invalid image artifact path") }
					var definition = lookup[response]
					for (index, component) in components.enumerated() {
						guard
							Self.validIdentifier(String(component)),
							let field = definition?.fields.first(where: { $0.name == component }),
							!field.array
						else { throw SpecificationError.invalid("unknown image artifact field") }
						if index == components.count - 1 {
							guard
								field.type == "string"
							else { throw SpecificationError.invalid("image artifact must be a path string") }
						} else {
							definition = lookup[field.type]
						}
					}
				}
				tool = Operation.Tool(
					label: label, description: description,
					parametersJSON: parametersJSON, imageArtifact: imageArtifact)
			}
			operations.append(Operation(name: name, request: request, response: response, tool: tool))
		}
		let toolRequests = Set(operations.filter { $0.tool != nil }.map(\.request))
		guard
			parsed.allSatisfy({ definition in
				let injected = definition.fields.filter { $0.injected != nil }
				return injected.isEmpty
					|| (toolRequests.contains(definition.name)
						&& injected.count == 1 && injected[0].name == "projectRoot")
			})
		else { throw SpecificationError.invalid("injected field must be a Pi tool request") }
		self.types = parsed
		self.operations = operations
	}

	internal static func validIdentifier(_ name: String) -> Bool {
		OpenXPCSpecification.validName(name) && !keywords.contains(name)
	}

	private static func mapping(
		_ value: Any, required: Set<String>, allowed: Set<String>
	) throws -> [String: Any] {
		guard
			let result = value as? [String: Any],
			required.isSubset(of: Set(result.keys)),
			Set(result.keys).isSubset(of: allowed)
		else { throw SpecificationError.invalid("missing or unknown typed field") }
		return result
	}

	private static func boolean(_ fields: [String: Any], key: String) throws -> Bool {
		guard
			let value = fields[key]
		else { return false }
		guard
			let boolean = value as? Bool
		else { throw SpecificationError.invalid("invalid \(key)") }
		return boolean
	}

	private static func bound(
		_ fields: [String: Any], key: String, required: Bool, allowed: Bool, maximum: Int
	) throws -> Int? {
		guard
			allowed || fields[key] == nil
		else { throw SpecificationError.invalid("unexpected \(key)") }
		guard
			let value = fields[key]
		else {
			guard
				!required
			else { throw SpecificationError.invalid("missing \(key)") }
			return nil
		}
		guard
			let number = value as? Int,
			(1...maximum).contains(number)
		else { throw SpecificationError.invalid("invalid \(key)") }
		return number
	}
}
