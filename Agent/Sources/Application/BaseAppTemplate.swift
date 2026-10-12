// @frontmatter:start
// Provides the versioned Swift package manifest and editable source templates for generated apps.
// @frontmatter:end
import Foundation

/// Versioned, client-owned infrastructure. Extensions are intentionally ordinary Swift sources.
public enum BaseAppTemplate {
	public static let version = "8"
	public static let manifest = #"""
		// swift-tools-version: 6.0
		import PackageDescription
		var targets: [Target] = [
		    .target(name: "AppModel"),
		    .target(name: "PreviewContract"),
		    .testTarget(name: "AppModelTests", dependencies: ["AppModel", .product(name: "Testing", package: "swift-testing")])
		]
		var products: [Product] = [.library(name: "AppModel", targets: ["AppModel"])]
		#if os(macOS)
		targets += [
		    .target(name: "AppViews", dependencies: ["AppModel"]),
		    .target(name: "PreviewSupport", dependencies: ["AppModel", "AppViews", "PreviewContract"]),
		    .target(name: "DevExtension", dependencies: ["AppModel", "AppViews"]),
		    .executableTarget(name: "PreviewApp", dependencies: ["PreviewSupport"]),
		    .executableTarget(name: "ProductionApp", dependencies: ["AppModel", "AppViews", "DevExtension"])
		]
		products += [.executable(name: "PreviewApp", targets: ["PreviewApp"]), .executable(name: "ProductionApp", targets: ["ProductionApp"])]
		#endif
		let package = Package(
		    name: "GeneratedMacApp",
		    platforms: [.macOS(.v14)],
		    products: products,
		    dependencies: [.package(url: "https://github.com/swiftlang/swift-testing.git", exact: "6.2.3")],
		    targets: targets)
		"""#

	public static var extensions: [String: String] {
		var files = [
			"Sources/AppModel/ApplicationModel.swift": #"""
			import Foundation
			import Observation
			import CoreData
			@MainActor @Observable public final class ApplicationModel {
			    public private(set) var state = ApplicationState()
			    @ObservationIgnored private let persistence: ApplicationPersistence?
			    @ObservationIgnored public private(set) var persistenceFailure: (any Error)?
			    @ObservationIgnored private var reduceMotion = false
			    // Compatibility APIs for the protected development service. Starter text is transient UI state.
			    public var title: String { get { state.title } set { setTitle(newValue) } }
			    public var detail: String { get { state.detail } set { setDetail(newValue) } }
			    public var animation: AnimationIntent { get { state.animation } set { state.animation = newValue } }

