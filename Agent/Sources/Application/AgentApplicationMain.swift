// @frontmatter:start
// Starts the Agent XPC service and reports startup failure to standard error.
// @frontmatter:end
import Foundation

@main @MainActor enum AgentApplicationMain {
	static func main() {
		do {
			try AgentXPCServiceMain.run()
		} catch {
			FileHandle.standardError.write(Data("AgentXPCService: \(error)\n".utf8))
			Foundation.exit(1)
		}
	}
}
