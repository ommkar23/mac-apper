import Foundation

/// Emits self-contained, target-scoped XPC service and client sources.
public enum OpenXPCSourceGenerator {
	public enum ServiceDispatch: Sendable { case handlers, controllers }

	public struct GeneratedFiles: Sendable {
		public let swift: String
		public let piExtension: String?
	}

	public static func generate(
		spec: OpenXPCSpecification, target: String,
		serviceDispatch: ServiceDispatch = .controllers
	) throws -> GeneratedFiles {
		guard
			let mode = spec.generation(for: target),
			let role = spec.role(for: target)
		else { throw SpecificationError.invalid("unknown target") }
		let operations: [String]
		switch role {
		case .service: operations = spec.operations
		case .client(let allowed): operations = allowed
		}
		return try OpenXPCFunctionalGenerator.generate(
			spec, target: target, mode: mode,
			operations: operations, serviceDispatch: serviceDispatch)
	}
}
