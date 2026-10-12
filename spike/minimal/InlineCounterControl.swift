import AppKit
import Foundation
import ImageIO
import SwiftUI
import UniformTypeIdentifiers

// Standalone no-package/no-resource reproduction for the tested macOS installation.
@main struct CounterRepro {
	@MainActor static func main() throws {
		guard
			CommandLine.arguments.count == 2
		else { throw CocoaError(.coderInvalidValue) }
		_ = NSApplication.shared
		NSApplication.shared.setActivationPolicy(.prohibited)
		NSApplication.shared.appearance = NSAppearance(named: .aqua)
		let content = VStack(spacing: 24) {
			Image(systemName: "number.square.fill")
				.font(.system(size: 44)).foregroundStyle(.blue)
			Text("0").font(.system(size: 56, weight: .bold))
			HStack(spacing: 16) {
				Button {
				} label: {
					Label("Increment", systemImage: "plus")
				}
				Button {
				} label: {
					Label("Decrement", systemImage: "minus")
				}
			}.buttonStyle(.bordered).controlSize(.large)
			Button("Reset") {}.buttonStyle(.plain)
		}
		.frame(width: 460, height: 430)
		.environment(\.colorScheme, .light)
		.transaction {
			$0.disablesAnimations = true; $0.animation = nil
		}
		let renderer = ImageRenderer(content: content)
		renderer.proposedSize = ProposedViewSize(width: 460, height: 430)
		renderer.scale = 1
		guard
			let image = renderer.cgImage,
			image.width == 460,
			image.height == 430
		else { throw CocoaError(.coderInvalidValue) }
		guard
			let context = CGContext(
				data: nil, width: 460, height: 430, bitsPerComponent: 8,
				bytesPerRow: 460 * 4, space: CGColorSpaceCreateDeviceRGB(),
				bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
		else { throw CocoaError(.coderInvalidValue) }
		context.setFillColor(CGColor(gray: 1, alpha: 1))
		context.fill(CGRect(x: 0, y: 0, width: 460, height: 430))
		context.draw(image, in: CGRect(x: 0, y: 0, width: 460, height: 430))
		guard
			let white = context.makeImage()
		else { throw CocoaError(.coderInvalidValue) }
		for (suffix, bitmap) in [("", image), ("-white.png", white)] {
			let bytes = NSMutableData()
			guard
				let destination = CGImageDestinationCreateWithData(
					bytes, UTType.png.identifier as CFString, 1, nil)
			else { throw CocoaError(.coderInvalidValue) }
			CGImageDestinationAddImage(destination, bitmap, nil)
			guard
				CGImageDestinationFinalize(destination),
				bytes.length <= 2_097_152
			else { throw CocoaError(.coderInvalidValue) }
			try (bytes as Data).write(to: URL(fileURLWithPath: CommandLine.arguments[1] + suffix))
		}
	}
}
