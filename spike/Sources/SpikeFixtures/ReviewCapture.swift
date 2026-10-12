import AppKit
import Foundation
import ImageIO
import SwiftUI
import UniformTypeIdentifiers

public struct ReviewCaptureConfiguration: Sendable {
	public let width = 720
	public let height = 540
	public let scale = 1
	public let appearance = "aqua"
	public let settlingSeconds = 0.25
	public let maximumBytes = 2_097_152
	public init() {}

	public func validatePNG(_ data: Data) throws {
		guard
			!data.isEmpty,
			data.count <= maximumBytes,
			Array(data.prefix(8)) == [137, 80, 78, 71, 13, 10, 26, 10],
			Array(data.suffix(12)) == [0, 0, 0, 0, 73, 69, 78, 68, 174, 66, 96, 130],
			let source = CGImageSourceCreateWithData(data as CFData, nil),
			CGImageSourceGetCount(source) == 1,
			let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
			(properties[kCGImagePropertyPixelWidth] as? Int) == width,
			(properties[kCGImagePropertyPixelHeight] as? Int) == height,
			let image = CGImageSourceCreateImageAtIndex(source, 0, nil),
			image.width == width,
			image.height == height
		else { throw CocoaError(.coderInvalidValue) }
	}
}

/// Caches only the owned hosting view. Never captures the desktop or a screen window image.
@MainActor public func captureReview(_ fixture: ReviewFixture, localImageURL: URL) throws -> Data {
	let config = ReviewCaptureConfiguration()
	let app = NSApplication.shared
	app.setActivationPolicy(.prohibited)
	app.appearance = NSAppearance(named: .aqua)
	let host = NSHostingView(rootView: fixture.content(localImageURL: localImageURL))
	host.frame = NSRect(x: 0, y: 0, width: config.width, height: config.height)
	let window = NSWindow(
		contentRect: host.frame, styleMask: [.borderless], backing: .buffered, defer: false)
	window.isReleasedWhenClosed = false
	window.appearance = NSAppearance(named: .aqua)
	window.setFrameOrigin(NSPoint(x: -10000, y: -10000))
	window.contentView = host
	window.orderBack(nil)
	defer { window.orderOut(nil); window.contentView = nil; window.close() }
	host.layoutSubtreeIfNeeded()
	host.displayIfNeeded()
	let deadline = ProcessInfo.processInfo.systemUptime + config.settlingSeconds
	while ProcessInfo.processInfo.systemUptime < deadline {
		_ = RunLoop.current.run(mode: .default, before: Date().addingTimeInterval(0.01))
	}
	host.layoutSubtreeIfNeeded()
	host.displayIfNeeded()
	guard
		let bitmap = NSBitmapImageRep(
			bitmapDataPlanes: nil, pixelsWide: config.width, pixelsHigh: config.height,
			bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
			colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)
	else { throw CocoaError(.coderInvalidValue) }
	bitmap.size = host.frame.size
	host.cacheDisplay(in: host.bounds, to: bitmap)
	guard
		let data = bitmap.representation(using: .png, properties: [:])
	else { throw CocoaError(.coderInvalidValue) }
	try config.validatePNG(data)
	return data
}
