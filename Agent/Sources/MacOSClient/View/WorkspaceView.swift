// @frontmatter:start
// Renders the workspace sidebar, conversation, composer, activity, and rename controls.
// @frontmatter:end
import AgentMacosClientModel
import SwiftUI

public struct WorkspaceView: View {
	@Bindable var model: WorkspaceSession
	@Bindable var presentation: WorkspacePresentation
	public init(presentation: WorkspacePresentation) {
		self.presentation = presentation
		self.model = presentation.session
	}
	/// Fixture convenience; production supplies its host adapter at the composition root.
	public init(model: WorkspaceSession, showPreview: Bool = false) {
		self.init(presentation: WorkspacePresentation(session: model))
	}

	public var body: some View {
		VStack(spacing: 0) {
			HStack(alignment: .top, spacing: 0) {
				sidebar
				Divider()
				VStack(spacing: 0) {
					header
					if model.messages.isEmpty {
						Spacer()
						VStack(spacing: 22) {
							composer(initial: true)
							Text("Describe your request").font(.title2.weight(.medium))
							Text(presentation.emptyMessage).foregroundStyle(.secondary)
						}.frame(maxWidth: 660).padding(.horizontal, 36)
						Spacer()
						Spacer().frame(height: 60)
					} else {
						conversation
						composer(initial: false).padding(.horizontal, 32).padding(.bottom, 22)
					}
				}.frame(maxWidth: .infinity, maxHeight: .infinity)
			}
			footer
		}
		.background(Color(nsColor: .windowBackgroundColor))
		.frame(minWidth: 900, minHeight: 620)
		.task { await presentation.runRefreshLoop() }
		.sheet(item: $presentation.sheet) { destination in
			switch destination {
			case .activity:
				VStack(alignment: .leading, spacing: 16) {
					Text("Activity").font(.title2.bold())
					ScrollView {
						Text(model.state.liveDetails.joined(separator: "\n")).font(
							.system(.body, design: .monospaced)
						).textSelection(.enabled).frame(maxWidth: .infinity, alignment: .leading)
					}
					DiagnosticsAccessView(presentation: presentation)
					Button("Done") { presentation.dismissDiagnostics() }.keyboardShortcut(.defaultAction)
				}.padding(24).frame(width: 680, height: 480)
			case .rename:
				VStack(alignment: .leading, spacing: 16) {
					Text("Rename App").font(.title2.bold())
					Text("Mac Apper will rebuild, repackage, sign, and register the app with its new name.")
						.foregroundStyle(.secondary)
					TextField("App name", text: $presentation.renameDraft)
						.textFieldStyle(.roundedBorder)
						.onSubmit { Task { await presentation.confirmRename() } }
					if !presentation.renameError.isEmpty {
						Text(presentation.renameError).font(.caption).foregroundStyle(.red)
					}
					HStack {
						Spacer()
						Button("Cancel") { presentation.cancelRename() }.disabled(presentation.renameSubmitting)
						Button(presentation.renameButtonTitle) { Task { await presentation.confirmRename() } }
							.keyboardShortcut(.defaultAction)
							.disabled(!presentation.canRename)
					}
				}.padding(24).frame(width: 440)
					.interactiveDismissDisabled(presentation.renameSubmitting)
			}
		}
	}

