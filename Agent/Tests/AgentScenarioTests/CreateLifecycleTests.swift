// @frontmatter:start
// Checks Create's absolute budget, partial acquisition, cancellation and aggregate cleanup offline.
// @frontmatter:end
import Foundation
import Scenario
import ScenarioTesting
@_spi(Experimental) import Testing

@MainActor private final class CreateFixtureContext: CreateCaseContext {
	var release: @MainActor () async throws -> Void = {}
	override func cleanupResources() async throws { try await release() }
}

@Suite @MainActor struct CreateLifecycleTests {
	private func registry(
		_ local: CreateFixtureContext, setup: [Step<CreateFixtureContext>] = [],
		behaviour: [Step<CreateFixtureContext>] = [], collection: CreateCollection = CreateCollection(),
		emit: @escaping () -> Void = {}
	) throws -> ScenarioRegistry {
		try ScenarioRegistry([
			ScenarioCollection(
				"create-fixture", context: { collection }, setup: [],
				cases: [
					CreateCases.makeCase(
						"create-fixture-case", context: { local }, setup: setup, behaviour: behaviour)
				],
				cleanup: [CreateCollection.confirmationChain(emit: emit)])
		])
	}

	@Test func absoluteBudgetIncludesSetupAndAwaitsLosingWork() async throws {
		let local = CreateFixtureContext()
		local.budget = .milliseconds(400)
		var finished = false, cleaned = false, later = false
		var initialDeadline: ContinuousClock.Instant?
		local.release = {
			#expect(finished); #expect(!Task.isCancelled); cleaned = true
		}
		let registry = try registry(
			local,
			setup: [
				CreateCases.step("consume setup") { context in
					initialDeadline = context.deadline
					#expect(initialDeadline != nil)
					try await Task.sleep(for: .milliseconds(220))
				}
			],
			behaviour: [
				CreateCases.step("consume remaining") { context in
					#expect(context.deadline == initialDeadline)
					context.startBudget()
					#expect(context.deadline == initialDeadline)
					do { try await Task.sleep(for: .seconds(10)) } catch {
						try? await Task.sleep(for: .milliseconds(10))
						finished = true
						throw error
					}
				}, CreateCases.step("later") { _ in later = true },
			])
		let report = try await registry.executeCollection(
			"create-fixture", observer: ScenarioTestingObserver())
		#expect(!report.bodyProblems.isEmpty)
		#expect(finished && cleaned && !later && local.cleanupConfirmed)
		#expect(!local.runPassed)
	}

	@Test func expiredBudgetNeverStartsAcquisitionAndCleanupStillRuns() async throws {
		let local = CreateFixtureContext()
		local.budget = .zero
		var acquired = false, cleaned = false
		local.release = { cleaned = true }
		let registry = try registry(
			local, setup: [CreateCases.step("acquire") { _ in acquired = true }])
		let report = try await registry.executeCollection(
			"create-fixture", observer: ScenarioTestingObserver())
		#expect(!acquired && cleaned && local.cleanupConfirmed)
		#expect(!report.bodyProblems.isEmpty)
	}

	@Test func failedCleanupCannotKeepAnEarlierConfirmation() async throws {
		let local = CreateFixtureContext()
		try await local.cleanup()
		#expect(local.cleanupConfirmed)
		local.release = { throw ScenarioFailure.message("retry failure") }
		do { try await local.cleanup(); Issue.record("Expected cleanup failure") } catch {}
		#expect(!local.cleanupConfirmed)
	}

	@Test func partialSetupIsRegisteredBeforeFailure() async throws {
		let local = CreateFixtureContext(), collection = CreateCollection()
		var uncertain = false, cleaned = false
		local.release = {
			#expect(uncertain); cleaned = true; throw ScenarioFailure.message("uncertain submission")
		}
		let registry = try registry(
			local,
			setup: [
				CreateCases.step("partial submission") { _ in
					#expect(collection.contexts.count == 1)
					uncertain = true
					throw ScenarioFailure.message("submission failed before project capture")
				}
			], collection: collection)
		let report = try await registry.executeCollection("create-fixture")
		#expect(cleaned && !local.cleanupConfirmed && !local.runPassed)
		#expect(report.cleanupProblems.count == 2)
	}

	@Test func collectionConfirmsOnceAndRejectsEmptyOrFailedContexts() async throws {
		let collection = CreateCollection(), first = CreateFixtureContext(),
			second = CreateFixtureContext()
		var count = 0
		#expect(throws: ScenarioFailure.self) { try collection.confirmCleanup { count += 1 } }
		collection.contexts = [first, second]
		try await first.cleanup()
		#expect(throws: ScenarioFailure.self) { try collection.confirmCleanup { count += 1 } }
		try await second.cleanup()
		try collection.confirmCleanup { count += 1 }
		try collection.confirmCleanup { count += 1 }
		#expect(count == 1)
	}

