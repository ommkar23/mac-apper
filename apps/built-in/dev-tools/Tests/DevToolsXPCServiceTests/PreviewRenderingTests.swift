// @frontmatter:start
// Verifies real preview compilation, injected model-state rendering, sizing, discovery errors, and isolated source/artifact cleanup.
// @frontmatter:end
import Darwin
import Foundation
import Scenario
import ImageIO
import Testing
@testable import DevToolsApplication

struct PreviewFixture {
	let root: URL
	let project: URL
	let id: UUID
	let factory: ControllerFactory
	init(source: String) throws {
		root = try ProjectTemporaryDirectory.root().appendingPathComponent(UUID().uuidString)
		id = UUID()
		project = root.appendingPathComponent(id.uuidString.lowercased())
		try FileManager.default.createDirectory(
			at: project.appendingPathComponent("Sources/AppViews"), withIntermediateDirectories: true)
		try FileManager.default.createDirectory(
			at: project.appendingPathComponent("Sources/AppModel"), withIntermediateDirectories: true)
		try """
		// swift-tools-version: 6.0
		import PackageDescription
		let package = Package(name: "PreviewFixture", platforms: [.macOS(.v14)], targets: [
		    .target(name: "AppModel"), .target(name: "AppViews", dependencies: ["AppModel"])
		])
		""".write(
			to: project.appendingPathComponent("Package.swift"), atomically: true, encoding: .utf8)
		try """
		{"schemaVersion":1,"appID":"\(id.uuidString.lowercased())","executableTarget":"ProductionApp","previewTarget":"PreviewApp","devServiceID":"com.macapper.generated.\(id.uuidString.lowercased())"}
		""".write(
			to: project.appendingPathComponent("app-manifest.json"), atomically: true, encoding: .utf8)
		try
			"#if compiler(<6.4)\n#error(\"Swift 6.4 is required\")\n#endif\npublic struct Model { public var count = 0; public init() {} }"
			.write(
				to: project.appendingPathComponent("Sources/AppModel/Model.swift"), atomically: true,
				encoding: .utf8)
		try source.write(
			to: project.appendingPathComponent("Sources/AppViews/Example.swift"), atomically: true,
			encoding: .utf8)
		factory = ControllerFactory(projectsRoot: root)
	}
	func preview(_ size: PreviewScreenSize? = nil, sessionID: UUID = UUID()) async throws
		-> PreviewResult
	{
		try await factory.controllers().preview.handle(
			id, sessionID,
			PreviewRequest(
				projectRoot: project.path, viewPath: "Sources/AppViews/Example.swift", screenSize: size))
	}
	func remove() throws { try FileManager.default.removeItem(at: root) }
}

private let validPreview = """
	import SwiftUI
	import AppModel
	private struct FixtureView: View {
	    let model: Model
	    var body: some View { model.count == -3 ? Color.red : Color.blue }
	}
	#if MAC_APPER_PREVIEW
	@MainActor public func apperPreview_Example() -> some View {
	    var model = Model()
	    model.count = -3
	    return FixtureView(model: model)
	}
	#endif
	"""

