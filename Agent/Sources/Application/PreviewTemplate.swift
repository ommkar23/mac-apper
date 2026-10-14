// @frontmatter:start
// Provides protected generated-app files, including the preview controller and production entry point.
// @frontmatter:end
import Foundation

extension BaseAppTemplate {
	public static func protectedFiles(appID: String) throws -> [String: String] {
		var files = [
			"Package.swift": manifest,
			"Package.resolved": #"""
			{
			  "pins" : [
			    {
			      "identity" : "swift-syntax",
			      "kind" : "remoteSourceControl",
			      "location" : "https://github.com/swiftlang/swift-syntax.git",
			      "state" : { "revision" : "4799286537280063c85a32f09884cfbca301b1a1", "version" : "602.0.0" }
			    },
			    {
			      "identity" : "swift-testing",
			      "kind" : "remoteSourceControl",
			      "location" : "https://github.com/swiftlang/swift-testing.git",
			      "state" : { "revision" : "48a471ab313e858258ab0b9b0bf2cea55a50cefb", "version" : "6.2.3" }
			    }
			  ],
			  "version" : 3
			}
			"""#,
			"Scaffold.version": version,
			"app-manifest.json": try ContractSource.appManifest(appID: appID),
			"Sources/PreviewContract/PreviewProtocol.swift": try ContractSource.text,
			"Sources/ProductionApp/ProductionApp.swift": #"""
			import Foundation
			import SwiftUI
			import Observation
			import AppModel
			import AppViews
			import DevExtension
			@MainActor @Observable final class ProductionRuntime {
			    let model: ApplicationModel
			    private var service: GeneratedAppXPCService?
			    init() {
			        model = ApplicationModel.production(appID: "\#(appID)")
			        service = try? GeneratedAppXPCService(model: model)
			        service?.start()
			    }
			}
			enum ProductionWindowTitle {
			    static func resolve(bundle: Bundle = .main) -> String {
			        for key in ["CFBundleDisplayName", "CFBundleName"] {
			            if let name = bundle.object(forInfoDictionaryKey: key) as? String,
			               !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
			                return name
			            }
			        }
			        return "Generated App"
			    }
			}
			@main @MainActor struct ProductionApplication: App {
			    @State private var runtime = ProductionRuntime()
			    var body: some Scene {
			        WindowGroup(Text(verbatim: ProductionWindowTitle.resolve())) {
			            ApplicationRoot(model: runtime.model)
			        }
			    }
			}
			"""#,
			"Sources/PreviewApp/PreviewApp.swift": #"""
			import SwiftUI
			import PreviewSupport
			@main struct PreviewApplication: App {
			    @State private var preview = PreviewController()
			    init() { preview.start() }
			    var body: some Scene { WindowGroup("Preview") { preview.root } }
			}
			"""#,
			"Sources/PreviewSupport/PreviewController.swift": #"""
			import SwiftUI
			import AppKit
			import ImageIO
			import UniformTypeIdentifiers
			import AppModel
			import AppViews
			import PreviewContract
			@MainActor @Observable public final class PreviewController {
			    private let model = ApplicationModel()
			    private let width = 640
			    private let height = 480
			    private var resolvedAppearance = "light"
			    private var runID = ""
			    private var buildID = ""
			    private var output: URL?
			    private var ready = false
			    private let channel = FileHandle.standardOutput
			    public init() {}
			    public var root: some View {
			        ApplicationRoot(model: model)
			            .frame(width: CGFloat(width), height: CGFloat(height))
			            .environment(\.colorScheme, resolvedAppearance == "dark" ? .dark : .light)
			    }
			    public func start() {
			        Task { await prepare() }
			    }
			    private func send(_ kind: String, path: String? = nil, message: String? = nil) throws {
			        let record = PreviewRecord(kind: kind, runID: runID, buildID: buildID, path: path,
			            appearance: resolvedAppearance, width: width, height: height, message: message)
			        var data = try JSONEncoder().encode(record)
			        guard data.count <= 8192 else { throw PreviewError.invalidResult }
			        data.append(10); try channel.write(contentsOf: data)
			    }
			    private func prepare() async {
			        do {
			            let args = CommandLine.arguments
			            guard args.count == 7, args[1] == "--run-id", args[3] == "--build-id", args[5] == "--output",
			                  UUID(uuidString: args[2]) != nil else { throw PreviewError.invalidConfiguration }
			            runID = args[2]; buildID = args[4]; output = URL(fileURLWithPath: args[6], isDirectory: true)
			            try Task.checkCancellation()
			            resolvedAppearance = NSApp.effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua ? "dark" : "light"
			            ready = true
			            try send("model_ready")
			            // Dedicated owned stdin, separate from logs and the stdout protocol channel. One render per run.
			            Task.detached { [weak self] in
			                let data = FileHandle.standardInput.availableData
			                guard data == Data("render\n".utf8) else { return }
			                await self?.render()
			            }
			        } catch { try? send("render_failed", message: "Preview preparation rejected: \(error)") }
			    }
			    private func render() {
			        do {
			            guard ready, let output else { throw PreviewError.invalidTransition }
			            ready = false
			            let renderer = ImageRenderer(content: root)
			            renderer.proposedSize = ProposedViewSize(width: CGFloat(width), height: CGFloat(height))
			            renderer.scale = 1
			            guard let image = renderer.cgImage, image.width == width, image.height == height else { throw PreviewError.invalidResult }
			            let bytes = NSMutableData()
			            guard let destination = CGImageDestinationCreateWithData(bytes, UTType.png.identifier as CFString, 1, nil) else { throw PreviewError.invalidResult }
			            CGImageDestinationAddImage(destination, image, nil)
			            guard CGImageDestinationFinalize(destination), bytes.length > 0, bytes.length <= 2_097_152 else { throw PreviewError.invalidResult }
			            try (bytes as Data).write(to: output.appendingPathComponent("render.png"), options: .atomic)
			            try send("render_completed", path: "render.png")
			        } catch { try? send("render_failed", message: "SwiftUI render failed; use supported SwiftUI content or smaller dimensions: \(error)") }
			    }
			}
			"""#,
		]
		for (path, content) in try ContractSource.developmentFiles { files[path] = content }
		return files
	}
}
