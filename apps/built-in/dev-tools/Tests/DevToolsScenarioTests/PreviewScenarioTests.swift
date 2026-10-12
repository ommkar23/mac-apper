// @frontmatter:start
// Exercises packaged DevTools Preview paths, rendering, failures, scope, cleanup, and optional production Pi read without sessions or live APIs.
// @frontmatter:end
import Darwin
import Foundation
import ImageIO
import Scenario
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

@MainActor private final class PreviewCollection: CollectionContext {
	let host: PackagedXPCHost
	var serviceWasReaped = false
	init() throws { host = try DevToolsScenarioInputs.host(includePreviewResources: true) }

	func reapService() throws {
		let app = try #require(host.app)
		let binary = app.appendingPathComponent(
			"Contents/XPCServices/DevToolsApplication.xpc/Contents/MacOS/DevToolsApplication")
		let canonical = try #require(realpath(binary.path, nil))
		defer { free(canonical) }
		let expected = String(cString: canonical)
		var pids = [Int32](repeating: 0, count: 16_384)
		let count = pids.withUnsafeMutableBytes { proc_listallpids($0.baseAddress, Int32($0.count)) }
		try #require(count > 0 && count < pids.count, "Process inventory unavailable; retain host")
		var identities: [OwnedProcessIdentity] = []
		for pid in pids.prefix(Int(count)) where pid > 1 {
			var path = [UInt8](repeating: 0, count: 4096)
			let length = path.withUnsafeMutableBytes {
				proc_pidpath(pid, $0.baseAddress, UInt32($0.count))
			}
			guard
				length > 0,
				String(decoding: path.prefix { $0 != 0 }, as: UTF8.self) == expected
			else { continue }
			let identity = try OwnedProcessIdentity.capture(pid)
			try #require(identity.path == expected)
			identities.append(identity)
		}
		try #require(identities.count <= 1)
		try #require(!identities.isEmpty || serviceWasReaped, "Service identity missing; retain host")
		for identity in identities {
			try identity.reap()
			print(
				"PREVIEW_SERVICE_CLEANUP: pid=\(identity.pid) start=\(identity.start) path=\(expected) reaped"
			)
		}
		serviceWasReaped = true
	}
}

@MainActor private final class PreviewCase: CaseContext {
	typealias Fixture = (id: UUID, url: URL)
	let collection: PreviewCollection
	let projects = DevToolsScenarioProjects()
	let session = UUID()
	var primary: Fixture?
	var reviewFiles: [URL] = []
	init(_ collection: PreviewCollection) { self.collection = collection }

