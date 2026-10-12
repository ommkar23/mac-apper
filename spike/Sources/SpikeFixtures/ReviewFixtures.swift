import AppKit
import SwiftUI

/// Separate from the historical ImageRenderer comparison matrix.
public enum ReviewFixture: String, CaseIterable, Sendable {
	case nativeButtons = "native-button-styles"
	case buttonToolbar = "button-toolbar"
	case textInputs = "text-inputs"
	case textEditor = "text-editor"
	case toggles = "toggles"
	case segmentedPicker = "segmented-picker"
	case menuPicker = "menu-picker"
	case sliders = "sliders"
	case progress = "progress-indicators"
	case list = "sidebar-list"
	case table = "project-table"
	case form = "profile-form"
	case groups = "group-boxes"
	case scroll = "scrolling-cards"
	case lazyGrid = "lazy-grid"
	case grid = "alignment-grid"
	case navigation = "navigation-split"
	case tabs = "tab-view"
	case typography
	case shapes = "shapes-gradients"
	case symbols = "symbol-gallery"
	case images = "local-images"
	case dashboard
	case settings

	@MainActor public func content(localImageURL: URL) -> some View {
		VStack(alignment: .leading, spacing: 16) {
			Text(rawValue).font(.title2.bold())
			ReviewBody(fixture: self, localImageURL: localImageURL)
				.frame(maxWidth: .infinity, maxHeight: .infinity)
		}
		.padding(24)
		.frame(width: 720, height: 540)
		.background(Color(nsColor: .windowBackgroundColor))
		.environment(\.colorScheme, .light)
		.environment(\.locale, Locale(identifier: "en_US_POSIX"))
		.transaction {
			$0.disablesAnimations = true; $0.animation = nil
		}
	}
}

private struct ProjectRow: Identifiable {
	let id: Int
	let name: String
	let status: String
	let tasks: String
	static let seeded = [
		Self(id: 1, name: "Atlas", status: "Ready", tasks: "12"),
		Self(id: 2, name: "Beacon", status: "Review", tasks: "8"),
		Self(id: 3, name: "Cedar", status: "Draft", tasks: "5"),
		Self(id: 4, name: "Delta", status: "Ready", tasks: "21"),
	]
}

private struct ReviewBody: View {
	let fixture: ReviewFixture
	let localImageURL: URL
	@State private var name = "Alex Morgan"
	@State private var password = "local-seed"
	@State private var notes =
		"Offline review notes\n\nPrepare the release checklist.\nReview accessibility labels.\nArchive local evidence."
	@State private var enabled = true
	@State private var disabled = false
	@State private var choice = "Weekly"
	@State private var amount = 0.65
	@State private var count = 3
	@State private var selection: Int? = 2

