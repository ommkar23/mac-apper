// @frontmatter:start
// Observes unexpected Swift Testing issues without suppressing normal test reporting.
// @frontmatter:end
import Foundation
import Scenario
@_spi(Experimental) import Testing

private final class IssueCounter: @unchecked Sendable {
	private let lock = NSLock()
	private var failures = 0
	func record(_ issue: Issue) {
		lock.lock()
		defer { lock.unlock() }
		if issue.isFailure { failures += 1 }
	}
	var count: Int {
		lock.lock()
		defer { lock.unlock() }
		return failures
	}
}

@MainActor public struct ScenarioTestingObserver: ScenarioStepObserver {
	public init() {}
	public func validate() throws {
		guard
			Test.current != nil
		else {
			throw ScenarioFailure.message("ScenarioTestingObserver requires a current Swift Testing test")
		}
	}
	public func observe(
		_ identity: ScenarioStepIdentity,
		operation: @escaping @MainActor @Sendable () async throws -> Void
	) async -> ScenarioStepObservation {
		guard
			let test = Test.current
		else {
			return ScenarioStepObservation(problems: [
				ScenarioProblem(origin: .assertion, message: "Swift Testing context unavailable")
			])
		}
		let counter = IssueCounter()
		let scope = IssueHandlingTrait.compactMapIssues { issue in
			counter.record(issue)
			return issue
		}
		var problems: [ScenarioProblem] = []
		do {
			try await scope.provideScope(for: test, testCase: Test.Case.current) { try await operation() }
		} catch {
			problems.append(
				ScenarioProblem(
					origin: error is CancellationError ? .cancellation : .thrownError,
					message: String(describing: error)))
		}
		let unexpectedIssues = counter.count
		if unexpectedIssues > 0 {
			problems.append(
				ScenarioProblem(
					origin: .assertion, message: "\(unexpectedIssues) unexpected Swift Testing issue(s)"))
		}
		return ScenarioStepObservation(problems: problems, assertionsObserved: true)
	}
}