	@Test func earlierSuccessCannotConfirmLaterCleanupFailure() async throws {
		let first = CreateFixtureContext(), second = CreateFixtureContext(),
			collection = CreateCollection()
		var emitted = false
		second.release = { throw ScenarioFailure.message("second cleanup unconfirmed") }
		let registry = try ScenarioRegistry([
			ScenarioCollection(
				"create-multiple", context: { collection }, setup: [],
				cases: [
					CreateCases.makeCase("create-first", context: { first }, setup: [], behaviour: []),
					CreateCases.makeCase("create-second", context: { second }, setup: [], behaviour: []),
				], cleanup: [CreateCollection.confirmationChain { emitted = true }])
		])
		let report = try await registry.executeCollection(
			"create-multiple", observer: ScenarioTestingObserver())
		#expect(first.cleanupConfirmed && !second.cleanupConfirmed)
		#expect(collection.contexts.count == 2 && !emitted)
		#expect(report.cleanupProblems.count == 2)
	}

	@Test func callerCancellationAwaitsUncancelledCleanup() async throws {
		let local = CreateFixtureContext()
		var started = false, cleaned = false, returned = false
		local.release = {
			#expect(!local.runPassed)
			#expect(returned && !Task.isCancelled)
			try await Task.sleep(for: .milliseconds(10)); cleaned = true
		}
		let registry = try registry(
			local,
			behaviour: [
				CreateCases.step("wait") { context in
					context.runPassed = true
					started = true
					defer { returned = true }
					try await Task.sleep(for: .seconds(10))
				}
			])
		let task = Task { try await registry.executeCollection("create-fixture") }
		while !started { await Task.yield() }
		task.cancel()
		let report = try await task.value
		#expect(cleaned && report.cancelled && !local.runPassed)
	}

	@Test func retentionDistinguishesSuccessfulAndThrownFinalPhase() async throws {
		for fail in [false, true] {
			let local = CreateFixtureContext()
			var keptPass: Bool?
			local.release = { keptPass = local.runPassed }
			let registry = try registry(
				local,
				behaviour: [
					CreateCases.step("final phase") { context in
						context.runPassed = true
						if fail { throw ScenarioFailure.message("late final-phase failure") }
					}
				])
			let report = try await registry.executeCollection(
				"create-fixture", observer: ScenarioTestingObserver())
			#expect(keptPass == !fail)
			#expect(report.bodyProblems.isEmpty == !fail)
		}
	}

	@Test func observedLateFailureClearsPassBeforeResourceRetention() async throws {
		let local = CreateFixtureContext()
		var retained = false
		local.release = { retained = !local.runPassed }
		let registry = try registry(
			local,
			behaviour: [
				CreateCases.step("apparent final pass") { context in
					context.runPassed = true
					#expect(Bool(false), "create-late-body-fixture")
				}
			])
		let suppress = IssueHandlingTrait.compactMapIssues { issue in
			if issue.comments.contains(where: { $0.rawValue == "create-late-body-fixture" }) {
				return nil
			}
			return issue
		}
		let test = try #require(Test.current)
		var report: ScenarioReport?
		try await suppress.provideScope(for: test, testCase: Test.Case.current) { @MainActor in
			report = try await registry.executeCollection(
				"create-fixture", observer: ScenarioTestingObserver())
		}
		#expect(!(try #require(report)).bodyProblems.isEmpty)
		#expect(retained && !local.runPassed)
	}

	@Test func observedFailuresGatePassAndConfirmation() async throws {
		for cleanupFailure in [false, true] {
			let local = CreateFixtureContext()
			var later = false, emitted = false
			local.release = { if cleanupFailure { #expect(Bool(false), "create-cleanup-fixture") } }
			let registry = try registry(
				local,
				behaviour: [
					CreateCases.step("assert") { _ in
						if !cleanupFailure { #expect(Bool(false), "create-body-fixture") }
					},
					CreateCases.step("later") { context in
						later = true; context.runPassed = true
					},
				], emit: { emitted = true })
			let suppress = IssueHandlingTrait.compactMapIssues { issue in
				if issue.comments.contains(where: {
					["create-cleanup-fixture", "create-body-fixture"].contains($0.rawValue)
				}) {
					return nil
				}
				return issue
			}
			let test = try #require(Test.current)
			var report: ScenarioReport?
			try await suppress.provideScope(for: test, testCase: Test.Case.current) { @MainActor in
				report = try await registry.executeCollection(
					"create-fixture", observer: ScenarioTestingObserver())
			}
			let result = try #require(report)
			if cleanupFailure {
				#expect(later && !emitted && !result.cleanupProblems.isEmpty)
			} else {
				#expect(!later && !local.runPassed && !result.bodyProblems.isEmpty)
			}
		}
	}
}
