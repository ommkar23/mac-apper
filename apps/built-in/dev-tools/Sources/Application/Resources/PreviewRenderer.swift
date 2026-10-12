// @frontmatter:start
// Provides the isolated snapshot executable template that renders an injected preview factory to a bounded PNG.
// @frontmatter:end
import AppKit
import AppViews
import Foundation
import ImageIO
import SwiftUI
import UniformTypeIdentifiers

@main struct ApperSnapshot {
	@MainActor static func main() throws {
		guard
			CommandLine.arguments.count == 4,
			let width = Int(CommandLine.arguments[1]),
			let height = Int(CommandLine.arguments[2]),
			(64...2048).contains(width),
			(64...2048).contains(height),
			width * height <= 2_097_152
		else { throw CocoaError(.coderInvalidValue) }
		let app = NSApplication.shared
		app.setActivationPolicy(.prohibited)
		app.appearance = NSAppearance(named: .aqua)
		let content = __APPER_PREVIEW_FACTORY__()
			.frame(width: CGFloat(width), height: CGFloat(height))
			.environment(\.colorScheme, .light)
			.transaction {
				$0.disablesAnimations = true; $0.animation = nil
			}
		let image = try capture(content, width: width, height: height)
		let bytes = NSMutableData()
		guard
			let destination = CGImageDestinationCreateWithData(
				bytes, UTType.png.identifier as CFString, 1, nil)
		else { throw CocoaError(.coderInvalidValue) }
		CGImageDestinationAddImage(destination, image, nil)
		guard
			CGImageDestinationFinalize(destination),
			bytes.length > 0,
			bytes.length <= 2_097_152
		else { throw CocoaError(.coderInvalidValue) }
		try (bytes as Data).write(to: URL(fileURLWithPath: CommandLine.arguments[3]), options: .atomic)
	}

	/// Captures only the owned view, never the desktop. Closure precedes PNG publication.
	@MainActor private static func capture(_ content: some View, width: Int, height: Int) throws
		-> CGImage
	{
		let host = NSHostingView(rootView: content)
		host.frame = NSRect(x: 0, y: 0, width: width, height: height)
		let window = SnapshotWindow(
			contentRect: host.frame, styleMask: [.borderless], backing: .buffered, defer: false)
		window.isReleasedWhenClosed = false
		window.appearance = NSAppearance(named: .aqua)
		window.setFrameOrigin(NSPoint(x: -10000, y: -10000))
		defer {
			window.orderOut(nil)
			window.contentView = nil
			window.close()
		}
		window.contentView = host
		window.orderBack(nil)
		host.layoutSubtreeIfNeeded()
		host.displayIfNeeded()
		// A bounded layout opportunity, not an asynchronous-content readiness handshake.
		let deadline = ProcessInfo.processInfo.systemUptime + 0.25
		while ProcessInfo.processInfo.systemUptime < deadline {
			_ = RunLoop.current.run(mode: .default, before: Date().addingTimeInterval(0.01))
		}
		host.layoutSubtreeIfNeeded()
		host.displayIfNeeded()
		// Explicit scale 1 regardless of the screen/window backing scale.
		guard
			let bitmap = NSBitmapImageRep(
				bitmapDataPlanes: nil, pixelsWide: width, pixelsHigh: height,
				bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
				colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)
		else { throw CocoaError(.coderInvalidValue) }
		bitmap.size = host.frame.size
		host.cacheDisplay(in: host.bounds, to: bitmap)
		guard
			let image = bitmap.cgImage,
			image.width == width,
			image.height == height
		else { throw CocoaError(.coderInvalidValue) }
		return image
	}
}

private final class SnapshotWindow: NSWindow {
	override var canBecomeKey: Bool { false }
	override var canBecomeMain: Bool { false }
}
