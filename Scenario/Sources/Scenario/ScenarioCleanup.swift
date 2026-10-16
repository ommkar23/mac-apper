// @frontmatter:start
// Declares ownership-gated cleanup chains and executes independent chains in order.
// @frontmatter:end
import Foundation

public enum CleanupEligibility: Sendable { case run, notAcquired }
public struct CleanupState: Sendable {
	/// A snapshot of completed operations, including earlier chains and inner cases.
	public let report: ScenarioReport
}
@MainActor public struct CleanupChain<Context> {
	public let name: String
	let eligibility: @MainActor (Context, CleanupState) throws -> CleanupEligibility
	let steps: [Step<Context>]
	public init(
		_ name: String,
		eligibility: @escaping @MainActor (Context, CleanupState) throws -> CleanupEligibility = {
			_, _ in .run
		},
		steps: [Step<Context>]
	) {
		self.name = name
		self.eligibility = eligibility
		self.steps = steps
	}
}

/// Cancellation handlers can run on any executor. Relay only the flag, never cancellation to cleanup.
private final class CleanupCancellationRelay: @unchecked Sendable {
	private let lock = NSLock()
	private var requested: Bool
	init(requested: Bool) { self.requested = requested }
	func recordCancellation() {
		lock.lock()
		defer { lock.unlock() }
		requested = true
	}
	var isCancelled: Bool {
		lock.lock()
		defer { lock.unlock() }
		return requested
	}
}

extension ScenarioRecorder {
	func cleanup<Context>(
		_ chains: [CleanupChain<Context>], context: Context?, caseName: String?,
		unavailable: ScenarioSkipReason = .contextUnavailable
	) async {
		let cancellation = CleanupCancellationRelay(requested: cancelled)
		// An unstructured task inherits task locals, but not the caller's cancellation.
		let task = Task { @MainActor in
			for chain in chains {
				guard
					let context
				else {
					for step in chain.steps {
						self.skip(self.identity(caseName, .cleanup, step.name, chain: chain.name), unavailable)
					}
					continue
				}
				var eligible = CleanupEligibility.notAcquired
				let checked = await self.run(
					self.identity(caseName, .cleanup, "eligibility", chain: chain.name),
					failureOrigin: .eligibility
				) {
					eligible = try chain.eligibility(
						context,
						CleanupState(
							report: ScenarioReport(
								steps: self.steps, cancellationRequested: cancellation.isCancelled))
					)
				}
				var blocked: ScenarioSkipReason? =
					checked ? (eligible == .run ? nil : .resourceNotAcquired) : .cleanupPrerequisiteFailed
				for step in chain.steps {
					let identity = self.identity(caseName, .cleanup, step.name, chain: chain.name)
					if let blocked {
						self.skip(identity, blocked)
					} else if !(await self.run(identity, operation: { try await step.execute(context) })) {
						blocked = .cleanupPrerequisiteFailed
					}
				}
			}
		}
		await withTaskCancellationHandler {
			await task.value
		} onCancel: {
			cancellation.recordCancellation()
		}
	}
}