	private var header: some View {
		HStack(spacing: 16) {
			VStack(alignment: .leading, spacing: 4) {
				Text(model.chatTitle).font(.headline).lineLimit(1).help(model.chatTitle)
				Text(presentation.workspaceSubtitle)
					.font(.caption).foregroundStyle(.secondary)
			}
			Spacer(minLength: 12)
			if !model.isNewAppPage {
				HStack(spacing: 6) {
					Button {
						Task { await presentation.newChat() }
					} label: {
						Image(systemName: "square.and.pencil").frame(width: 32, height: 30)
					}.help("New Session").accessibilityLabel("New Session").disabled(!model.canNavigate)
					Button {
						Task { await presentation.openCodebaseInZed() }
					} label: {
						Image(systemName: "chevron.left.forwardslash.chevron.right").frame(
							width: 32, height: 30)
					}.help("Open in Zed").accessibilityLabel("Open Codebase in Zed").disabled(
						!presentation.canOpenCodebase)
					Button {
						Task { await presentation.launchCurrentApp() }
					} label: {
						Image(systemName: "play.fill").frame(width: 32, height: 30)
					}.help("Launch App").accessibilityLabel("Launch App").disabled(
						!presentation.canLaunch)
				}
				.buttonStyle(.borderless)
				.padding(5)
				.background(Color.primary.opacity(0.045), in: RoundedRectangle(cornerRadius: 12))
			}
		}.padding(.horizontal, 28).padding(.vertical, 20)
	}

	private var sidebar: some View {
		VStack(alignment: .leading, spacing: 0) {
			ScrollView {
				VStack(alignment: .leading, spacing: 22) {
					ForEach(model.library) { group in
						libraryGroup(group)
					}
					if model.hasOngoingPlan {
						DisclosureGroup("Plan", isExpanded: $presentation.planExpanded) {
							VStack(alignment: .leading, spacing: 12) {
								ForEach(model.state.tasks, id: \.id) { task in
									Label(
										task.title,
										systemImage: task.status == "completed"
											? "checkmark.circle.fill"
											: task.status == "in_progress" ? "circle.dotted" : "circle"
									)
									.font(.caption).foregroundStyle(
										task.status == "completed" ? Color.green : .secondary)
								}
							}.padding(.top, 10)
						}.padding(.horizontal, 8)
					}
				}.padding(.horizontal, 12).padding(.top, 20).padding(.bottom, 16)
			}
			if !model.isNewAppPage {
				Button {
					Task { await presentation.newChat(newApp: true) }
				} label: {
					Label("New App", systemImage: "plus").font(.callout.weight(.semibold))
						.frame(maxWidth: .infinity).padding(.vertical, 12)
						.background(Color.accentColor.opacity(0.13), in: RoundedRectangle(cornerRadius: 12))
				}
				.buttonStyle(.plain).disabled(!model.canNavigate)
				.padding(16)
			}
		}
		.frame(width: 244)
		.frame(maxHeight: .infinity)
		.background(Color.primary.opacity(0.025))
	}

	private func libraryGroup(_ group: WorkspaceGroup) -> some View {
		VStack(alignment: .leading, spacing: 5) {
			HStack(spacing: 5) {
				Button {
					presentation.toggleGroup(group.id)
				} label: {
					Image(
						systemName: presentation.collapsedGroups.contains(group.id)
							? "chevron.right" : "chevron.down"
					)
					.font(.caption2.weight(.semibold)).frame(width: 16, height: 26)
				}.help("Expand or collapse sessions")
				Button {
					Task { await presentation.openGroup(group) }
				} label: {
					Label(group.title, systemImage: group.isChatOnly ? "bubble.left.and.bubble.right" : "app")
						.font(.callout.weight(.semibold)).lineLimit(1).frame(
							maxWidth: .infinity, alignment: .leading)
				}.disabled(!model.canNavigate).help(group.title)
				if let app = group.app {
					Button {
						presentation.beginRename(app)
					} label: {
						Image(systemName: "pencil").font(.caption)
					}
					.disabled(!model.canNavigate).help("Rename \(app.name)")
				}
			}.buttonStyle(.plain)
			if !presentation.collapsedGroups.contains(group.id) {
				if group.sessions.isEmpty {
					Text(group.isChatOnly ? "Chat only · no app tools" : "No saved sessions yet")
						.font(.caption).foregroundStyle(.tertiary).padding(.leading, 29).padding(.vertical, 5)
				}
				ForEach(group.sessions) { session in
					Button {
						Task { await presentation.openSession(session.file, in: group.project) }
					} label: {
						HStack(spacing: 7) {
							Image(systemName: "bubble.left").font(.caption)
							Text(session.title).lineLimit(1)
							Spacer(minLength: 0)
						}
						.font(.callout)
						.padding(.horizontal, 10).padding(.vertical, 9)
						.background(
							presentation.isSelected(session.file)
								? Color.accentColor.opacity(0.14) : .clear, in: RoundedRectangle(cornerRadius: 9)
						)
						.contentShape(Rectangle())
					}
					.buttonStyle(.plain).disabled(!model.canNavigate).padding(.leading, 19)
					.help(session.title)
				}
			}
		}
	}

