// Verifies owned native-view capture through the production Preview compiler and renderer.
import Foundation
import ImageIO
import Testing
@testable import DevToolsApplication

private let nativePreviewSource = """
	import AppKit
	import SwiftUI
	import AppModel
	private struct NativeTile: NSViewRepresentable {
	    func makeNSView(context: Context) -> NSTextField {
	        let field = NSTextField(labelWithString: "Native composed content")
	        field.textColor = .black
	        field.backgroundColor = .white
	        field.drawsBackground = true
	        return field
	    }
	    func updateNSView(_ view: NSTextField, context: Context) {}
	}
	private struct FixtureView: View {
	    let model: Model
	    var body: some View {
	        VStack(spacing: 12) {
	            Image(systemName: "number.square.fill")
	            Text("Seeded count: \\(model.count)")
	            Button { } label: { Label("Increment", systemImage: "plus") }
	                .buttonStyle(.bordered).controlSize(.large)
	            Button("Decrement") { }.buttonStyle(.borderless)
	            Button("Reset") { }.buttonStyle(.borderedProminent)
	            NativeTile().frame(width: 260, height: 30)
	            ProgressView(value: 0.6).frame(width: 260)
	        }.foregroundStyle(.black).frame(maxWidth: .infinity, maxHeight: .infinity)
	            .background(.white)
	    }
	}
	#if MAC_APPER_PREVIEW
	@MainActor public func apperPreview_Native() -> some View {
	    var model = Model()
	    model.count = -3
	    return FixtureView(model: model)
	}
	#endif
	"""

@Test func previewNativeStyledLabelsAndComposedContent() async throws {
	let fixture = try PreviewFixture(source: nativePreviewSource)
	defer { try? fixture.remove() }
	let result = try await fixture.preview(PreviewScreenSize(width: 460, height: 430))
	try #require(result.status == "rendered", "\(result.summary)")
	let artifact = try #require(result.artifact)
	let data = try Data(contentsOf: URL(fileURLWithPath: artifact.reviewPath))
	let source = try #require(CGImageSourceCreateWithData(data as CFData, nil))
	let image = try #require(CGImageSourceCreateImageAtIndex(source, 0, nil))
	try #require(image.width == 460 && image.height == 430)
	var pixels = [UInt8](repeating: 0, count: 460 * 430 * 4)
	try pixels.withUnsafeMutableBytes { buffer in
		let context = try #require(
			CGContext(
				data: buffer.baseAddress, width: 460, height: 430, bitsPerComponent: 8,
				bytesPerRow: 460 * 4, space: CGColorSpaceCreateDeviceRGB(),
				bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
		context.draw(image, in: CGRect(x: 0, y: 0, width: 460, height: 430))
	}
	var placeholderPixels = 0
	var darkPixels = 0
	for index in stride(from: 0, to: pixels.count, by: 4) {
		let red = pixels[index], green = pixels[index + 1], blue = pixels[index + 2]
		if red > 180 && blue < 80 { placeholderPixels += 1 }
		if red < 100 && green < 100 && blue < 100 && pixels[index + 3] > 200 { darkPixels += 1 }
	}
	#expect(placeholderPixels < 100, "Native controls must not be yellow/red whole-view placeholders")
	#expect(darkPixels > 500, "Seeded labels and composed native content must contribute ink")
	// Fixed fixture regions, not OCR or a claim about arbitrary content. Exclude button borders.
	for rows in [168..<182, 205..<217, 233..<246, 271..<285] {
		var ink = 0
		for y in rows {
			for x in 205..<270 {
				let index = (y * 460 + x) * 4
				if pixels[index] < 140 && pixels[index + 1] < 140 && pixels[index + 2] < 140 {
					ink += 1
				}
			}
		}
		#expect(ink > 40, "Each styled label/native text region must contain readable ink")
	}
	#expect(
		try Data(contentsOf: fixture.project.appendingPathComponent(artifact.relativePath)) == data)
	#expect(
		try FileManager.default.contentsOfDirectory(
			atPath: fixture.project.appendingPathComponent(".mac-apper/PreviewBuild").path
		).isEmpty)
	if let directory = ProcessInfo.processInfo.environment["DEV_TOOLS_PREVIEW_EXPORT_DIR"] {
		try data.write(
			to: URL(fileURLWithPath: directory).appendingPathComponent("native-composed.png"),
			options: .withoutOverwriting)
	}
}
