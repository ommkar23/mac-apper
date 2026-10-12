// @frontmatter:start
// Launches the macOS UI, lists presets, or submits a bounded headless Chat request through the client model.
// @frontmatter:end
import AgentMacosClientModel
import AppKit
import Foundation
import SwiftUI

@main @MainActor enum AgentMacosClientMain {
	static func main() {
		guard
			CommandLine.arguments.count > 1
		else {
			AgentMacosClientApp.main()
			return
		}
		if CommandLine.arguments == [CommandLine.arguments[0], "--chat"] {
			guard
				let data = readChatRequest(),
				let request = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any],
				Set(request.keys) == ["message"],
				let message = request["message"] as? String
			else { emit(["error": "invalidRequest"], status: 1) }
			Task {
				let service = AgentServiceXPCAdapter()
				let result = await HeadlessChatCommand.run(
					message: message,
					runtime: AgentXPCRuntime(transport: service),
					store: AgentXPCWorkspaceStore(transport: service))
				guard
					let encoded = try? JSONEncoder().encode(result),
					encoded.count <= 65_536
				else { emit(["error": "encodingFailure"], status: 1) }
				FileHandle.standardOutput.write(encoded + Data([10]))
				exit(result.success ? 0 : 1)
			}
			RunLoop.current.run()
			exit(1)
		}
		guard
			CommandLine.arguments == [CommandLine.arguments[0], "--service-presets"]
		else { emit(["error": "invalidArgument"], status: 1) }
		emit([
			"presets": BuiltInAgentPresets.all.map { ["id": $0.id, "displayName": $0.displayName] }
		])
	}

	private static func readChatRequest() -> Data? {
		var data = Data()
		do {
			while data.count <= 65_536 {
				let chunk =
					try FileHandle.standardInput.read(upToCount: min(4096, 65_537 - data.count)) ?? Data()
				if chunk.isEmpty { return data }
				data.append(chunk)
				if data.contains(10) { return data.count <= 65_536 ? data : nil }
			}
		} catch { return nil }
		return nil
	}

	private static func emit(_ value: [String: Any], status: Int32 = 0) -> Never {
		let data =
			(try? JSONSerialization.data(withJSONObject: value, options: [.sortedKeys]))
			?? Data("{\"error\":\"encodingFailure\"}".utf8)
		FileHandle.standardOutput.write(data + Data([10]))
		exit(status)
	}
}

@MainActor private struct AgentMacosClientApp: App {
	@NSApplicationDelegateAdaptor(TerminationDelegate.self) private var delegate
	var body: some Scene {
		WindowGroup("Mac Apper") {
			WorkspaceView(presentation: delegate.presentation)
		}.defaultSize(width: 1200, height: 800)
	}
}

@MainActor final class TerminationDelegate: NSObject, NSApplicationDelegate {
	let runtime: AgentXPCRuntime
	let workspace: WorkspaceSession
	let presentation: WorkspacePresentation

	override init() {
		let service = AgentServiceXPCAdapter()
		let runtime = AgentXPCRuntime(transport: service)
		self.runtime = runtime
		workspace = WorkspaceSession(
			runtime: runtime,
			workspaceStore: AgentXPCWorkspaceStore(transport: service)
		)
		presentation = WorkspacePresentation(session: workspace, host: AgentMacosHostActions())
		super.init()
	}

	func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
		.terminateNow
	}
}
