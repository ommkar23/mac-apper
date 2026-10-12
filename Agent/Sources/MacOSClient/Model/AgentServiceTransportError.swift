// @frontmatter:start
// Reports malformed typed Agent transport requests and responses at the native client boundary.
// @frontmatter:end
public enum AgentServiceTransportError: Error, Sendable, Equatable {
	case invalidRequest
	case invalidResponse
}
