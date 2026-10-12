// @frontmatter:start
// Computes portable animation phases and reduced-motion behavior.
// @frontmatter:end
import Foundation

/// Portable animation decisions. Views map these values; no platform framework or wall clock here.
public struct AnimationIntent: Codable, Equatable, Sendable {
	public enum Trigger: String, Codable, Sendable { case contentChanged, cancelled }
	public enum State: String, Codable, Sendable { case transitioning, settled }
	public enum Curve: String, Codable, Sendable { case linear, easeInOut }
	public struct Phase: Codable, Equatable, Sendable {
		public let name: String
		public let duration: Double
		public let delay: Double
		public let curve: Curve
	}
	public let trigger: Trigger
	public let state: State
	public let phases: [Phase]
	public static func transition(trigger: Trigger, reduceMotion: Bool) -> Self {
		let animate = !reduceMotion && trigger == .contentChanged
		return Self(
			trigger: trigger, state: animate ? .transitioning : .settled,
			phases: animate ? [Phase(name: "settle", duration: 0.25, delay: 0, curve: .easeInOut)] : [])
	}
	public func phase(at elapsed: Double) -> Phase? {
		guard
			elapsed.isFinite,
			elapsed >= 0
		else { return nil }
		var start = 0.0
		for phase in phases {
			start += phase.delay
			if elapsed >= start && elapsed < start + phase.duration { return phase }
			start += phase.duration
		}
		return nil
	}
}
