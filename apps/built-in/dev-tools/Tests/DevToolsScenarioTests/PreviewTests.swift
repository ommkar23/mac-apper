// @frontmatter:start
// Exercises packaged DevTools Preview paths, rendering, failures, scope, cleanup, and optional production Pi read without sessions or live APIs.
// @frontmatter:end
import CryptoKit
import Darwin
import Foundation
import ImageIO
import Scenario
import ScenarioTesting
import Testing

private let previewSource = """
	import SwiftUI
	import AppModel
	private struct ExampleView: View {
	    let model: Model
	    var body: some View { model.count == -3 ? Color.red : Color.blue }
	}
	#if MAC_APPER_PREVIEW
	@MainActor public func apperPreview_Example() -> some View {
	    var model = Model()
	    model.count = -3
	    return ExampleView(model: model)
	}
	#endif
	"""

@MainActor final class PreviewCollection: CollectionContext {}

@MainActor final class PreviewCase: CaseContext {
	typealias Fixture = (id: UUID, url: URL)
	let collection: PreviewCollection
	let lifecycle = DevToolsScenarioLifecycle()
	var projects: DevToolsScenarioProjects { get throws { try #require(lifecycle.projects) } }
	let session = UUID()
	var primary: Fixture?
	var secondary: Fixture?
	var originalManifest: Data?
	var originalSource: Data?
	var metadata: [String: Any]?
	var imageBytes: Data?
	var relativePath: String?
	var reviewPath: String?
	var reviewFiles: [URL] = []
	init(_ collection: PreviewCollection) { self.collection = collection }

	func verifyProductionIdentity() throws {
		let app = try #require(lifecycle.host?.app)
		let package = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
			.deletingLastPathComponent().deletingLastPathComponent()
		let products =
			ProcessInfo.processInfo.environment["DEV_TOOLS_SCENARIO_PRODUCTS"]
			.map { URL(fileURLWithPath: $0) } ?? package.appendingPathComponent(".build/debug")
		let extensionFile = try #require(
			Bundle(
				url: products.appendingPathComponent(
					"DevTools_DevToolsTerminalClient.bundle"))?.url(
					forResource: "Extension", withExtension: "ts"))
		for (original, staged) in [
			(
				products.appendingPathComponent("DevToolsTerminalClient"),
				app.appendingPathComponent("Contents/MacOS/DevToolsTerminalClient")
			),
			(extensionFile, app.appendingPathComponent("Contents/Resources/PiExtension/Extension.ts")),
		] {
			var source = original, destination = staged
			if original.lastPathComponent == "DevToolsTerminalClient" {
				// Signing necessarily changes the signature. Compare exact unsigned executable bytes
				// on owned copies, never alter either current product or signed host.
				let audit = try #require(lifecycle.home).privateDirectory("preview-byte-audit")
				source = audit.appendingPathComponent("original")
				destination = audit.appendingPathComponent("staged")
				try FileManager.default.copyItem(at: original, to: source)
				try FileManager.default.copyItem(at: staged, to: destination)
				for file in [source, destination] {
					let process = Process()
					process.executableURL = URL(fileURLWithPath: "/usr/bin/codesign")
					process.arguments = ["--remove-signature", file.path]
					process.environment = try #require(lifecycle.home).environment
					process.standardOutput = FileHandle.nullDevice
					process.standardError = FileHandle.nullDevice
					try process.run(); process.waitUntilExit()
					try #require(process.terminationStatus == 0)
				}
			}
			let bytes = try Data(contentsOf: source)
			try #require(Data(contentsOf: destination) == bytes)
			print(
				"PREVIEW_RESOURCE_IDENTITY \(staged.path) sha256=\(SHA256.hash(data: bytes).map { String(format: "%02x", $0) }.joined())"
			)
		}
	}
	func removePrimary() throws {
		try lifecycle.stopServiceRetainingFixtures()
		let project = try #require(primary)
		try lifecycle.removeProjectAfterServiceStop(project.url)
		var info = stat()
		try #require(lstat(project.url.path, &info) == -1 && errno == ENOENT)
		print("PREVIEW_PROJECT_REMOVED home-and-host-retained \(project.url.path)")
	}

	func fixture(source: String = previewSource) throws -> Fixture {
		let project = try projects.create()
		let manager = FileManager.default
		for target in ["AppModel", "AppViews"] {
			try manager.createDirectory(
				at: project.url.appendingPathComponent("Sources/\(target)"),
				withIntermediateDirectories: true)
		}
		try """
		// swift-tools-version: 6.0
		import PackageDescription
		let package = Package(name: "PreviewScenario", platforms: [.macOS(.v14)], targets: [
		    .target(name: "AppModel"), .target(name: "AppViews", dependencies: ["AppModel"])
		])
		""".write(
			to: project.url.appendingPathComponent("Package.swift"), atomically: true, encoding: .utf8)
		try
			"#if compiler(<6.4)\n#error(\"Swift 6.4 is required\")\n#endif\npublic struct Model { public var count = 0; public init() {} }"
			.write(
				to: project.url.appendingPathComponent("Sources/AppModel/Model.swift"), atomically: true,
				encoding: .utf8)
		try setSource(source, in: project)
		print(
			"PREVIEW_PROJECT_REGISTERED id=\(project.id.uuidString.lowercased()) session=\(session.uuidString.lowercased()) \(project.url.path)"
		)
		return project
	}
	func setSource(_ source: String, in project: Fixture? = nil) throws {
		let project = try #require(project ?? primary)
		try source.write(
			to: project.url.appendingPathComponent("Sources/AppViews/Example.swift"), atomically: true,
			encoding: .utf8)
	}
	func params(size: (Int, Int)? = nil) -> [String: Any] {
		var fields: [String: Any] = ["viewPath": "Sources/AppViews/Example.swift"]
		if let size { fields["screenSize"] = ["width": size.0, "height": size.1] }
		return fields
	}
	func request(_ fields: [String: Any]? = nil, in project: Fixture? = nil) throws -> [String: Any] {
		let project = try #require(project ?? primary)
		var payload = fields ?? params()
		payload["projectRoot"] = project.url.path
		return try lifecycle.perform(classifyCompletion: PreviewFixtureAudit.completed) { host in
			try host.request("preview", payload: payload, projectID: project.id, sessionID: session)
		}
	}
	func error(_ response: [String: Any], reason: String) throws {
		try #require(response["status"] as? String == "error")
		let summary = try #require(response["summary"] as? String)
		try #require(summary.contains(reason), "\(summary)")
		if ["missing_preview", "ambiguous_preview", "preview_in_production"].contains(reason) {
			try #require(summary.contains("Sources/AppViews/Example.swift"))
			try #require(summary.contains("#if MAC_APPER_PREVIEW"))
			try #require(summary.contains("public func apperPreview_Example() -> some View"))
		}
		try #require(summary.utf8.count <= 4096)
		try #require(
			response["artifact"] == nil && response["width"] == nil && response["height"] == nil)
	}
	func image(_ response: [String: Any], in project: Fixture? = nil, size: (Int, Int)) throws -> Data
	{
		let project = try #require(project ?? primary)
		try #require(
			response["status"] as? String == "rendered", "\(response["summary"] ?? "missing summary")")
		try #require(response["width"] as? Int == size.0 && response["height"] as? Int == size.1)
		let sourcePath = project.url.appendingPathComponent("Sources/AppViews/Example.swift")
		_ = try PreviewFixtureAudit.read(sourcePath)
		print("PREVIEW_SOURCE_VALIDATED nonlinked \(sourcePath.path)")
		let artifact = try #require(response["artifact"] as? [String: Any])
		try #require(artifact["kind"] as? String == "png")
		let path = try #require(artifact["relativePath"] as? String)
		try #require(
			path.range(
				of: #"^\.mac-apper/Artifacts/[0-9a-f-]{36}/render\.png$"#, options: .regularExpression)
				!= nil)
		let url = project.url.appendingPathComponent(path)
		let values = try url.resourceValues(forKeys: [
			.isRegularFileKey, .isSymbolicLinkKey, .fileSizeKey,
		])
		try #require(
			values.isRegularFile == true && values.isSymbolicLink != true
				&& (values.fileSize ?? Int.max) <= 2_097_152)
		let bytes = try PreviewFixtureAudit.read(url)
		try validateImage(bytes, size: size)
		let review = URL(fileURLWithPath: try #require(artifact["reviewPath"] as? String))
		let expected = project.url.deletingLastPathComponent()
			.appendingPathComponent(
				"previews/\(project.id.uuidString.lowercased())/\(session.uuidString.lowercased())")
		try PreviewFixtureAudit.sameDirectory(review.deletingLastPathComponent(), expected)
		try #require(
			review.lastPathComponent.range(of: #"^preview-[0-9]+\.png$"#, options: .regularExpression)
				!= nil)
		try #require(PreviewFixtureAudit.read(review) == bytes)
		reviewFiles.append(review)
		print(
			"PREVIEW_ARCHIVE_VALIDATED bytes=\(bytes.count) width=\(size.0) height=\(size.1) sha256=\(SHA256.hash(data: bytes).map { String(format: "%02x", $0) }.joined()) \(review.path)"
		)
		print("PREVIEW_RETAINED: \(review.path)")
		if let directory = ProcessInfo.processInfo.environment["DEV_TOOLS_PREVIEW_EXPORT_DIR"] {
			let root = URL(fileURLWithPath: directory)
			let values = try root.resourceValues(forKeys: [.isDirectoryKey, .isSymbolicLinkKey])
			try #require(values.isDirectory == true && values.isSymbolicLink != true)
			let requestID = path.split(separator: "/")[2]
			let destination = root.appendingPathComponent(
				"preview-\(project.id.uuidString.lowercased())-\(requestID).png")
			try bytes.write(to: destination, options: .withoutOverwriting)
			print("PREVIEW_EXPORTED: \(destination.path)")
		}
		return bytes
	}
	func validateImage(_ bytes: Data, size: (Int, Int)) throws {
		let source = try #require(CGImageSourceCreateWithData(bytes as CFData, nil))
		try #require(CGImageSourceGetType(source) as String? == "public.png")
		try #require(CGImageSourceGetCount(source) == 1)
		try #require(CGImageSourceGetStatus(source) == .statusComplete)
		let image = try #require(CGImageSourceCreateImageAtIndex(source, 0, nil))
		try #require(image.width == size.0 && image.height == size.1)
		var pixel = [UInt8](repeating: 0, count: 4)
		try pixel.withUnsafeMutableBytes { bytes in
			let context = try #require(
				CGContext(
					data: bytes.baseAddress, width: 1, height: 1, bitsPerComponent: 8, bytesPerRow: 4,
					space: CGColorSpaceCreateDeviceRGB(),
					bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
			context.draw(image, in: CGRect(x: 0, y: 0, width: 1, height: 1))
		}
		try #require(
			pixel[0] > 200 && pixel[2] < 80, "Injected negative state must render red, not default blue")
	}
	func clean(in project: Fixture? = nil) throws {
		let project = try #require(project ?? primary)
		let manager = FileManager.default
		for path in [".mac-apper/PreviewBuild"] {
			let directory = project.url.appendingPathComponent(path)
			if manager.fileExists(atPath: directory.path) {
				let descriptor = try PreviewFixtureAudit.descriptor(directory.path, directory: true)
				Darwin.close(descriptor)
				try #require(try manager.contentsOfDirectory(atPath: directory.path).isEmpty)
			}
		}
		// No surviving compiler or snapshot executable may reference this fixture.
		let process = Process(), output = Pipe()
		process.executableURL = URL(fileURLWithPath: "/bin/ps")
		process.arguments = ["-ww", "-axo", "command="]
		process.environment = try #require(lifecycle.home).environment
		process.standardOutput = output
		process.standardError = FileHandle.nullDevice
		try process.run()
		let text = String(decoding: output.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
		process.waitUntilExit()
		try #require(process.terminationStatus == 0)
		try #require(!text.contains(project.url.path + "/.mac-apper/PreviewBuild/"))
	}
	func noArtifacts(in project: Fixture? = nil) throws {
		let project = try #require(project ?? primary)
		let directory = project.url.appendingPathComponent(".mac-apper/Artifacts")
		if FileManager.default.fileExists(atPath: directory.path) {
			let descriptor = try PreviewFixtureAudit.descriptor(directory.path, directory: true)
			Darwin.close(descriptor)
			try #require(try FileManager.default.contentsOfDirectory(atPath: directory.path).isEmpty)
		}
	}
	func tool(_ fields: [String: Any], expectedRejection: Bool = false) throws -> [String: Any] {
		let envelope = try lifecycle.perform(classifyCompletion: { envelope in
			let completion = try #require(envelope["observation"] as? String)
			try #require(completion == (expectedRejection ? "operationFailed" : "completed"))
		}) { _ in try harness(["params": fields]) }
		print("PREVIEW_OBSERVED \(envelope["evidence"] ?? "missing")")
		return try #require(envelope["result"] as? [String: Any])
	}
	func readImage(_ path: String) throws -> Data {
		let envelope = try harness(["readPath": path])
		let result = try #require(envelope["result"] as? [String: Any])
		let content = try #require(result["content"] as? [[String: Any]])
		let image = try #require(content.first { $0["type"] as? String == "image" })
		try #require(image["mimeType"] as? String == "image/png")
		let encoded = try #require(image["data"] as? String)
		return try #require(Data(base64Encoded: encoded))
	}
	private func harness(_ request: [String: Any]) throws -> [String: Any] {
		let project = try #require(primary), app = try #require(lifecycle.host?.app)
		let home = try #require(lifecycle.home)
		var environment = home.environment
		environment["PATH"] = ProcessInfo.processInfo.environment["PATH"] ?? "/usr/bin:/bin"
		environment["OPENXPC_DEVTOOLSTERMINALCLIENT_CLIENT_PATH"] =
			app.appendingPathComponent("Contents/MacOS/DevToolsTerminalClient").path
		environment["OPENXPC_PROJECT_ROOT"] = project.url.path
		environment["OPENXPC_PROJECT_ID"] = project.id.uuidString.lowercased()
		environment["OPENXPC_SESSION_ID"] = session.uuidString.lowercased()
		if request["readPath"] != nil {
			let module: String = try #require(
				ProcessInfo.processInfo.environment["DEV_TOOLS_SCENARIO_PI_READ_MODULE"])
			environment["DEV_TOOLS_SCENARIO_PI_READ_MODULE"] = module
		}
		let body = try JSONSerialization.data(withJSONObject: request)
		let reply = try XPCClientAdapter().call(
			URL(fileURLWithPath: "/usr/bin/env"), request: body,
			arguments: [
				"-i"
			] + environment.sorted { $0.key < $1.key }.map { "\($0.key)=\($0.value)" } + [
				"node", "--no-warnings", "--experimental-strip-types",
				app.appendingPathComponent("Contents/Resources/PreviewToolHarness.ts").path,
				app.appendingPathComponent("Contents/Resources/PiExtension/Extension.ts").path,
			],
			environment: home.environment, maxResponseBytes: 131_072, timeoutSeconds: 345)
		try #require(reply.status == 0)
		return try #require(JSONSerialization.jsonObject(with: reply.data) as? [String: Any])
	}
}

