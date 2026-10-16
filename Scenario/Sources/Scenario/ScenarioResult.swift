// @frontmatter:start
// Defines lifecycle identities, observations, structured execution reports and failures.
// @frontmatter:end
import Foundation

public enum ScenarioPhase: Sendable { case context, setup, behaviour, cleanup }
public enum ScenarioStepStatus: Sendable { case passed, completed, failed, skipped }
public enum ScenarioSkipReason: Sendable {
	case priorSetupFailure, priorBehaviourFailure, collectionSetupFailure, contextUnavailable
	case cancelled, cleanupPrerequisiteFailed, resourceNotAcquired
}
public struct ScenarioStepIdentity: Sendable {
	public let collection: String
	public let caseName: String?
	public let phase: ScenarioPhase
	public let chain: String?
	public let step: String
}
public struct ScenarioProblem: Sendable {
	public enum Origin: Sendable { case thrownError, assertion, cancellation, eligibility }
	public let origin: Origin
	public let message: String
	public init(origin: Origin, message: String) {
		self.origin = origin
		self.message = String(message.prefix(4096))
	}
}
public struct ScenarioStepObservation: Sendable {
	public let problems: [ScenarioProblem]
	public let assertionsObserved: Bool
	public init(problems: [ScenarioProblem] = [], assertionsObserved: Bool = false) {
		self.problems = problems
		self.assertionsObserved = assertionsObserved
	}
}
@MainActor public protocol ScenarioStepObserver {
	/// Called before any context is constructed. Throw when observation is unavailable.
	func validate() throws
	func observe(
		_ identity: ScenarioStepIdentity,
		operation: @escaping @MainActor @Sendable () async throws -> Void
	) async -> ScenarioStepObservation
}
public struct ScenarioStepResult: Sendable {
	public let identity: ScenarioStepIdentity
	public let status: ScenarioStepStatus
	public let skipReason: ScenarioSkipReason?
	public let elapsed: Duration
	public let problems: [ScenarioProblem]
	public let assertionsObserved: Bool
}
public struct ScenarioReport: Sendable {
	public let steps: [ScenarioStepResult]
	let cancellationRequested: Bool
	init(steps: [ScenarioStepResult], cancellationRequested: Bool = false) {
		self.steps = steps
		self.cancellationRequested = cancellationRequested
	}
	public var cancelled: Bool {
		cancellationRequested
			|| steps.contains {
				$0.problems.contains { $0.origin == .cancellation } || $0.skipReason == .cancelled
			}
	}
	public var bodyProblems: [ScenarioProblem] {
		steps.filter { $0.identity.phase != .cleanup }.flatMap(\.problems)
	}
	public var cleanupProblems: [ScenarioProblem] {
		steps.filter { $0.identity.phase == .cleanup }.flatMap(\.problems)
	}
	public func requireSuccess() throws {
		if cancelled || !bodyProblems.isEmpty || !cleanupProblems.isEmpty {
			throw ScenarioExecutionFailure(report: self)
		}
	}
}
public struct ScenarioExecutionFailure: Error, CustomStringConvertible {
	public let report: ScenarioReport
	public var description: String {
		let messages = report.steps.flatMap { result in
			let identity = result.identity
			let path = [
				identity.collection, identity.caseName, String(describing: identity.phase), identity.chain,
				identity.step,
			]
			.compactMap { $0 }.joined(separator: " / ")
			return result.problems.map { "\(path): \($0.message)" }
		}
		return (messages + (report.cancelled ? ["scenario cancelled"] : [])).joined(separator: "; ")
	}
}

@MainActor final class ScenarioRecorder {
	var steps: [ScenarioStepResult] = []
	let collection: String
	let observer: (any ScenarioStepObserver)?
	init(_ collection: String, observer: (any ScenarioStepObserver)?) {
		self.collection = collection
		self.observer = observer
	}
	var cancelled: Bool { Task.isCancelled || ScenarioReport(steps: steps).cancelled }
	func identity(_ caseName: String?, _ phase: ScenarioPhase, _ step: String, chain: String? = nil)
		-> ScenarioStepIdentity
	{
		ScenarioStepIdentity(
			collection: collection, caseName: caseName, phase: phase, chain: chain, step: step)
	}
	func skip(_ identity: ScenarioStepIdentity, _ reason: ScenarioSkipReason) {
		steps.append(
			ScenarioStepResult(
				identity: identity, status: .skipped, skipReason: reason, elapsed: .zero, problems: [],
				assertionsObserved: false))
	}
	func run(
		_ identity: ScenarioStepIdentity, failureOrigin: ScenarioProblem.Origin? = nil,
		operation: @escaping @MainActor @Sendable () async throws -> Void
	) async -> Bool {
		let start = ContinuousClock.now
		let observation: ScenarioStepObservation
		if let observer {
			observation = await observer.observe(identity, operation: operation)
		} else {
			do {
				try await operation()
				observation = ScenarioStepObservation()
			} catch {
				observation = ScenarioStepObservation(problems: [Self.problem(error)])
			}
		}
		let problems = observation.problems.map { problem in
			if let failureOrigin, problem.origin == .thrownError {
				return ScenarioProblem(origin: failureOrigin, message: problem.message)
			}
			return problem
		}
		let status: ScenarioStepStatus =
			problems.isEmpty ? (observation.assertionsObserved ? .passed : .completed) : .failed
		steps.append(
			ScenarioStepResult(
				identity: identity, status: status, skipReason: nil, elapsed: start.duration(to: .now),
				problems: problems, assertionsObserved: observation.assertionsObserved))
		return observation.problems.isEmpty
	}
	static func problem(_ error: any Error) -> ScenarioProblem {
		ScenarioProblem(
			origin: error is CancellationError ? .cancellation : .thrownError,
			message: String(describing: error))
	}
}
