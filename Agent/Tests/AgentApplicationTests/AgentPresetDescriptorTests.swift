// @frontmatter:start
// Tests coding of the legacy fixed-agent XPC descriptor.
// @frontmatter:end
import AgentApplication
import Foundation
import Testing

@Test func fixedAgentDescriptorRoundTrips() throws {
	let descriptor = AgentPresetDescriptor(
		id: "chat", displayName: "Chat", runtimeMode: .conversation)
	let copy = try JSONDecoder().decode(
		AgentPresetDescriptor.self, from: JSONEncoder().encode(descriptor))
	#expect(copy == descriptor)
}
