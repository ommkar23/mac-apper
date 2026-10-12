// @frontmatter:start
// Creates five scoped controllers with shared project resolution and operation serialization.
// @frontmatter:end
import Foundation

private enum DevToolsOperationFailure: Error { case busy }

actor DevToolsOperationGate {
	private var busy = false

	func run<Value: Sendable>(_ operation: @Sendable () async throws -> Value) async throws -> Value {
		guard
			!busy
		else { throw DevToolsOperationFailure.busy }
		busy = true
		defer { busy = false }
		return try await operation()
	}
}

struct ControllerFactory: Sendable {
	let build: BuildController
	let test: TestController
	let run: RunController
	let preview: PreviewController
	let plan: PlanController

	init(
		projectsRoot: URL,
		xcrunURL: URL = URL(fileURLWithPath: "/usr/bin/xcrun"),
		outputLimitBytes: Int = 65_536,
		environment: [String: String] = ProcessInfo.processInfo.environment
	) {
		let projects = ProjectResolver(projectsRoot: projectsRoot)
		let gate = DevToolsOperationGate()
		build = BuildController(
			projects: projects, gate: gate, xcrunURL: xcrunURL,
			outputLimitBytes: outputLimitBytes, environment: environment)
		test = TestController(
			projects: projects, gate: gate, xcrunURL: xcrunURL,
			outputLimitBytes: outputLimitBytes, environment: environment)
		run = RunController(projects: projects, gate: gate, build: build, environment: environment)
		preview = PreviewController(
			projects: projects, gate: gate, xcrunURL: xcrunURL, environment: environment)
		plan = PlanController(projects: projects, gate: gate)
	}

	func controllers() -> OpenXPCGeneratedService.Controllers {
		.init(build: build, test: test, run: run, preview: preview, plan: plan)
	}
}