	func setup() throws { primary = try fixture() }
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
		collection.serviceWasReaped = false
		return try collection.host.request(
			"preview", payload: payload, projectID: project.id, sessionID: session)
	}
	func error(_ response: [String: Any], reason: String) throws {
		try #require(response["status"] as? String == "error")
		let summary = try #require(response["summary"] as? String)
		#expect(summary.contains(reason), "\(summary)")
		if ["missing_preview", "ambiguous_preview", "preview_in_production"].contains(reason) {
			#expect(summary.contains("Sources/AppViews/Example.swift"))
			#expect(summary.contains("#if MAC_APPER_PREVIEW"))
			#expect(summary.contains("public func apperPreview_Example() -> some View"))
		}
		#expect(summary.utf8.count <= 4096)
		#expect(response["artifact"] == nil && response["width"] == nil && response["height"] == nil)
	}
	func image(_ response: [String: Any], in project: Fixture? = nil, size: (Int, Int)) throws -> Data
	{
		let project = try #require(project ?? primary)
		try #require(
			response["status"] as? String == "rendered", "\(response["summary"] ?? "missing summary")")
		#expect(response["width"] as? Int == size.0 && response["height"] as? Int == size.1)
		let artifact = try #require(response["artifact"] as? [String: Any])
		#expect(artifact["kind"] as? String == "png")
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
		let bytes = try Data(contentsOf: url)
		try validateImage(bytes, size: size)
		let review = URL(fileURLWithPath: try #require(artifact["reviewPath"] as? String))
		let expected = project.url.deletingLastPathComponent().resolvingSymlinksInPath()
			.appendingPathComponent(
				"previews/\(project.id.uuidString.lowercased())/\(session.uuidString.lowercased())")
		try #require(review.deletingLastPathComponent() == expected)
		try #require(
			review.lastPathComponent.range(of: #"^preview-[0-9]+\.png$"#, options: .regularExpression)
				!= nil)
		#expect(try Data(contentsOf: review) == bytes)
		reviewFiles.append(review)
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
		#expect(CGImageSourceGetType(source) as String? == "public.png")
		let image = try #require(CGImageSourceCreateImageAtIndex(source, 0, nil))
		#expect(image.width == size.0 && image.height == size.1)
		var pixel = [UInt8](repeating: 0, count: 4)
		try pixel.withUnsafeMutableBytes { bytes in
			let context = try #require(
				CGContext(
					data: bytes.baseAddress, width: 1, height: 1, bitsPerComponent: 8, bytesPerRow: 4,
					space: CGColorSpaceCreateDeviceRGB(),
					bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
			context.draw(image, in: CGRect(x: 0, y: 0, width: 1, height: 1))
		}
		#expect(
			pixel[0] > 200 && pixel[2] < 80, "Injected negative state must render red, not default blue")
	}
	func clean(in project: Fixture? = nil) throws {
		let project = try #require(project ?? primary)
		let manager = FileManager.default
		for path in [".mac-apper/PreviewBuild"] {
			let directory = project.url.appendingPathComponent(path)
			if manager.fileExists(atPath: directory.path) {
				#expect(try manager.contentsOfDirectory(atPath: directory.path).isEmpty)
			}
		}
		// No surviving compiler or snapshot executable may reference this fixture.
		let process = Process(), output = Pipe()
		process.executableURL = URL(fileURLWithPath: "/bin/ps")
		process.arguments = ["-ww", "-axo", "command="]
		process.standardOutput = output
		process.standardError = FileHandle.nullDevice
		try process.run()
		let text = String(decoding: output.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
		process.waitUntilExit()
		#expect(!text.contains(project.url.path + "/.mac-apper/PreviewBuild/"))
	}
	func noArtifacts(in project: Fixture? = nil) throws {
		let project = try #require(project ?? primary)
		let directory = project.url.appendingPathComponent(".mac-apper/Artifacts")
		if FileManager.default.fileExists(atPath: directory.path) {
			#expect(try FileManager.default.contentsOfDirectory(atPath: directory.path).isEmpty)
		}
	}
	func tool(_ fields: [String: Any]) throws -> [String: Any] {
		collection.serviceWasReaped = false
		return try harness(["params": fields])
	}
	func readImage(_ path: String) throws -> Data {
		let result = try harness(["readPath": path])
		let content = try #require(result["content"] as? [[String: Any]])
		let image = try #require(content.first { $0["type"] as? String == "image" })
		try #require(image["mimeType"] as? String == "image/png")
		let encoded = try #require(image["data"] as? String)
		return try #require(Data(base64Encoded: encoded))
	}
	private func harness(_ request: [String: Any]) throws -> [String: Any] {
		let project = try #require(primary), app = try #require(collection.host.app)
		let body = try JSONSerialization.data(withJSONObject: request)
		let reply = try XPCClientAdapter().call(
			URL(fileURLWithPath: "/usr/bin/env"), request: body,
			arguments: [
				"node", "--experimental-strip-types",
				app.appendingPathComponent("Contents/Resources/PreviewToolHarness.ts").path,
				app.appendingPathComponent("Contents/Resources/PiExtension/Extension.ts").path,
			],
			environment: [
				"OPENXPC_DEVTOOLSTERMINALCLIENT_CLIENT_PATH": app.appendingPathComponent(
					"Contents/MacOS/DevToolsTerminalClient"
				).path,
				"OPENXPC_PROJECT_ROOT": project.url.path, "OPENXPC_PROJECT_ID": project.id.uuidString,
				"OPENXPC_SESSION_ID": session.uuidString,
			], maxResponseBytes: 131_072, timeoutSeconds: 345)
		try #require(reply.status == 0)
		return try #require(JSONSerialization.jsonObject(with: reply.data) as? [String: Any])
	}
}