@Test func previewRendersInjectedPrivateViewWithoutChangingProjectSources() async throws {
	let fixture = try PreviewFixture(source: validPreview)
	defer { try? fixture.remove() }
	let manifest = try Data(contentsOf: fixture.project.appendingPathComponent("Package.swift"))
	let session = UUID()
	let response = try await fixture.preview(
		PreviewScreenSize(width: 320, height: 240), sessionID: session)
	try #require(response.status == "rendered", "\(response.summary)")
	#expect(response.width == 320 && response.height == 240)
	let artifact = try #require(response.artifact)
	#expect(artifact.kind == "png")
	#expect(artifact.relativePath.hasPrefix(".mac-apper/Artifacts/"))
	let data = try Data(contentsOf: fixture.project.appendingPathComponent(artifact.relativePath))
	let review = URL(fileURLWithPath: artifact.reviewPath)
	let canonicalRoot = try #require(realpath(fixture.root.path, nil))
	defer { free(canonicalRoot) }
	#expect(
		review.deletingLastPathComponent().path
			== "\(String(cString: canonicalRoot))/previews/\(fixture.id.uuidString.lowercased())/\(session.uuidString.lowercased())"
	)
	#expect(try readArchiveWithoutFollowingLinks(artifact.reviewPath) == data)
	let image = try #require(CGImageSourceCreateWithData(data as CFData, nil))
	let decoded = try #require(CGImageSourceCreateImageAtIndex(image, 0, nil))
	#expect(decoded.width == 320 && decoded.height == 240)
	var pixel = [UInt8](repeating: 0, count: 4)
	try pixel.withUnsafeMutableBytes { bytes in
		let context = try #require(
			CGContext(
				data: bytes.baseAddress, width: 1, height: 1, bitsPerComponent: 8, bytesPerRow: 4,
				space: CGColorSpaceCreateDeviceRGB(),
				bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
		context.draw(decoded, in: CGRect(x: 0, y: 0, width: 1, height: 1))
	}
	#expect(
		pixel[0] > 200 && pixel[2] < 80, "Injected negative model must render red, not default blue")
	#expect(try Data(contentsOf: fixture.project.appendingPathComponent("Package.swift")) == manifest)
	#expect(
		try String(
			contentsOf: fixture.project.appendingPathComponent("Sources/AppViews/Example.swift"),
			encoding: .utf8) == validPreview)
	#expect(
		try FileManager.default.contentsOfDirectory(
			atPath: fixture.project.appendingPathComponent(".mac-apper/PreviewBuild").path
		).isEmpty)
	try FileManager.default.removeItem(at: fixture.project)
	#expect(
		try readArchiveWithoutFollowingLinks(artifact.reviewPath) == data,
		"Review PNG must outlive the generated project")
}

@Test func previewDefaultsTo640By480() async throws {
	let fixture = try PreviewFixture(source: validPreview)
	defer { try? fixture.remove() }
	let response = try await fixture.preview()
	try #require(response.status == "rendered", "\(response.summary)")
	#expect(response.width == 640 && response.height == 480)
}

@Test func previewRejectsInvalidCanvasBeforeBuilding() async throws {
	let fixture = try PreviewFixture(source: validPreview)
	defer { try? fixture.remove() }
	for (width, height) in [(0, 240), (320, 2049), (2048, 2048), (Int.max, Int.max)] {
		let response = try await fixture.preview(PreviewScreenSize(width: width, height: height))
		#expect(response.status == "error")
		#expect(response.summary.contains("invalidScreenSize"))
		#expect(response.artifact == nil)
	}
	#expect(
		!FileManager.default.fileExists(
			atPath: fixture.project.appendingPathComponent(".mac-apper/PreviewBuild").path))
}

@Test func previewRejectsCommentDecoysAmbiguityAndProductionFactories() async throws {
	let sources = [
		(
			"import SwiftUI\n// @MainActor public func apperPreview_Fake() -> some View { Color.red }\n",
			"missing_preview"
		),
		(
			validPreview
				+ "\n#if MAC_APPER_PREVIEW\n@MainActor public func apperPreview_Second() -> some View { Color.blue }\n#endif",
			"ambiguous_preview"
		),
		(
			validPreview.replacingOccurrences(of: "#if MAC_APPER_PREVIEW\n", with: "")
				.replacingOccurrences(of: "#endif", with: ""), "preview_in_production"
		),
		(
			validPreview.replacingOccurrences(of: "@MainActor public", with: "@MainActor private"),
			"invalid_preview_factory"
		),
		(
			validPreview.replacingOccurrences(
				of: "apperPreview_Example()", with: "apperPreview_Example(value: Int = 0)"),
			"invalid_preview_factory"
		),
	]
	for (source, reason) in sources {
		let fixture = try PreviewFixture(source: source)
		defer { try? fixture.remove() }
		let response = try await fixture.preview()
		#expect(response.status == "error", "\(response.summary)")
		#expect(response.summary.contains(reason), "\(response.summary)")
		#expect(response.artifact == nil)
	}
}

@Test func previewRejectsLinkedSourceFiles() async throws {
	let fixture = try PreviewFixture(source: validPreview)
	defer { try? fixture.remove() }
	let source = fixture.project.appendingPathComponent("Sources/AppViews/Example.swift")
	try FileManager.default.removeItem(at: source)
	try FileManager.default.createSymbolicLink(
		at: source,
		withDestinationURL: fixture.project.appendingPathComponent("Sources/AppModel/Model.swift"))
	await #expect(throws: (any Error).self) { _ = try await fixture.preview() }
}
