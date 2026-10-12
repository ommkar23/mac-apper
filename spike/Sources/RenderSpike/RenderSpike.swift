import AppKit
import CryptoKit
import Foundation
import ImageIO
import SpikeFixtures
import SwiftUI
import UniformTypeIdentifiers

struct Artifact: Codable {
	let fixture: String
	let method: String
	let width: Int
	let height: Int
	let sha256: String
	let file: String
}

@main struct RenderSpike {
	@MainActor static func main() throws {
		if CommandLine.arguments.count == 2, CommandLine.arguments[1] == "--review-list" {
			print(ReviewFixture.allCases.map(\.rawValue).joined(separator: "\n"))
			return
		}
		if CommandLine.arguments.count == 5, CommandLine.arguments[1] == "--review" {
			guard
				let fixture = ReviewFixture(rawValue: CommandLine.arguments[4])
			else { throw CocoaError(.coderInvalidValue) }
			let data = try captureReview(
				fixture, localImageURL: URL(fileURLWithPath: CommandLine.arguments[3]))
			guard
				NSApplication.shared.windows.allSatisfy({ !$0.isVisible })
			else { throw CocoaError(.coderInvalidValue) }
			try data.write(
				to: URL(fileURLWithPath: CommandLine.arguments[2]), options: .withoutOverwriting)
			print(
				"Captured \(fixture.rawValue); 720x540 scale=1 aqua; bytes=\(data.count); all owned windows closed"
			)
			return
		}
		if CommandLine.arguments.count == 2, CommandLine.arguments[1] == "--list" {
			print(Fixture.allCases.map(\.rawValue).joined(separator: "\n"))
			return
		}
		guard
			(3...4).contains(CommandLine.arguments.count)
		else { throw CocoaError(.coderInvalidValue) }
		let selected: [Fixture]
		if CommandLine.arguments.count == 4 {
			guard
				let fixture = Fixture(rawValue: CommandLine.arguments[3])
			else { throw CocoaError(.coderInvalidValue) }
			selected = [fixture]
		} else {
			selected = Fixture.allCases
		}
		let output = URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true)
		let local = URL(fileURLWithPath: CommandLine.arguments[2])
		guard
			FileManager.default.fileExists(atPath: output.path),
			FileManager.default.fileExists(atPath: local.path)
		else { throw CocoaError(.fileNoSuchFile) }
		let app = NSApplication.shared
		app.setActivationPolicy(.prohibited)
		app.appearance = NSAppearance(named: .aqua)
		var records: [Artifact] = []
		let size = NSSize(width: Canvas.width, height: Canvas.height)
		for fixture in selected {
			// This exact value is passed to both renderers; no replacement label or state.
			let content = fixture.content(localImageURL: local)
			let renderer = ImageRenderer(content: content)
			renderer.proposedSize = ProposedViewSize(size)
			renderer.scale = 1
			guard
				let image = renderer.cgImage
			else { throw CocoaError(.coderInvalidValue) }
			records.append(try save(image, fixture: fixture, method: "image-renderer", output: output))

			let host = NSHostingView(rootView: content)
			host.frame = NSRect(origin: .zero, size: size)
			let window = NSWindow(
				contentRect: host.frame, styleMask: [.borderless],
				backing: .buffered, defer: false)
			window.isReleasedWhenClosed = false
			// Off desktop, non-key, no activation; cache the owned view, never the screen.
			window.setFrameOrigin(NSPoint(x: -10000, y: -10000))
			window.contentView = host
			window.orderBack(nil)
			defer { window.orderOut(nil); window.contentView = nil; window.close() }
			host.layoutSubtreeIfNeeded()
			host.displayIfNeeded()
			let deadline = Date().addingTimeInterval(0.25)
			while Date() < deadline {
				_ = RunLoop.current.run(mode: .default, before: Date().addingTimeInterval(0.01))
			}
			host.layoutSubtreeIfNeeded()
			host.displayIfNeeded()
			guard
				let bitmap = NSBitmapImageRep(
					bitmapDataPlanes: nil, pixelsWide: Canvas.width,
					pixelsHigh: Canvas.height, bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true,
					isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)
			else { throw CocoaError(.coderInvalidValue) }
			bitmap.size = size
			host.cacheDisplay(in: host.bounds, to: bitmap)
			guard
				let captured = bitmap.cgImage
			else { throw CocoaError(.coderInvalidValue) }
			records.append(try save(captured, fixture: fixture, method: "hosting-window", output: output))
			try comparison(image, captured, fixture: fixture, output: output)
			// Explicit lifecycle control: same content, after this fixture's owned native host.
			let afterHost = ImageRenderer(content: content)
			afterHost.proposedSize = ProposedViewSize(size)
			afterHost.scale = 1
			guard
				let warmImage = afterHost.cgImage
			else { throw CocoaError(.coderInvalidValue) }
			records.append(
				try save(warmImage, fixture: fixture, method: "image-renderer-after-host", output: output))
			try comparison(warmImage, captured, fixture: fixture, output: output, suffix: "after-host")
		}
		let encoder = JSONEncoder()
		encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
		try encoder.encode(records).write(to: output.appendingPathComponent("artifacts.json"))
		// Every loop's defer closes the only owned window before the next fixture.
		guard
			app.windows.allSatisfy({ !$0.isVisible })
		else { throw CocoaError(.coderInvalidValue) }
		print(
			"Captured \(records.count) PNGs; all owned windows closed; pid=\(ProcessInfo.processInfo.processIdentifier)"
		)
	}

	static func save(_ image: CGImage, fixture: Fixture, method: String, output: URL) throws
		-> Artifact
	{
		guard
			image.width == Canvas.width,
			image.height == Canvas.height
		else { throw CocoaError(.coderInvalidValue) }
		let data = NSMutableData()
		guard
			let destination = CGImageDestinationCreateWithData(
				data, UTType.png.identifier as CFString, 1, nil)
		else { throw CocoaError(.coderInvalidValue) }
		CGImageDestinationAddImage(destination, image, nil)
		guard
			CGImageDestinationFinalize(destination),
			data.length > 0,
			data.length <= 2_097_152
		else { throw CocoaError(.coderInvalidValue) }
		let filename = "\(fixture.rawValue)-\(method).png"
		try (data as Data).write(to: output.appendingPathComponent(filename), options: .atomic)
		let hash = SHA256.hash(data: data as Data).map { String(format: "%02x", $0) }.joined()
		return Artifact(
			fixture: fixture.rawValue, method: method, width: image.width,
			height: image.height, sha256: hash, file: filename)
	}

	static func comparison(
		_ left: CGImage, _ right: CGImage, fixture: Fixture, output: URL, suffix: String = "cold"
	) throws {
		let width = Canvas.width * 2
		guard
			let context = CGContext(
				data: nil, width: width, height: Canvas.height,
				bitsPerComponent: 8, bytesPerRow: width * 4, space: CGColorSpaceCreateDeviceRGB(),
				bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
		else { throw CocoaError(.coderInvalidValue) }
		context.setFillColor(CGColor(gray: 1, alpha: 1))
		context.fill(CGRect(x: 0, y: 0, width: width, height: Canvas.height))
		context.draw(left, in: CGRect(x: 0, y: 0, width: Canvas.width, height: Canvas.height))
		context.draw(
			right, in: CGRect(x: Canvas.width, y: 0, width: Canvas.width, height: Canvas.height))
		guard
			let result = context.makeImage()
		else { throw CocoaError(.coderInvalidValue) }
		let data = NSMutableData()
		guard
			let destination = CGImageDestinationCreateWithData(
				data, UTType.png.identifier as CFString, 1, nil)
		else { throw CocoaError(.coderInvalidValue) }
		CGImageDestinationAddImage(destination, result, nil)
		guard
			CGImageDestinationFinalize(destination)
		else { throw CocoaError(.coderInvalidValue) }
		try (data as Data).write(
			to: output.appendingPathComponent("\(fixture.rawValue)-\(suffix)-comparison.png"))
	}
}
