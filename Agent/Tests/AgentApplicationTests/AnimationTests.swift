// @frontmatter:start
// Tests portable animation decisions, reduced motion, and codable round trips.
// @frontmatter:end
import Foundation
import Testing

@testable import AgentApplication

@Test func animationDecisionsArePortableAndDeterministic() throws {
	let intent = AnimationIntent.transition(trigger: .contentChanged, reduceMotion: false)
	#expect(intent.state == .transitioning)
	#expect(intent.phases.map(\.name) == ["settle"])
	#expect(intent.phases[0].duration == 0.25)
	#expect(intent.phases[0].curve == .easeInOut)
	#expect(intent.phases[0].delay == 0)
	#expect(intent.phase(at: 0.1)?.name == "settle")
	#expect(intent.phase(at: 0.3) == nil)
	let reduced = AnimationIntent.transition(trigger: .contentChanged, reduceMotion: true)
	#expect(reduced.state == .settled)
	#expect(reduced.phases.isEmpty)
	#expect(
		try JSONDecoder().decode(AnimationIntent.self, from: JSONEncoder().encode(intent)) == intent)
}