	private var conversation: some View {
		ScrollViewReader { proxy in
			ScrollView {
				LazyVStack(alignment: .leading, spacing: 24) {
					ForEach(model.messages) { message in
						HStack {
							if message.isUser { Spacer(minLength: 90) }
							VStack(alignment: .leading, spacing: 8) {
								Text(message.isUser ? "You" : "Pi").font(.caption.weight(.semibold))
									.foregroundStyle(.secondary)
								Text(message.text).textSelection(.enabled).fixedSize(
									horizontal: false, vertical: true)
							}
							.padding(18)
							.background(
								message.isUser ? Color.blue.opacity(0.12) : Color.primary.opacity(0.055),
								in: RoundedRectangle(cornerRadius: 18))
							if !message.isUser { Spacer(minLength: 40) }
						}
					}
					if model.busy {
						HStack(spacing: 10) {
							ProgressView().controlSize(.small)
							Text(model.activity).font(.callout).foregroundStyle(.secondary).lineLimit(2)
						}.padding(.vertical, 8)
					}
					Color.clear.frame(height: 1).id("latest")
				}.padding(32).frame(maxWidth: 900)
					.frame(maxWidth: .infinity)
			}
			.onChange(of: presentation.scrollRevision) { _, _ in proxy.scrollTo("latest", anchor: .bottom)
			}
		}
	}

	private func composer(initial: Bool) -> some View {
		VStack(alignment: .leading, spacing: 12) {
			ZStack(alignment: .topLeading) {
				if model.idea.isEmpty {
					Text(presentation.composerPlaceholder)
						.font(.body).foregroundStyle(.secondary).padding(.leading, 5).allowsHitTesting(false)
				}
				TextEditor(text: $model.idea)
					.font(.body).scrollContentBackground(.hidden)
					.frame(height: initial ? 150 : 64)
					.accessibilityLabel(presentation.composerAccessibilityLabel)
			}
			HStack {
				if initial {
					Picker("Agent", selection: $presentation.selectedAgentID) {
						ForEach(model.agentPresets) { agent in
							Text(agent.displayName).tag(agent.id)
						}
					}
					.pickerStyle(.menu)
					.fixedSize()
					.accessibilityLabel("Agent preset")
				}
				Text(presentation.composerCaption)
					.font(.caption).foregroundStyle(.secondary)
				Spacer()
				if model.busy { Button("Stop") { Task { await model.cancel() } }.buttonStyle(.borderless) }
				Button {
					Task { await model.submit() }
				} label: {
					Image(systemName: "arrow.up").font(.headline).frame(width: 26, height: 26)
				}
				.buttonStyle(.borderedProminent).clipShape(Circle())
				.keyboardShortcut(.return, modifiers: .command)
				.disabled(!presentation.canSendMessage)
				.accessibilityLabel("Send message")
			}
		}
		.padding(18)
		.background(
			initial ? Color.blue.opacity(0.07) : Color.green.opacity(0.07),
			in: RoundedRectangle(cornerRadius: 20)
		)
		.overlay(RoundedRectangle(cornerRadius: 20).stroke(Color.primary.opacity(0.12), lineWidth: 1))
	}

	private var footer: some View {
		HStack {
			Text(presentation.footerText).lineLimit(1)
			Spacer()
			Button("Activity", systemImage: "waveform.path") {
				Task { await presentation.showDiagnostics() }
			}.buttonStyle(.plain)
		}.font(.caption).foregroundStyle(.secondary).padding(.horizontal, 24).padding(.vertical, 10)
	}
}
