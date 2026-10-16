// @frontmatter:start
// Checks Preview's actual declarative phase inventory and offline observation and retention contracts.
// @frontmatter:end
import Foundation
import Scenario
import ScenarioTesting
@_spi(Experimental) import Testing

@MainActor private final class PreviewObservationReport {
	var report: ScenarioReport?
}

@Suite @MainActor struct PreviewContractTests {
	@Test func actualInventoryAndUnknownSelectionsAcquireNothing() async throws {
		var acquisitions = 0
		let registry = try ScenarioRegistry([
			previewCollection(context: {
				acquisitions += 1; return PreviewCollection()
			})
		])
		#expect(registry.collectionNames == ["dev-tools-preview"])
		#expect(
			registry.caseNames == [
				"preview-render", "preview-size", "preview-factories", "preview-failure-recovery",
				"preview-scope", "preview-path-content",
			])
		#expect(acquisitions == 0)
		do {
			_ = try await registry.executeCase("unknown-preview", observer: ScenarioTestingObserver())
			Issue.record("unknown selection was accepted")
		} catch let error as ScenarioFailure {
			#expect(error.description == "unknown case: unknown-preview")
		}
		do {
			_ = try await registry.executeCollection(
				"unknown-preview", observer: ScenarioTestingObserver())
			Issue.record("unknown collection was accepted")
		} catch let error as ScenarioFailure {
			#expect(error.description == "unknown collection: unknown-preview")
		}
		#expect(acquisitions == 0)
		let collection = PreviewCollection()
		let first = PreviewCase(collection), second = PreviewCase(collection)
		#expect(first.lifecycle !== second.lifecycle)
		for context in [first, second] {
			#expect(context.lifecycle.home == nil)
			#expect(context.lifecycle.host == nil)
			#expect(context.lifecycle.projects == nil)
			#expect(context.primary == nil && context.secondary == nil)
		}
	}

	@Test func expectedTypedRenderingErrorsAreSuccessfulAssertions() async throws {
		let context = PreviewCase(PreviewCollection())
		let registry = try ScenarioRegistry([
			ScenarioCollection(
				"offline-preview-errors", context: PreviewCollection.init, setup: [],
				cases: [
					ScenarioCase(
						"offline-preview-errors", context: { _ in context }, setup: [],
						behaviour: [
							Step("assert expected typed rendering error and confirmed request completion") {
								context in
								let state = DevToolsScenarioLifecycle.RequestState()
								let result = try state.perform(
									classifyCompletion: PreviewFixtureAudit.completed, capture: {}
								) { ["status": "error", "summary": "processFailed"] as [String: Any] }
								try context.error(result, reason: "processFailed")
								try state.stop {}
								try #require(state.serviceStopped)
							},
							Step("confirm all assertions passed") { $0.lifecycle.passed = true },
						], cleanup: previewCleanup())
				], cleanup: [])
		])
		let report = try await registry.executeCase(
			"offline-preview-errors", observer: ScenarioTestingObserver())
		try report.requireSuccess()
		#expect(context.lifecycle.passed && context.lifecycle.serviceStopped)
	}

	@Test func observedFailureSkipsSuccessAndRetainsStoppedFixtures() async throws {
		let context = PreviewCase(PreviewCollection())
		let registry = try ScenarioRegistry([
			ScenarioCollection(
				"offline-preview-observation", context: PreviewCollection.init, setup: [],
				cases: [
					ScenarioCase(
						"offline-preview-observation", context: { _ in context },
						setup: [
							Step("acquire private fixtures without a signed host") { context in
								#expect(throws: (any Error).self) {
									try context.lifecycle.setup(beforeHost: {
										throw ScenarioFailure.message("offline")
									})
								}
								context.primary = try context.projects.create()
							}
						],
						behaviour: [
							Step("observe an intentional nonthrowing assertion failure") { _ in
								let actual = "error"
								#expect(actual == "rendered", "intentional Preview observation fixture")
							},
							Step("confirm all assertions passed") { $0.lifecycle.passed = true },
						], cleanup: previewCleanup())
				], cleanup: [])
		])
		let test = try #require(Test.current)
		let outer = IssueHandlingTrait.compactMapIssues { issue in
			issue.comments.contains { $0.rawValue == "intentional Preview observation fixture" }
				? nil : issue
		}
		let result = PreviewObservationReport()
		// Suppress only this tagged fixture outside the inner assertion observer.
		try await outer.provideScope(for: test, testCase: Test.Case.current) { @MainActor in
			result.report = try await registry.executeCase(
				"offline-preview-observation", observer: ScenarioTestingObserver())
		}
		let report = try #require(result.report)
		#expect(throws: ScenarioExecutionFailure.self) { try report.requireSuccess() }
		#expect(report.bodyProblems.contains { $0.origin == .assertion })
		#expect(report.cleanupProblems.isEmpty)
		#expect(
			report.steps.contains {
				$0.identity.step == "confirm all assertions passed"
					&& $0.skipReason == .priorBehaviourFailure
			})
		#expect(!context.lifecycle.passed && context.lifecycle.serviceStopped)
		let home = try #require(context.lifecycle.home)
		let project = try #require(context.primary)
		#expect(FileManager.default.fileExists(atPath: home.directory.path))
		#expect(FileManager.default.fileExists(atPath: project.url.path))
		// Only after checking stopped-fixture retention, release this regression's own fixture.
		context.lifecycle.passed = true
		try context.lifecycle.teardown()
		#expect(!FileManager.default.fileExists(atPath: home.directory.path))
	}

	@Test func partialSetupStillUsesProductionGatedCleanup() async throws {
		let context = PreviewCase(PreviewCollection())
		let registry = try ScenarioRegistry([
			ScenarioCollection(
				"offline-preview-partial", context: PreviewCollection.init, setup: [],
				cases: [
					ScenarioCase(
						"offline-preview-partial", context: { _ in context },
						setup: [
							Step("fail after private-home acquisition but before host startup") {
								try $0.lifecycle.setup(beforeHost: {
									throw ScenarioFailure.message("offline partial")
								})
							}
						],
						behaviour: [Step("confirm all assertions passed") { $0.lifecycle.passed = true }],
						cleanup: previewCleanup())
				], cleanup: [])
		])
		let report = try await registry.executeCase(
			"offline-preview-partial", observer: ScenarioTestingObserver())
		#expect(throws: ScenarioExecutionFailure.self) { try report.requireSuccess() }
		#expect(!report.bodyProblems.isEmpty && report.cleanupProblems.isEmpty)
		#expect(!context.lifecycle.passed && context.lifecycle.serviceStopped)
		#expect(
			report.steps.contains {
				$0.identity.step == "confirm all assertions passed" && $0.skipReason == .priorSetupFailure
			})
		let home = try #require(context.lifecycle.home)
		#expect(FileManager.default.fileExists(atPath: home.directory.path))
		context.lifecycle.passed = true
		try context.lifecycle.teardown()
		#expect(!FileManager.default.fileExists(atPath: home.directory.path))
	}

	@Test func actualDeclarationsUseNamedObservedPhases() throws {
		let source = try String(
			contentsOf: URL(fileURLWithPath: #filePath).deletingLastPathComponent()
				.appendingPathComponent("PreviewTests.swift"), encoding: .utf8)
		#expect(!source.contains("steps: [\n\t\t\t\t\tStep"))
		#expect(!source.contains("teardown:"))
		#expect(!source.contains("registry.runCase"))
		#expect(!source.contains("registry.runCollection"))
		#expect(source.contains("ScenarioTestingObserver()"))
		#expect(source.components(separatedBy: "behaviour: [").count - 1 == 6)
		#expect(source.components(separatedBy: "confirm all assertions passed").count - 1 == 6)
		#expect(source.contains("setup: [],"))
		#expect(source.contains("try report.requireSuccess()"))
		let declarations = source.components(separatedBy: "ScenarioCase(").dropFirst()
		try #require(declarations.count == 6)
		for declaration in declarations {
			#expect(declaration.contains("setup: previewSetup()"))
			#expect(declaration.contains("behaviour: ["))
			#expect(declaration.contains("cleanup: previewCleanup()"))
			let behaviour = try #require(declaration.components(separatedBy: "behaviour: [").last)
			let steps = behaviour.components(separatedBy: "Step(").dropFirst()
			#expect(steps.last?.hasPrefix("\"confirm all assertions passed\"") == true)
		}
		for boundary in [
			"prepare isolated signed host with Preview resources",
			"verify production client and extension byte identity",
			"register and populate primary Preview fixture",
			"capture original manifest and source",
			"verify archived bytes survive project removal",
			"register secondary fixture and linked source",
			"reject traversal", "reject linked source",
			"reject foreign root with primary project identity",
			"invoke unmodified generated extension and validate text-only metadata",
			"validate PNG and archive identity and retain returned paths",
			"read relative and absolute paths using installed production read",
			"verify original source and empty render scratch",
			"missing preview returns typed error diagnostics without an artifact or image",
			"scope rejection still becomes a failed text-only tool result",
			"read retained archive through production read after project deletion",
		] {
			#expect(source.contains("Step(\"\(boundary)\""))
		}
	}
}