@MainActor func previewSetup() -> [Step<PreviewCase>] {
	[
		Step("prepare isolated signed host with Preview resources") {
			try $0.lifecycle.setup(includePreviewResources: true)
		},
		Step("verify production client and extension byte identity") {
			try $0.verifyProductionIdentity()
		},
		Step("register and populate primary Preview fixture") { $0.primary = try $0.fixture() },
	]
}

@MainActor func previewCleanup() -> [CleanupChain<PreviewCase>] {
	[
		CleanupChain(
			"gated Preview lifecycle release",
			steps: [
				Step("stop owned service and apply fixture retention gates") {
					try $0.lifecycle.teardown()
				}
			])
	]
}

@MainActor func previewCollection(
	context: @escaping @MainActor () -> PreviewCollection = PreviewCollection.init
) -> ScenarioCollection {
	ScenarioCollection(
		"dev-tools-preview", context: context, setup: [],
		cases: [
			ScenarioCase(
				"preview-render", context: PreviewCase.init, setup: previewSetup(),
				behaviour: [
					Step("capture original manifest and source") { context in
						let project = try #require(context.primary)
						context.originalManifest = try Data(
							contentsOf: project.url.appendingPathComponent("Package.swift"))
						context.originalSource = try Data(
							contentsOf: project.url.appendingPathComponent("Sources/AppViews/Example.swift"))
					},
					Step("render and validate injected red state, dimensions, PNG and archive") { context in
						context.imageBytes = try context.image(
							context.request(context.params(size: (320, 240))), size: (320, 240))
					},
					Step("verify original files and empty render scratch") { context in
						let project = try #require(context.primary)
						try #require(
							try Data(contentsOf: project.url.appendingPathComponent("Package.swift"))
								== context.originalManifest)
						let source = project.url.appendingPathComponent("Sources/AppViews/Example.swift")
						try #require(try Data(contentsOf: source) == context.originalSource)
						try #require(try String(contentsOf: source, encoding: .utf8) == previewSource)
						try context.clean()
					},
					Step("stop service and selectively remove primary project") { context in
						try context.removePrimary()
					},
					Step("verify archived bytes survive project removal") { context in
						let review = try #require(context.reviewFiles.first)
						try #require(PreviewFixtureAudit.read(review) == context.imageBytes)
					},
					Step("confirm all assertions passed") { $0.lifecycle.passed = true },
				], cleanup: previewCleanup()),
			ScenarioCase(
				"preview-size", context: PreviewCase.init, setup: previewSetup(),
				behaviour: [
					Step("use default canvas") { context in
						_ = try context.image(context.request(), size: (640, 480)); try context.clean()
					},
					Step("render custom canvas") { context in
						_ = try context.image(
							context.request(context.params(size: (800, 600))), size: (800, 600));
						try context.clean()
					},
					Step("reject invalid dimensions and excessive area") { context in
						for size in [(0, 240), (320, 2049), (2048, 2048)] {
							try context.error(
								context.request(context.params(size: size)), reason: "invalidScreenSize")
						}
						try context.clean()
					},
					Step("confirm all assertions passed") { $0.lifecycle.passed = true },
				], cleanup: previewCleanup()),
			ScenarioCase(
				"preview-factories", context: PreviewCase.init, setup: previewSetup(),
				behaviour: [
					Step("reject missing and comment-only preview code") { context in
						try context.setSource(
							"import SwiftUI\n// @MainActor public func apperPreview_Decoy() -> some View { Color.red }\n"
						)
						try context.error(context.request(), reason: "missing_preview")
						try context.noArtifacts(); try context.clean()
					},
					Step("reject ambiguous factories") { context in
						try context.setSource(
							previewSource
								+ "\n#if MAC_APPER_PREVIEW\n@MainActor public func apperPreview_Second() -> some View { Color.blue }\n#endif"
						)
						try context.error(context.request(), reason: "ambiguous_preview")
						try context.noArtifacts(); try context.clean()
					},
					Step("reject preview code present in production compilation") { context in
						try context.setSource(
							previewSource.replacingOccurrences(of: "#if MAC_APPER_PREVIEW\n", with: "")
								.replacingOccurrences(of: "#endif", with: ""))
						try context.error(context.request(), reason: "preview_in_production")
						try context.noArtifacts(); try context.clean()
					},
					Step("confirm all assertions passed") { $0.lifecycle.passed = true },
				], cleanup: previewCleanup()),
			ScenarioCase(
				"preview-failure-recovery", context: PreviewCase.init, setup: previewSetup(),
				behaviour: [
					Step("compile error produces bounded diagnostics and cleans up") { context in
						try context.setSource(previewSource + "\nthis is not Swift code")
						try context.error(context.request(), reason: "processFailed")
						try context.noArtifacts(); try context.clean()
					},
					Step("crashing preview leaves no artifact or worker") { context in
						try context.setSource(
							previewSource.replacingOccurrences(
								of: "var model = Model()",
								with: "fatalError(\"scenario render crash\"); var model = Model()"))
						try context.error(context.request(), reason: "processFailed")
						try context.noArtifacts(); try context.clean()
					},
					Step("valid request recovers on the same project and service") { context in
						try context.setSource(previewSource)
						_ = try context.image(
							context.request(context.params(size: (320, 240))), size: (320, 240))
						try context.clean()
					},
					Step("confirm all assertions passed") { $0.lifecycle.passed = true },
				], cleanup: previewCleanup()),
			ScenarioCase(
				"preview-scope", context: PreviewCase.init,
				setup: previewSetup() + [
					Step("register secondary fixture and linked source") { context in
						let project = try #require(context.primary)
						let other = try context.fixture()
						context.secondary = other
						try FileManager.default.createSymbolicLink(
							at: project.url.appendingPathComponent("Sources/AppViews/Linked.swift"),
							withDestinationURL: other.url.appendingPathComponent("Sources/AppViews/Example.swift")
						)
					}
				],
				behaviour: [
					Step("reject traversal") { context in
						let project = try #require(context.primary)
						try context.lifecycle.perform { host in
							try host.expectRejected(
								"preview",
								payload: [
									"projectRoot": project.url.path,
									"viewPath": "Sources/AppViews/../AppModel/Model.swift",
								], error: "operationFailed",
								projectID: project.id, sessionID: context.session)
						}
					},
					Step("reject linked source") { context in
						let project = try #require(context.primary)
						try context.lifecycle.perform { host in
							try host.expectRejected(
								"preview",
								payload: [
									"projectRoot": project.url.path, "viewPath": "Sources/AppViews/Linked.swift",
								], error: "operationFailed",
								projectID: project.id, sessionID: context.session)
						}
					},
					Step("reject foreign root with primary project identity") { context in
						let project = try #require(context.primary)
						let other = try #require(context.secondary)
						try context.lifecycle.perform { host in
							try host.expectRejected(
								"preview",
								payload: [
									"projectRoot": other.url.path, "viewPath": "Sources/AppViews/Example.swift",
								], error: "operationFailed",
								projectID: project.id, sessionID: context.session)
						}
					},
					Step("verify both projects have no artifacts or render workers") { context in
						let other = try #require(context.secondary)
						try context.noArtifacts(); try context.noArtifacts(in: other)
						try context.clean(); try context.clean(in: other)
					},
					Step("confirm all assertions passed") { $0.lifecycle.passed = true },
				], cleanup: previewCleanup()),
			ScenarioCase(
				"preview-path-content", context: PreviewCase.init, setup: previewSetup(),
				behaviour: [
					Step("capture original source") { context in
						let project = try #require(context.primary)
						context.originalSource = try Data(
							contentsOf: project.url.appendingPathComponent("Sources/AppViews/Example.swift"))
					},
					Step("invoke unmodified generated extension and validate text-only metadata") { context in
						let result = try context.tool(context.params(size: (320, 240)))
						try #require(result["isError"] as? Bool != true)
						let content = try #require(result["content"] as? [[String: Any]])
						try #require(content.count == 1 && content[0]["type"] as? String == "text")
						let text = try #require(
							content.first { $0["type"] as? String == "text" }?["text"] as? String)
						context.metadata = try #require(
							JSONSerialization.jsonObject(with: Data(text.utf8)) as? [String: Any])
					},
					Step("validate PNG and archive identity and retain returned paths") { context in
						let metadata = try #require(context.metadata)
						context.imageBytes = try context.image(metadata, size: (320, 240))
						let artifact = try #require(metadata["artifact"] as? [String: Any])
						context.relativePath = try #require(artifact["relativePath"] as? String)
						let review = try #require(artifact["reviewPath"] as? String)
						try #require(review.hasPrefix("/"))
						context.reviewPath = review
					},
					Step("read relative and absolute paths using installed production read") { context in
						let relative = try #require(context.relativePath)
						let review = try #require(context.reviewPath)
						let bytes = try #require(context.imageBytes)
						try #require(try context.readImage(relative) == bytes)
						try #require(try context.readImage(review) == bytes)
					},
					Step("verify original source and empty render scratch") { context in
						let project = try #require(context.primary)
						try #require(
							try Data(
								contentsOf: project.url.appendingPathComponent("Sources/AppViews/Example.swift"))
								== context.originalSource)
						try context.clean()
					},
					Step("missing preview returns typed error diagnostics without an artifact or image") {
						context in
						try context.setSource("import SwiftUI\n")
						let result = try context.tool(context.params())
						let details = try #require(result["details"] as? [String: Any])
						try context.error(
							try #require(details["result"] as? [String: Any]), reason: "missing_preview")
						let content = try #require(result["content"] as? [[String: Any]])
						try #require(!content.contains { $0["type"] as? String == "image" })
						try #require(
							content.contains { ($0["text"] as? String)?.contains("missing_preview") == true })
						try #require(
							content.contains { ($0["text"] as? String)?.contains("Retry preview") == true })
						try #require(
							content.contains {
								($0["text"] as? String)?.contains("#if MAC_APPER_PREVIEW") == true
							})
						try context.clean()
					},
					Step("scope rejection still becomes a failed text-only tool result") { context in
						let result = try context.tool(
							["viewPath": "Sources/AppViews/../AppModel/Model.swift"], expectedRejection: true)
						try #require(result["isError"] as? Bool == true)
						let content = try #require(result["content"] as? [[String: Any]])
						try #require(content.count == 1 && content[0]["type"] as? String == "text")
						try context.clean()
					},
					Step("stop service and selectively remove primary project") { context in
						let review = try #require(context.reviewFiles.first)
						try #require(PreviewFixtureAudit.read(review) == context.imageBytes)
						try context.removePrimary()
					},
					Step("read retained archive through production read after project deletion") { context in
						let review = try #require(context.reviewPath)
						let bytes = try #require(context.imageBytes)
						try #require(try context.readImage(review) == bytes)
					},
					Step("confirm all assertions passed") { $0.lifecycle.passed = true },
				],
				cleanup: previewCleanup()),
		], cleanup: [])
}

@Test @MainActor func devToolsPreviewScenarios() async throws {
	let registry = try ScenarioRegistry([previewCollection()])
	if let selected = ProcessInfo.processInfo.environment["DEV_TOOLS_SCENARIO_CASE"] {
		let report = try await registry.executeCase(selected, observer: ScenarioTestingObserver())
		try report.requireSuccess()
	} else {
		let report = try await registry.executeCollection(
			"dev-tools-preview", observer: ScenarioTestingObserver())
		try report.requireSuccess()
	}
}
