// @frontmatter:start
// Runs named scenario collections, cases, and steps with scoped contexts and teardown.
// @frontmatter:end
import Foundation

/// A project-owned reference shared by collection hooks and all of its selected cases.
public protocol CollectionContext: AnyObject {}

/// A project-owned reference shared by hooks and steps of one case.
public protocol CaseContext: AnyObject {}

public enum ScenarioFailure: Error, CustomStringConvertible {
	case message(String)

	public var description: String {
		if case .message(let message) = self { return message }
		return "scenario failed"
	}
}

@MainActor public struct Step<Context: CaseContext> {
	public let name: String
	let execute: @MainActor (Context) async throws -> Void

	public init(_ name: String, execute: @escaping @MainActor (Context) async throws -> Void) {
		self.name = name
		self.execute = execute
	}
}

@MainActor public struct ScenarioCase<Collection: CollectionContext> {
	public let name: String
	let execute: @MainActor (Collection) async throws -> Void

	public init<Context: CaseContext>(
		_ name: String,
		context: @escaping @MainActor (Collection) throws -> Context,
		setup: (@MainActor (Context) async throws -> Void)? = nil,
		steps: [Step<Context>],
		teardown: (@MainActor (Context) async throws -> Void)? = nil
	) {
		self.name = name
		self.execute = { collection in
			let local = try context(collection)
			var failures: [String] = []
			do {
				try await setup?(local)
				for step in steps {
					guard
						!step.name.isEmpty
					else { throw ScenarioFailure.message("unnamed step") }
					print("  step: \(step.name)")
					try await step.execute(local)
				}
			} catch { failures.append(String(describing: error)) }
			do { try await teardown?(local) } catch { failures.append("case teardown: \(error)") }
			if !failures.isEmpty { throw ScenarioFailure.message(failures.joined(separator: "; ")) }
		}
	}
}

@MainActor public struct ScenarioCollection {
	public let name: String
	let caseNames: [String]
	let execute: @MainActor (String?) async throws -> Void

	public init<Context: CollectionContext>(
		_ name: String,
		context: @escaping @MainActor () throws -> Context,
		setup: (@MainActor (Context) async throws -> Void)? = nil,
		teardown: (@MainActor (Context) async throws -> Void)? = nil,
		cases: [ScenarioCase<Context>]
	) {
		self.name = name
		caseNames = cases.map(\.name)
		execute = { selected in
			let shared = try context()
			var failures: [String] = []
			do {
				try await setup?(shared)
				for testCase in cases where selected == nil || selected == testCase.name {
					print("case: \(testCase.name)")
					do { try await testCase.execute(shared) } catch {
						failures.append("\(testCase.name): \(error)")
					}
				}
			} catch { failures.append("collection setup: \(error)") }
			do { try await teardown?(shared) } catch { failures.append("collection teardown: \(error)") }
			if !failures.isEmpty { throw ScenarioFailure.message(failures.joined(separator: "; ")) }
		}
	}
}

@MainActor public struct ScenarioRegistry {
	private let collections: [ScenarioCollection]

	public init(_ collections: [ScenarioCollection]) throws {
		guard
			!collections.isEmpty,
			collections.count <= 64
		else { throw ScenarioFailure.message("expected 1...64 collections") }
		var names = Set<String>()
		var caseNames = Set<String>()
		for collection in collections {
			guard
				Self.valid(collection.name),
				names.insert(collection.name).inserted,
				collection.caseNames.count <= 100
			else { throw ScenarioFailure.message("invalid or duplicate collection: \(collection.name)") }
			for name in collection.caseNames {
				guard
					Self.valid(name),
					caseNames.insert(name).inserted
				else { throw ScenarioFailure.message("invalid or duplicate case: \(name)") }
			}
		}
		self.collections = collections
	}

	/// Registered names without constructing contexts or executing hooks.
	public var collectionNames: [String] { collections.map(\.name) }
	public var caseNames: [String] { collections.flatMap(\.caseNames) }

	public func runCollection(_ name: String) async throws {
		guard
			let collection = collections.first(where: { $0.name == name })
		else { throw ScenarioFailure.message("unknown collection: \(name)") }
		try await collection.execute(nil)
	}

	public func runCase(_ name: String) async throws {
		guard
			let collection = collections.first(where: { $0.caseNames.contains(name) })
		else { throw ScenarioFailure.message("unknown case: \(name)") }
		try await collection.execute(name)
	}

	private static func valid(_ name: String) -> Bool {
		name.range(of: "^[a-z][a-z0-9-]{0,63}$", options: .regularExpression) != nil
	}
}