	var body: some View {
		switch fixture {
		case .nativeButtons:
			VStack(spacing: 22) {
				Button("Automatic action") {}.buttonStyle(.automatic)
				Button("Plain action") {}.buttonStyle(.plain)
				Button("Bordered action") {}.buttonStyle(.bordered)
				Button("Borderless action") {}.buttonStyle(.borderless)
				Button("Prominent action") {}.buttonStyle(.borderedProminent)
				Button("Disabled action") {}.disabled(true)
			}
		case .buttonToolbar:
			VStack(spacing: 28) {
				HStack {
					Button("New", systemImage: "plus") {}
					Button("Share", systemImage: "square.and.arrow.up") {}
					Menu("More") {
						Button("Archive") {}; Button("Duplicate") {}
					}
				}.controlSize(.large)
				Divider()
				HStack {
					Button("Cancel") {}; Button("Save changes") {}.buttonStyle(.borderedProminent)
				}
				Label("All changes saved locally", systemImage: "checkmark.circle").foregroundStyle(
					.secondary)
			}
		case .textInputs:
			VStack(alignment: .leading, spacing: 20) {
				TextField("Display name", text: $name).textFieldStyle(.roundedBorder)
				SecureField("Password", text: $password).textFieldStyle(.roundedBorder)
				TextField("Search projects", text: .constant("Atlas")).textFieldStyle(.plain)
				Text("Seeded values; password intentionally masked").font(.caption)
			}
		case .textEditor:
			VStack(alignment: .leading) {
				Text("Release notebook").font(.headline)
				TextEditor(text: $notes).font(.body).border(.gray.opacity(0.4))
				Text("4 checklist lines • Local draft").font(.caption).foregroundStyle(.secondary)
			}
		case .toggles:
			VStack(alignment: .leading, spacing: 24) {
				Toggle("Notifications", isOn: $enabled).toggleStyle(.switch)
				Toggle("Launch at login", isOn: $disabled).toggleStyle(.switch)
				Toggle("Include archived projects", isOn: $enabled).toggleStyle(.checkbox)
				Toggle("Unavailable option", isOn: $disabled).disabled(true)
			}
		case .segmentedPicker:
			VStack(spacing: 28) {
				Picker("Schedule", selection: $choice) { choices }.pickerStyle(.segmented)
				Text("Weekly summary selected").font(.title3)
			}
		case .menuPicker:
			VStack(alignment: .leading, spacing: 28) {
				Picker("Summary frequency", selection: $choice) { choices }.pickerStyle(.menu)
				Picker("Radio frequency", selection: $choice) { choices }.pickerStyle(.radioGroup)
				Stepper("Copies: \(count)", value: $count, in: 1...10)
			}
		case .sliders:
			VStack(alignment: .leading, spacing: 24) {
				Text("Volume: 65%").font(.headline)
				Slider(value: $amount, in: 0...1) { Text("Volume") }
				Slider(value: .constant(0.3), in: 0...1, step: 0.1) { Text("Discrete level") }
				Slider(value: .constant(0.8)).disabled(true)
			}
		case .progress:
			VStack(spacing: 28) {
				ProgressView("Indexing local files", value: 0.65)
				ProgressView(value: 0.35).progressViewStyle(.linear)
				ProgressView(value: 0.75).progressViewStyle(.circular)
				Text("Determinate values only; no animation or remote work").font(.caption)
			}
		case .list:
			List(selection: $selection) {
				Section("Workspace") {
					ForEach(ProjectRow.seeded) { row in Label(row.name, systemImage: "folder").tag(row.id) }
				}
				Section("Library") {
					Label("Archive", systemImage: "archivebox"); Label("Recent", systemImage: "clock")
				}
			}.listStyle(.sidebar)
		case .table:
			Table(ProjectRow.seeded) {
				TableColumn("Project", value: \.name)
				TableColumn("Status", value: \.status)
				TableColumn("Tasks", value: \.tasks)
			}
		case .form:
			Form {
				Section("Profile") {
					TextField("Name", text: $name);
					TextField("Email", text: .constant("alex@example.invalid"))
				}
				Section("Preferences") {
					Toggle("Enable summaries", isOn: $enabled);
					Picker("Frequency", selection: $choice) { choices }
				}
			}.formStyle(.grouped)
		case .groups:
			VStack(spacing: 20) {
				GroupBox("Storage") {
					LabeledContent("Local documents", value: "128 MB"); LabeledContent("Projects", value: "4")
				}.frame(maxWidth: .infinity)
				GroupBox {
					Label("Everything is available offline", systemImage: "externaldrive.badge.checkmark")
						.padding()
				} label: {
					Label("Backup", systemImage: "archivebox")
				}
			}
		case .scroll:
			ScrollView {
				VStack(spacing: 16) {
					ForEach(1...8, id: \.self) { index in
						HStack {
							Image(systemName: "doc.text");
							VStack(alignment: .leading) {
								Text("Local note \(index)").bold(); Text("Deterministic card content")
							}; Spacer()
						}
						.padding(20).background(.blue.opacity(0.08), in: RoundedRectangle(cornerRadius: 12))
					}
				}
			}
		case .lazyGrid:
			ScrollView {
				LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 3), spacing: 16) {
					ForEach(1...12, id: \.self) { index in
						VStack {
							Image(systemName: "folder.fill").font(.largeTitle); Text("Collection \(index)")
						}
						.frame(maxWidth: .infinity).padding(18).background(
							.teal.opacity(0.12), in: RoundedRectangle(cornerRadius: 10))
					}
				}
			}
		case .grid:
			Grid(alignment: .leading, horizontalSpacing: 40, verticalSpacing: 24) {
				GridRow {
					Text("Metric").bold(); Text("Current").bold(); Text("Target").bold()
				}
				Divider()
				GridRow {
					Text("Projects"); Text("4"); Text("6")
				}
				GridRow {
					Text("Completed tasks"); Text("32"); Text("40")
				}
				GridRow {
					Text("Review coverage"); Text("65%"); Text("100%")
				}
			}
		case .navigation:
			NavigationSplitView {
				List {
					Label("Overview", systemImage: "house"); Label("Projects", systemImage: "folder");
					Label("Settings", systemImage: "gear")
				}
				.navigationSplitViewColumnWidth(180)
			} detail: {
				VStack(spacing: 20) {
					Image(systemName: "folder.badge.gearshape").font(.system(size: 48));
					Text("Project overview").font(.title); Text("Four local projects ready for review")
				}
			}
		case .tabs:
			TabView(selection: .constant(0)) {
				VStack(spacing: 24) {
					Label("Local library", systemImage: "books.vertical").font(.largeTitle);
					Text("12 saved documents"); Button("Open library") {}
				}.tabItem { Label("Library", systemImage: "books.vertical") }.tag(0)
				Text("Activity log").tabItem { Label("Activity", systemImage: "clock") }.tag(1)
				Text("Preferences").tabItem { Label("Settings", systemImage: "gear") }.tag(2)
			}
		case .typography:
			VStack(alignment: .leading, spacing: 18) {
				Text("A local-first workspace").font(.largeTitle.bold())
				Text("Readable hierarchy").font(.title2)
				Text(
					"SwiftUI body text wraps naturally across multiple lines. This fixture checks spacing, weights and secondary text without remote fonts."
				).font(.body)
				Text("Secondary annotation").foregroundStyle(.secondary)
				Text("let count = 42").font(.system(.body, design: .monospaced))
				Text("Caption • 2026-01-15").font(.caption)
			}
		case .shapes:
			VStack(spacing: 24) {
				RoundedRectangle(cornerRadius: 20).fill(
					LinearGradient(colors: [.blue, .purple], startPoint: .leading, endPoint: .trailing)
				).frame(height: 120)
				HStack(spacing: 24) {
					Circle().fill(
						RadialGradient(
							colors: [.yellow, .orange], center: .center, startRadius: 0, endRadius: 80));
					Capsule().stroke(.teal, lineWidth: 6); RoundedRectangle(cornerRadius: 16).fill(.mint)
				}.frame(height: 120)
				Text("Linear and radial gradients • vector shapes")
			}
		case .symbols:
			LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 3), spacing: 28) {
				ForEach(
					[
						"house.fill", "folder.fill", "star.fill", "heart.fill", "bell.fill", "gearshape.fill",
						"cloud.fill", "leaf.fill", "number.square.fill",
					], id: \.self
				) { symbol in
					VStack {
						Image(systemName: symbol).font(.system(size: 38)).symbolRenderingMode(.multicolor);
						Text(symbol).font(.caption)
					}
				}
			}
		case .images:
			VStack(spacing: 24) {
				HStack(spacing: 40) {
					raster(Fixture.bundledImageURL); raster(localImageURL)
				}
				Text("Bundled PNG / local-file PNG").font(.headline)
				Label("Deterministic checker pixels, not asset-catalog lookup", systemImage: "photo")
			}
		case .dashboard:
			VStack(alignment: .leading, spacing: 20) {
				HStack {
					Text("Workspace overview").font(.title); Spacer();
					Button("New project", systemImage: "plus") {}
				}
				HStack {
					metric("Projects", "4"); metric("Tasks", "32"); metric("Ready", "75%")
				}
				GroupBox("Release readiness") {
					ProgressView(value: 0.75); Label("3 of 4 projects ready", systemImage: "checkmark.circle")
				}
				ForEach(ProjectRow.seeded) { row in
					HStack {
						Label(row.name, systemImage: "folder"); Spacer();
						Text(row.status).foregroundStyle(.secondary)
					}; Divider()
				}
			}
		case .settings:
			VStack(alignment: .leading, spacing: 20) {
				GroupBox("Account") {
					TextField("Name", text: $name).textFieldStyle(.roundedBorder);
					LabeledContent("Storage", value: "Local only")
				}
				GroupBox("Notifications") {
					Toggle("Weekly summary", isOn: $enabled);
					Picker("Frequency", selection: $choice) { choices }.pickerStyle(.segmented)
				}
				GroupBox("Display") {
					Slider(value: $amount) { Text("Text scale") }; Toggle("Compact rows", isOn: $disabled)
				}
				HStack {
					Spacer(); Button("Restore defaults") {};
					Button("Apply") {}.buttonStyle(.borderedProminent)
				}
			}
		}
	}

	private var choices: some View {
		ForEach(["Daily", "Weekly", "Monthly"], id: \.self) { Text($0).tag($0) }
	}
	private func raster(_ url: URL) -> some View {
		Image(nsImage: NSImage(contentsOf: url)!).resizable().interpolation(.none).frame(
			width: 160, height: 160)
	}
	private func metric(_ title: String, _ value: String) -> some View {
		VStack(alignment: .leading) {
			Text(title).font(.caption); Text(value).font(.title.bold())
		}
		.frame(maxWidth: .infinity, alignment: .leading).padding().background(
			.blue.opacity(0.08), in: RoundedRectangle(cornerRadius: 12))
	}
}