			    /// No-argument construction is isolated in memory for tests and preview factories, never production.
			    public init(persistence: ApplicationPersistence? = nil) {
			        do {
			            self.persistence = try persistence ?? ApplicationPersistence.inMemory()
			            state.storageAvailable = true
			        } catch {
			            self.persistence = nil
			            persistenceFailure = error
			            state.persistenceError = "Local storage could not be opened. No changes have been saved. \(error.localizedDescription)"
			        }
			    }
			    private init(unavailable error: any Error) {
			        persistence = nil
			        persistenceFailure = error
			        state.persistenceError = "Local storage could not be opened. No changes have been saved. \(error.localizedDescription)"
			    }
			    public static func production(appID: String, home: URL? = nil) -> ApplicationModel {
			        do { return ApplicationModel(persistence: try ApplicationPersistence.production(appID: appID, home: home)) }
			        catch { return ApplicationModel(unavailable: error) }
			    }
			    /// App-specific actions call this, then re-fetch value presentation after success OR rollback.
			    /// Keep contexts and managed objects inside models, never in views or detached tasks.
			    @discardableResult public func persist(_ mutation: (NSManagedObjectContext) throws -> Void) -> Bool {
			        guard let persistence else { return false }
			        guard !persistence.isClosed else {
			            state.storageAvailable = false
			            state.persistenceError = "Local storage is closed. No changes have been saved."
			            state.animation = .transition(trigger: .cancelled, reduceMotion: reduceMotion)
			            return false
			        }
			        do {
			            try mutation(persistence.context)
			            try persistence.context.save()
			            persistenceFailure = nil
			            state.persistenceError = nil
			            state.animation = .transition(trigger: .contentChanged, reduceMotion: reduceMotion)
			            return true
			        } catch {
			            persistence.context.rollback()
			            persistenceFailure = error
			            state.persistenceError = "Changes could not be saved locally. Please try again. \(error.localizedDescription)"
			            state.animation = .transition(trigger: .cancelled, reduceMotion: reduceMotion)
			            return false
			        }
			    }
			    public func setReduceMotion(_ value: Bool) {
			        reduceMotion = value
			        state.animation = .transition(trigger: state.animation.trigger, reduceMotion: value)
			    }
			    public func apply(title: String, detail: String) {
			        guard state.controlsEnabled else { return }
			        state.animation = .transition(trigger: .contentChanged, reduceMotion: reduceMotion)
			        state.title = title; state.detail = detail
			    }
			    public func setTitle(_ value: String) { apply(title: value, detail: detail) }
			    public func setDetail(_ value: String) { apply(title: title, detail: value) }
			    public func reset() { apply(title: "Your app", detail: "Ready to create.") }
			}
			"""#,
			"Sources/AppViews/ApplicationRoot.swift": #"""
			import SwiftUI
			import AppModel
			public struct ApplicationRoot: View {
			    @Bindable var model: ApplicationModel
			    @Environment(\.accessibilityReduceMotion) private var reduceMotion
			    public init(model: ApplicationModel) { self.model = model }
			    private var nativeAnimation: Animation? {
			        let intent = model.state.animation
			        guard let phase = intent.phases.first else { return nil }
			        let value: Animation = phase.curve == .linear ? .linear(duration: phase.duration) : .easeInOut(duration: phase.duration)
			        return value.delay(phase.delay)
			    }
			    public var body: some View {
			        VStack(alignment: .leading, spacing: 20) {
			            Image(systemName: "sparkles").font(.largeTitle).foregroundStyle(.tint)
			            Text(model.state.title).font(.largeTitle.bold())
			            Text(model.state.detail).font(.title3).foregroundStyle(.secondary)
			            TextField(model.state.titleLabel, text: Binding(get: { model.state.title }, set: { model.setTitle($0) }))
			                .disabled(!model.state.controlsEnabled)
			            TextField(model.state.detailLabel, text: Binding(get: { model.state.detail }, set: { model.setDetail($0) }))
			                .disabled(!model.state.controlsEnabled)
			            Button(model.state.resetLabel) { model.reset() }.disabled(!model.state.resetEnabled)
			            Text(model.state.statusMessage).foregroundStyle(.secondary)
			            Spacer()
			        }.padding(32).frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
			            .background(.background)
			            .animation(nativeAnimation, value: model.state.title)
			            .animation(nativeAnimation, value: model.state.detail)
			            .onChange(of: reduceMotion, initial: true) { _, value in model.setReduceMotion(value) }
			    }
			}
			"""#,
			"Tests/AppModelTests/ApplicationTests.swift": #"""
			import Testing
			import AppModel
			@Test @MainActor func normalInitialization() {
			    let model = ApplicationModel()
			    #expect(model.title == "Your app")
			}
			@Test func animationDecision() {
			    let intent = AnimationIntent.transition(trigger: .contentChanged, reduceMotion: false)
			    #expect(intent.phase(at: 0.1)?.curve == .easeInOut)
			    #expect(intent.phase(at: 1) == nil)
			    #expect(AnimationIntent.transition(trigger: .contentChanged, reduceMotion: true).phases.isEmpty)
			}
			"""#,
		]
		files.merge(persistenceFiles) { _, new in new }
		return files
	}
}
