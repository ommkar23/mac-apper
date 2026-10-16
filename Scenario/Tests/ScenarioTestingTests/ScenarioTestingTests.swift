import Foundation
import Scenario
import ScenarioTesting
@_spi(Experimental) import Testing

@MainActor private final class ObservedShared: CollectionContext { var constructed = false }
@MainActor private final class ObservedLocal: CaseContext { var marked = false }
@MainActor private final class ReportBox { var report: ScenarioReport? }
private final class ObservedIssueCount: @unchecked Sendable {
	private let lock = NSLock()
	private var value = 0
	func increment() { lock.lock(); value += 1; lock.unlock() }
	var count: Int { lock.lock(); defer { lock.unlock() }; return value }
}

@MainActor private func observedRegistry(
	_ steps: [Step<ObservedLocal>], cleanup: [CleanupChain<ObservedLocal>] = []
) throws -> ScenarioRegistry {
	try ScenarioRegistry([
		ScenarioCollection(
			"observed", context: ObservedShared.init,
			cases: [
				ScenarioCase(
					"observed-case", context: { _ in ObservedLocal() }, behaviour: steps, cleanup: cleanup)
			])
	])
}

@Test @MainActor func observerDetectsNonthrowingAssertionsWithoutSuppressingThem() async throws {
	let registry = try observedRegistry(
		[
			Step("assert") { _ in #expect(Bool(false), "intentional lifecycle fixture") },
			Step("marker") { $0.marked = true },
		],
		cleanup: [
			CleanupChain(
				"cleanup",
				steps: [
					Step("assert cleanup") { _ in #expect(Bool(false), "intentional lifecycle fixture") },
					Step("unsafe") { _ in },
				])
		])
	let test = try #require(Test.current)
	let forwarded = ObservedIssueCount()
	let outer = IssueHandlingTrait.compactMapIssues { issue in
		if issue.comments.contains(where: { $0.rawValue == "intentional lifecycle fixture" }) {
			forwarded.increment()
			return nil
		}
		return issue
	}
	let box = ReportBox()
	try await outer.provideScope(for: test, testCase: Test.Case.current) { @MainActor in
		box.report = try await registry.executeCase(
			"observed-case", observer: ScenarioTestingObserver())
	}
	let result = try #require(box.report)
	#expect(forwarded.count == 2)
	#expect(result.bodyProblems.count == 1)
	#expect(result.cleanupProblems.count == 1)
	#expect(
		result.steps.contains {
			$0.identity.step == "marker" && $0.skipReason == .priorBehaviourFailure
		})
	#expect(
		result.steps.contains {
			$0.identity.step == "unsafe" && $0.skipReason == .cleanupPrerequisiteFailed
		})
	#expect(throws: ScenarioExecutionFailure.self) { try result.requireSuccess() }
}

@Test @MainActor func observerKnownIssuesRemainSuccessful() async throws {
	let registry = try observedRegistry([
		Step("known") { _ in
			withKnownIssue("expected") { #expect(Bool(false)) }
		}, Step("pass") { _ in #expect(Bool(true)) },
	])
	let report = try await registry.executeCase("observed-case", observer: ScenarioTestingObserver())
	try report.requireSuccess()
	#expect(report.steps.allSatisfy { $0.status == .passed })
}

@Test @MainActor func observerRequireFailureIsReported() async throws {
	let registry = try observedRegistry([
		Step("require") { _ in try #require(Bool(false), "intentional lifecycle fixture") }
	])
	let test = try #require(Test.current)
	let outer = IssueHandlingTrait.compactMapIssues { issue in
		issue.comments.contains { $0.rawValue == "intentional lifecycle fixture" } ? nil : issue
	}
	let box = ReportBox()
	try await outer.provideScope(for: test, testCase: Test.Case.current) { @MainActor in
		box.report = try await registry.executeCase(
			"observed-case", observer: ScenarioTestingObserver())
	}
	#expect(try #require(box.report).bodyProblems.contains { $0.origin == .assertion })
}

@MainActor private func rejectsWithoutTestContext() async throws -> Bool {
	let shared = ObservedShared()
	let registry = try ScenarioRegistry([
		ScenarioCollection(
			"missing",
			context: {
				shared.constructed = true
				return shared
			}, cases: [ScenarioCase("missing-case", context: { _ in ObservedLocal() }, behaviour: [])])
	])
	do {
		_ = try await registry.executeCase("missing-case", observer: ScenarioTestingObserver())
		return false
	} catch { return !shared.constructed }
}

@Test @MainActor func observerRejectsMissingTestContextBeforeAcquisition() async throws {
	let rejected = try await Task.detached { try await rejectsWithoutTestContext() }.value
	#expect(rejected)
}

@Test @MainActor func observerScopesAreIsolatedAcrossSuspension() async throws {
	let registry = try observedRegistry([
		Step("suspend") { _ in
			try await Task.sleep(for: .milliseconds(5)); #expect(Bool(true))
		}
	])
	let failing = try observedRegistry([
		Step("suspend fail") { _ in
			try await Task.sleep(for: .milliseconds(2))
			#expect(Bool(false), "intentional lifecycle fixture")
		}
	])
	let test = try #require(Test.current)
	let box = ReportBox()
	let outer = IssueHandlingTrait.compactMapIssues { issue in
		issue.comments.contains { $0.rawValue == "intentional lifecycle fixture" } ? nil : issue
	}
	try await outer.provideScope(for: test, testCase: Test.Case.current) { @MainActor in
		async let first = registry.executeCase("observed-case", observer: ScenarioTestingObserver())
		async let second = failing.executeCollection("observed", observer: ScenarioTestingObserver())
		let reports = try await [first, second]
		try reports[0].requireSuccess()
		#expect(reports[0].steps.allSatisfy { $0.status == .passed })
		box.report = reports[1]
	}
	#expect(try #require(box.report).bodyProblems.count == 1)
}

@Test @MainActor func observerCleanupRetainsTestingScopeAfterCancellation() async throws {
	let registry = try observedRegistry(
		[Step("cancel") { _ in throw CancellationError() }],
		cleanup: [
			CleanupChain(
				"release",
				steps: [
					Step("observed cleanup") { _ in
						#expect(Test.current != nil)
						#expect(!Task.isCancelled)
						try await Task.sleep(for: .milliseconds(2))
					}
				])
		])
	let report = try await registry.executeCase("observed-case", observer: ScenarioTestingObserver())
	#expect(report.cancelled)
	#expect(report.cleanupProblems.isEmpty)
	#expect(report.steps.contains { $0.identity.step == "observed cleanup" && $0.status == .passed })
}

@Test @MainActor func observerWarningsDoNotFailTheReport() async throws {
	let registry = try observedRegistry([
		Step("warning") { _ in
			Issue.record("intentional warning fixture", severity: .warning)
		}
	])
	let report = try await registry.executeCase("observed-case", observer: ScenarioTestingObserver())
	try report.requireSuccess()
	#expect(report.steps.allSatisfy { $0.status == .passed })
}
