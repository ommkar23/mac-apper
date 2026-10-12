// @frontmatter:start
// Renders safe diagnostics controls for copying metadata and revealing logs.
// @frontmatter:end
import AgentMacosClientModel
import SwiftUI

/// Shared production controls; also rendered directly by the provider-free verifier.
public struct DiagnosticsAccessView: View {
	@Bindable private var presentation: WorkspacePresentation
	public init(presentation: WorkspacePresentation) { self.presentation = presentation }
	public init(model: WorkspaceSession) { self.presentation = WorkspacePresentation(session: model) }
	public var body: some View {
		VStack(alignment: .leading, spacing: 14) {
			Text("Safe diagnostics").font(.headline)
			Text(
				"Metadata only · 3 × 256 KiB · 7-day retention on access.\nNo credentials, prompts, source, images or reasoning."
			).font(.caption)
			HStack(spacing: 20) {
				Button("Copy safe diagnostics", systemImage: "doc.on.doc") {
					presentation.copyDiagnostics()
				}
				Button("Reveal logs", systemImage: "folder") {
					Task { await presentation.revealLogs() }
				}.disabled(presentation.session.diagnosticDirectory == nil)
			}
		}.frame(maxWidth: .infinity, alignment: .leading)
	}
}
