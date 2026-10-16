// @frontmatter:start
// Exercises Chat's shared deadline, observed assertion gating and fail-closed cleanup without live sessions.
// @frontmatter:end
import Foundation
import Scenario
import ScenarioTesting
@_spi(Experimental) import Testing

@Suite @MainActor struct ChatLifecycleTests {
	private func registry(
		_ context: ChatCaseContext, setup: [Step<ChatCaseContext>] = [],
		behaviour: [Step<ChatCaseContext>] = [], collection: ChatCollection = ChatCollection()
	) throws -> ScenarioRegistry {
		try ScenarioRegistry([
			ScenarioCollection(
				"chat-fixture", context: { collection }, setup: [],
				cases: [
					ChatModelCases.makeCase(
						"chat-fixture-case", context: { context }, setup: setup, behaviour: behaviour)
				], cleanup: [ChatCollection.confirmationChain(emit: {})])
		])
	}

	@Test func oneDeadlineSpansSetupAndBehaviour() async throws {
		let context = ChatCaseContext()
		context.budget = .milliseconds(400)
		var later = false
		var cancelled = false
		var cleaned = false
		context.ownCleanup {
			#expect(!Task.isCancelled)
			try await Task.sleep(for: .milliseconds(10))
			cleaned = true
		}
		let registry = try registry(
			context,
			setup: [
				ChatModelCases.step("consume setup budget") { _ in
					try await Task.sleep(for: .milliseconds(220))
				}
			],
			behaviour: [
				ChatModelCases.step("wait past remaining budget") { _ in
					do { try await Task.sleep(for: .milliseconds(250)) } catch {
						cancelled = Task.isCancelled; throw error
					}
				}, ChatModelCases.step("later") { _ in later = true },
			])
		let report = try await registry.executeCollection(
			"chat-fixture", observer: ScenarioTestingObserver())
		#expect(!report.bodyProblems.isEmpty)
		#expect(cancelled && cleaned && !later)
		#expect(context.cleanupConfirmed)
		#expect(
			report.steps.contains {
				$0.identity.step == "audit completed Chat presentation"
					&& $0.skipReason == .priorBehaviourFailure
			})
	}

	@Test func successfulCollectionConfirmsExactlyOnce() async throws {
		let first = ChatCaseContext(), second = ChatCaseContext()
		var confirmations = 0
		let registry = try ScenarioRegistry([
			ScenarioCollection(
				"successful-chat-cases", context: ChatCollection.init, setup: [],
				cases: [
					ChatModelCases.makeCase("first-chat-case", context: { first }, setup: [], behaviour: []),
					ChatModelCases.makeCase(
						"second-chat-case", context: { second }, setup: [], behaviour: []),
				], cleanup: [ChatCollection.confirmationChain { confirmations += 1 }])
		])
		try await registry.executeCollection(
			"successful-chat-cases", observer: ScenarioTestingObserver()
		).requireSuccess()
		#expect(first.cleanupConfirmed && second.cleanupConfirmed)
		#expect(confirmations == 1)
	}

	@Test func partialAcquisitionRunsReverseCleanupAndAggregates() async throws {
		let context = ChatCaseContext()
		let collection = ChatCollection()
		var order: [Int] = []
		context.releaseSessions = {
			order.append(0); throw ScenarioFailure.message("session-release")
		}
		let registry = try registry(
			context,
			setup: [
				ChatModelCases.step("partial acquisition") { local in
					local.ownCleanup {
						order.append(1); throw ScenarioFailure.message("first-release")
					}
					local.ownCleanup {
						order.append(2); throw ScenarioFailure.message("second-release")
					}
					throw ScenarioFailure.message("acquisition")
				}
			], collection: collection)
		let report = try await registry.executeCollection("chat-fixture")
		#expect(order == [2, 1, 0])
		#expect(!context.cleanupConfirmed)
		#expect(report.cleanupProblems.count == 2)
		var emitted = false
		#expect(throws: ScenarioFailure.self) { try collection.confirmCleanup { emitted = true } }
		#expect(!emitted)
		let diagnostics = String(describing: report.cleanupProblems)
		#expect(diagnostics.contains("first-release"))
		#expect(diagnostics.contains("second-release"))
		#expect(diagnostics.contains("session-release"))
	}

	@Test func earlierSuccessCannotConfirmLaterFailure() async throws {
		let collection = ChatCollection()
		let first = ChatCaseContext(), second = ChatCaseContext()
		second.ownCleanup { throw ScenarioFailure.message("replay-close") }
		var emitted = false
		let registry = try ScenarioRegistry([
			ScenarioCollection(
				"multiple-chat-cases", context: { collection }, setup: [],
				cases: [
					ChatModelCases.makeCase("first-chat-case", context: { first }, setup: [], behaviour: []),
					ChatModelCases.makeCase(
						"second-chat-case", context: { second }, setup: [], behaviour: []),
				], cleanup: [ChatCollection.confirmationChain { emitted = true }])
		])
		let report = try await registry.executeCollection(
			"multiple-chat-cases", observer: ScenarioTestingObserver())
		#expect(first.cleanupConfirmed && !second.cleanupConfirmed)
		#expect(collection.contexts.count == 2)
		#expect(!report.cleanupProblems.isEmpty && !emitted)
	}

	@Test func cancellationAwaitsUncancelledCleanup() async throws {
		let context = ChatCaseContext()
		var started = false
		var cleaned = false
		context.ownCleanup {
			#expect(!Task.isCancelled)
			try await Task.sleep(for: .milliseconds(20))
			cleaned = true
		}
		let registry = try registry(
			context,
			behaviour: [
				ChatModelCases.step("wait for cancellation") { _ in
					started = true
					try await Task.sleep(for: .seconds(10))
				}
			])
		let task = Task { try await registry.executeCollection("chat-fixture") }
		while !started { await Task.yield() }
		task.cancel()
		let report = try await task.value
		#expect(cleaned)
		#expect(throws: ScenarioExecutionFailure.self) { try report.requireSuccess() }
	}

	@Test func observedCleanupAssertionSuppressesCollectionConfirmation() async throws {
		let context = ChatCaseContext()
		var emitted = false
		context.ownCleanup { #expect(Bool(false), "chat-cleanup-observed-fixture") }
		let registry = try ScenarioRegistry([
			ScenarioCollection(
				"cleanup-observation", context: ChatCollection.init, setup: [],
				cases: [
					ChatModelCases.makeCase(
						"cleanup-observation-case", context: { context }, setup: [], behaviour: [])
				], cleanup: [ChatCollection.confirmationChain { emitted = true }])
		])
		let outer = IssueHandlingTrait.compactMapIssues { issue in
			if issue.comments.contains(where: { $0.rawValue == "chat-cleanup-observed-fixture" }) {
				return nil
			}
			return issue
		}
		let test = try #require(Test.current)
		var report: ScenarioReport?
		try await outer.provideScope(for: test, testCase: Test.Case.current) { @MainActor in
			report = try await registry.executeCollection(
				"cleanup-observation", observer: ScenarioTestingObserver())
		}
		#expect(!emitted)
		#expect(try #require(report).cleanupProblems.count == 2)
	}

	@Test func observedAssertionSkipsLaterPhasesButAwaitsCleanup() async throws {
		let context = ChatCaseContext()
		var later = false
		var cleaned = false
		context.ownCleanup { cleaned = true }
		let registry = try registry(
			context,
			behaviour: [
				ChatModelCases.step("assert") { _ in #expect(Bool(false), "chat-observed-fixture") },
				ChatModelCases.step("later") { _ in later = true },
			])
		let outer = IssueHandlingTrait.compactMapIssues { issue in
			if issue.comments.contains(where: { $0.rawValue == "chat-observed-fixture" }) { return nil }
			return issue
		}
		let test = try #require(Test.current)
		var report: ScenarioReport?
		try await outer.provideScope(for: test, testCase: Test.Case.current) { @MainActor in
			report = try await registry.executeCollection(
				"chat-fixture", observer: ScenarioTestingObserver())
		}
		let result = try #require(report)
		#expect(result.bodyProblems.count == 1)
		#expect(!later && cleaned)
		#expect(throws: ScenarioExecutionFailure.self) { try result.requireSuccess() }
	}
}
