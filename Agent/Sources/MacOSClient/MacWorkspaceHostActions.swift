// @frontmatter:start
// Performs macOS application launching, Zed opening, clipboard, and log reveal actions.
// @frontmatter:end
import AgentMacosClientModel
import AppKit

@MainActor public final class AgentMacosHostActions: WorkspaceHostActions {
	public init() {}
	public func launchApplication(at url: URL) async throws {
		guard
			url.isFileURL,
			url.pathExtension == "app"
		else { throw HostActionError.invalidPath }
		try await withCheckedThrowingContinuation {
			(continuation: CheckedContinuation<Void, any Error>) in
			NSWorkspace.shared.openApplication(at: url, configuration: .init()) { @Sendable _, error in
				if let error { continuation.resume(throwing: error) } else { continuation.resume() }
			}
		}
	}
	public func openCodebaseInZed(at url: URL) async throws {
		guard
			url.isFileURL
		else { throw HostActionError.invalidPath }
		guard
			let zed = NSWorkspace.shared.urlForApplication(withBundleIdentifier: "dev.zed.Zed")
		else { throw HostActionError.zedUnavailable }
		try await withCheckedThrowingContinuation {
			(continuation: CheckedContinuation<Void, any Error>) in
			NSWorkspace.shared.open(
				[url], withApplicationAt: zed, configuration: .init()
			) { @Sendable _, error in
				if let error { continuation.resume(throwing: error) } else { continuation.resume() }
			}
		}
	}
	public func copyDiagnostics(_ text: String) throws {
		NSPasteboard.general.clearContents()
		guard
			NSPasteboard.general.setString(text, forType: .string)
		else { throw HostActionError.rejected }
	}
	public func revealLogs(at url: URL) throws {
		guard
			url.isFileURL
		else { throw HostActionError.invalidPath }
		guard
			NSWorkspace.shared.open(url)
		else { throw HostActionError.rejected }
	}
	private enum HostActionError: LocalizedError {
		case invalidPath, rejected, zedUnavailable
		var errorDescription: String? {
			switch self {
			case .invalidPath: return "The project path is invalid."
			case .rejected: return "macOS rejected the request."
			case .zedUnavailable: return "Zed is not installed."
			}
		}
	}
}