@MainActor private func previewCollection() -> ScenarioCollection {
	ScenarioCollection(
		"dev-tools-preview", context: PreviewCollection.init,
		setup: { try $0.host.prepare() },
		teardown: {
			try $0.reapService(); try $0.host.remove()
		},
		cases: [
			ScenarioCase(
				"preview-render", context: PreviewCase.init, setup: { try $0.setup() },
				steps: [
					Step("render injected private view and preserve project source and manifest") { context in
						let project = try #require(context.primary)
						let manifest = try Data(contentsOf: project.url.appendingPathComponent("Package.swift"))
						_ = try context.image(
							context.request(context.params(size: (320, 240))), size: (320, 240))
						#expect(
							try Data(contentsOf: project.url.appendingPathComponent("Package.swift")) == manifest)
						#expect(
							try String(
								contentsOf: project.url.appendingPathComponent("Sources/AppViews/Example.swift"),
								encoding: .utf8) == previewSource)
						try context.clean()
					},
					Step("review image survives project cleanup") { context in
						let review = try #require(context.reviewFiles.first)
						let bytes = try Data(contentsOf: review)
						try context.collection.reapService()
						try context.projects.remove()
						#expect(try Data(contentsOf: review) == bytes)
					},
				], teardown: { try $0.projects.remove() }),
			ScenarioCase(
				"preview-size", context: PreviewCase.init, setup: { try $0.setup() },
				steps: [
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
				], teardown: { try $0.projects.remove() }),
			ScenarioCase(
				"preview-factories", context: PreviewCase.init, setup: { try $0.setup() },
				steps: [
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
				], teardown: { try $0.projects.remove() }),
			ScenarioCase(
				"preview-failure-recovery", context: PreviewCase.init, setup: { try $0.setup() },
				steps: [
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
				], teardown: { try $0.projects.remove() }),
			ScenarioCase(
				"preview-scope", context: PreviewCase.init, setup: { try $0.setup() },
				steps: [
					Step("reject traversal, linked source and foreign project root") { context in
						let project = try #require(context.primary), other = try context.fixture()
						let linked = project.url.appendingPathComponent("Sources/AppViews/Linked.swift")
						try FileManager.default.createSymbolicLink(
							at: linked,
							withDestinationURL: other.url.appendingPathComponent("Sources/AppViews/Example.swift")
						)
						for payload in [
							[
								"projectRoot": project.url.path,
								"viewPath": "Sources/AppViews/../AppModel/Model.swift",
							],
							["projectRoot": project.url.path, "viewPath": "Sources/AppViews/Linked.swift"],
							["projectRoot": other.url.path, "viewPath": "Sources/AppViews/Example.swift"],
						] {
							try context.collection.host.expectRejected(
								"preview", payload: payload, error: "operationFailed", projectID: project.id,
								sessionID: context.session)
						}
						try context.noArtifacts(); try context.noArtifacts(in: other)
						try context.clean(); try context.clean(in: other)
					}
				], teardown: { try $0.projects.remove() }),
			ScenarioCase(
				"preview-path-content", context: PreviewCase.init, setup: { try $0.setup() },
				steps: [
					Step(
						"generated extension returns text-only paths readable by the installed production Pi tool"
					) {
						context in
						let project = try #require(context.primary)
						let source = project.url.appendingPathComponent("Sources/AppViews/Example.swift")
						let original = try Data(contentsOf: source)
						let result = try context.tool(context.params(size: (320, 240)))
						try #require(result["isError"] as? Bool != true)
						let content = try #require(result["content"] as? [[String: Any]])
						try #require(content.count == 1 && content[0]["type"] as? String == "text")
						let text = try #require(
							content.first { $0["type"] as? String == "text" }?["text"] as? String)
						let metadata = try #require(
							JSONSerialization.jsonObject(with: Data(text.utf8)) as? [String: Any])
						let data = try context.image(metadata, size: (320, 240))
						let artifact = try #require(metadata["artifact"] as? [String: Any])
						let relative = try #require(artifact["relativePath"] as? String)
						let review = try #require(artifact["reviewPath"] as? String)
						try #require(review.hasPrefix("/"))
						#expect(try context.readImage(relative) == data)
						#expect(try context.readImage(review) == data)
						#expect(try Data(contentsOf: source) == original)
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
						#expect(!content.contains { $0["type"] as? String == "image" })
						#expect(
							content.contains { ($0["text"] as? String)?.contains("missing_preview") == true })
						#expect(content.contains { ($0["text"] as? String)?.contains("Retry preview") == true })
						#expect(
							content.contains {
								($0["text"] as? String)?.contains("#if MAC_APPER_PREVIEW") == true
							})
						try context.clean()
					},
					Step("scope rejection still becomes a failed text-only tool result") { context in
						let result = try context.tool(["viewPath": "Sources/AppViews/../AppModel/Model.swift"])
						#expect(result["isError"] as? Bool == true)
						let content = try #require(result["content"] as? [[String: Any]])
						#expect(content.count == 1 && content[0]["type"] as? String == "text")
						try context.clean()
					},
					Step("archive remains readable by production read after project cleanup") { context in
						let review = try #require(context.reviewFiles.first)
						let bytes = try Data(contentsOf: review)
						try context.collection.reapService()
						try context.projects.remove()
						#expect(try context.readImage(review.path) == bytes)
					},
				],
				teardown: {
					try $0.collection.reapService(); try $0.projects.remove()
				}),
		])
}

@Test @MainActor func devToolsPreviewScenarios() async throws {
	let registry = try ScenarioRegistry([previewCollection()])
	if let selected = ProcessInfo.processInfo.environment["DEV_TOOLS_SCENARIO_CASE"] {
		try await registry.runCase(selected)
	} else {
		try await registry.runCollection("dev-tools-preview")
	}
}
