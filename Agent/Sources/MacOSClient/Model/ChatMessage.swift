// @frontmatter:start
// Represents a client-owned chat message with a local presentation identifier.
// @frontmatter:end
import Foundation

public struct ChatMessage: Identifiable, Sendable {
	public let id = UUID()
	public let isUser: Bool
	public var text: String

	public init(isUser: Bool, text: String) {
		self.isUser = isUser
		self.text = text
	}
}
