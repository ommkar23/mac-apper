// @frontmatter:start
// Runs selected declarative scenario phases with structured reports and compatible legacy hooks.
// @frontmatter:end
import Foundation

/// A lightweight project-owned reference shared by a collection's selected cases.
public protocol CollectionContext: AnyObject {}
/// A lightweight project-owned reference for one case. Acquire resources in setup.
public protocol CaseContext: AnyObject {}

public enum ScenarioFailure: Error, CustomStringConvertible {
	case message(String)
	public var description: String {
		if case .message(let message) = self { return message }
		return "scenario failed"
	}
}

@MainActor public struct Step<Context> {
	public let name: String
	let execute: @MainActor (Context) async throws -> Void
	public init(_ name: String, execute: @escaping @MainActor (Context) async throws -> Void) {
		self.name = name
		self.execute = execute
	}
}

extension ScenarioRecorder {
	func body<Context>(
		_ steps: [Step<Context>], context: Context?, caseName: String?, phase: ScenarioPhase,
		skipping: ScenarioSkipReason? = nil
	) async -> Bool {
		var blocked = skipping
		for step in steps {
			let identity = identity(caseName, phase, step.name)
			if cancelled { blocked = .cancelled }
			if let blocked { skip(identity, blocked); continue }
			guard
				let context
			else {
				skip(identity, .contextUnavailable)
				blocked = .contextUnavailable
				continue
			}
			if !(await run(
				identity,
				operation: {
					guard
						!step.name.isEmpty
					else { throw ScenarioFailure.message("unnamed step") }
					print("  step: \(step.name)")
					try await step.execute(context)
				}))
			{
				blocked = phase == .setup ? .priorSetupFailure : .priorBehaviourFailure
			}
		}
		return blocked == nil && !cancelled
	}
}

@MainActor public struct ScenarioCase<Collection: CollectionContext> {
	public let name: String
	private(set) var declarations: [String]
	let execute: @MainActor (Collection?, ScenarioRecorder, ScenarioSkipReason?) async -> Void

	public init<Context: CaseContext>(
		_ name: String, context: @escaping @MainActor (Collection) throws -> Context,
		setup: [Step<Context>] = [], behaviour: [Step<Context>], cleanup: [CleanupChain<Context>] = []
	) {
		self.name = name
		declarations =
			setup.map(\.name) + behaviour.map(\.name)
			+ cleanup.flatMap { [$0.name] + $0.steps.map(\.name) }
		execute = { collection, recorder, skipping in
			var local: Context?
			var reason = skipping
			if recorder.cancelled { reason = .cancelled }
			let identity = recorder.identity(name, .context, "context")
			if let reason {
				recorder.skip(identity, reason)
			} else if let collection {
				let created = await recorder.run(identity) { local = try context(collection) }
				if !created { reason = .contextUnavailable }
			} else {
				recorder.skip(identity, .contextUnavailable); reason = .contextUnavailable
			}
			let setupOK = await recorder.body(
				setup, context: local, caseName: name, phase: .setup, skipping: reason)
			_ = await recorder.body(
				behaviour, context: local, caseName: name, phase: .behaviour,
				skipping: reason ?? (setupOK ? nil : .priorSetupFailure))
			await recorder.cleanup(
				cleanup, context: local, caseName: name, unavailable: reason ?? .contextUnavailable)
		}
	}

	public init<Context: CaseContext>(
		_ name: String, context: @escaping @MainActor (Collection) throws -> Context,
		setup: (@MainActor (Context) async throws -> Void)? = nil, steps: [Step<Context>],
		teardown: (@MainActor (Context) async throws -> Void)? = nil
	) {
		self.init(
			name, context: context, setup: setup.map { [Step("case setup", execute: $0)] } ?? [],
			behaviour: steps,
			cleanup: teardown.map {
				[CleanupChain("case teardown", steps: [Step("case teardown", execute: $0)])]
			} ?? [])
		declarations = []
	}
}

@MainActor public struct ScenarioCollection {
	public let name: String
	let caseNames: [String]
	private(set) var declarations: [String]
	let execute: @MainActor (String?, (any ScenarioStepObserver)?) async -> ScenarioReport

	public init<Context: CollectionContext>(
		_ name: String, context: @escaping @MainActor () throws -> Context,
		setup: [Step<Context>], cases: [ScenarioCase<Context>], cleanup: [CleanupChain<Context>] = []
	) {
		self.name = name
		caseNames = cases.map(\.name)
		declarations =
			setup.map(\.name) + cleanup.flatMap { [$0.name] + $0.steps.map(\.name) }
			+ cases.flatMap(\.declarations)
		execute = { selected, observer in
			let recorder = ScenarioRecorder(name, observer: observer)
			var shared: Context?
			var reason: ScenarioSkipReason?
			let identity = recorder.identity(nil, .context, "context")
			if recorder.cancelled {
				recorder.skip(identity, .cancelled); reason = .cancelled
			} else if !(await recorder.run(identity, operation: { shared = try context() })) {
				reason = .contextUnavailable
			}
			let setupOK = await recorder.body(
				setup, context: shared, caseName: nil, phase: .setup, skipping: reason)
			for testCase in cases where selected == nil || selected == testCase.name {
				print("case: \(testCase.name)")
				await testCase.execute(
					shared, recorder, reason ?? (setupOK ? nil : .collectionSetupFailure))
			}
			await recorder.cleanup(
				cleanup, context: shared, caseName: nil, unavailable: reason ?? .contextUnavailable)
			return ScenarioReport(steps: recorder.steps, cancellationRequested: Task.isCancelled)
		}
	}

	public init<Context: CollectionContext>(
		_ name: String, context: @escaping @MainActor () throws -> Context,
		setup: (@MainActor (Context) async throws -> Void)? = nil,
		teardown: (@MainActor (Context) async throws -> Void)? = nil, cases: [ScenarioCase<Context>]
	) {
		self.init(
			name, context: context, setup: setup.map { [Step("collection setup", execute: $0)] } ?? [],
			cases: cases,
			cleanup: teardown.map {
				[CleanupChain("collection teardown", steps: [Step("collection teardown", execute: $0)])]
			} ?? [])
		declarations = cases.flatMap(\.declarations)
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
			guard
				collection.declarations.allSatisfy({
					!$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
				})
			else { throw ScenarioFailure.message("unnamed lifecycle declaration") }
		}
		self.collections = collections
	}
	public var collectionNames: [String] { collections.map(\.name) }
	public var caseNames: [String] { collections.flatMap(\.caseNames) }
	public func executeCollection(_ name: String, observer: (any ScenarioStepObserver)? = nil)
		async throws -> ScenarioReport
	{
		guard
			let collection = collections.first(where: { $0.name == name })
		else { throw ScenarioFailure.message("unknown collection: \(name)") }
		try observer?.validate()
		return await collection.execute(nil, observer)
	}
	public func executeCase(_ name: String, observer: (any ScenarioStepObserver)? = nil) async throws
		-> ScenarioReport
	{
		guard
			let collection = collections.first(where: { $0.caseNames.contains(name) })
		else { throw ScenarioFailure.message("unknown case: \(name)") }
		try observer?.validate()
		return await collection.execute(name, observer)
	}
	public func runCollection(_ name: String) async throws {
		try await executeCollection(name).requireSuccess()
	}
	public func runCase(_ name: String) async throws { try await executeCase(name).requireSuccess() }
	private static func valid(_ name: String) -> Bool {
		name.range(of: "^[a-z][a-z0-9-]{0,63}$", options: .regularExpression) != nil
	}
}
