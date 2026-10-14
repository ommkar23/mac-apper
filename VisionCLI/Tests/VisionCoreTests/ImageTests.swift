// @frontmatter:start
// Tests real PNG decoding, truncated and unsupported image rejection, bounded file reads, and symlink refusal in owned temporary fixtures.
// @frontmatter:end
import Foundation
import Scenario
import ImageIO
import Testing
@testable import VisionCore

@Test func imagesAreDecodedAndBoundToTheirBytesAndDimensions() throws {
	let root = try ProjectTemporaryDirectory.root().appendingPathComponent(UUID().uuidString)
	try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
	defer { try? FileManager.default.removeItem(at: root) }
	let context = try #require(
		CGContext(
			data: nil, width: 4, height: 3, bitsPerComponent: 8, bytesPerRow: 16,
			space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
	)
	let image = try #require(context.makeImage())
	let bytes = NSMutableData()
	let destination = try #require(
		CGImageDestinationCreateWithData(bytes, "public.png" as CFString, 1, nil))
	CGImageDestinationAddImage(destination, image, nil)
	#expect(CGImageDestinationFinalize(destination))
	let file = root.appendingPathComponent("image.png")
	try (bytes as Data).write(to: file)
	let request = VisionRequest(
		requestID: UUID(), imagePath: file.path,
		criteria: [Criterion(id: "offline", description: "No Gemini call")])
	let decoded = try VisionRequest.decode(JSONEncoder().encode(request))
	#expect(decoded.imagePath == file.path)
	#expect(decoded.imagePath.hasPrefix(root.path + "/"))
	let loaded = try LoadedImage.load(path: decoded.imagePath)
	let alias = root.path + "/./image.png"
	#expect(alias.contains("/./"))
	#expect(throws: (any Error).self) { try LoadedImage.load(path: alias) }
	#expect(loaded.width == 4 && loaded.height == 3 && loaded.mimeType == "image/png")
	#expect(loaded.data == bytes as Data && loaded.sha256.count == 64)

	let jpegBytes = NSMutableData()
	let jpegDestination = try #require(
		CGImageDestinationCreateWithData(jpegBytes, "public.jpeg" as CFString, 1, nil))
	CGImageDestinationAddImage(jpegDestination, image, nil)
	#expect(CGImageDestinationFinalize(jpegDestination))
	let jpeg = root.appendingPathComponent("image.jpeg")
	try (jpegBytes as Data).write(to: jpeg)
	#expect(try LoadedImage.load(path: jpeg.path).mimeType == "image/jpeg")
	let parentLink = root.appendingPathComponent("parent-link")
	try FileManager.default.createSymbolicLink(at: parentLink, withDestinationURL: root)
	#expect(throws: (any Error).self) {
		try LoadedImage.load(path: parentLink.appendingPathComponent("image.png").path)
	}

	let link = root.appendingPathComponent("linked.png")
	try FileManager.default.createSymbolicLink(at: link, withDestinationURL: file)
	#expect(throws: (any Error).self) { try LoadedImage.load(path: link.path) }
	#expect(throws: (any Error).self) { try LocalFile.read(file.path, limit: 1) }
	let truncated = root.appendingPathComponent("truncated.png")
	try Data((bytes as Data).dropLast(20)).write(to: truncated)
	#expect(throws: (any Error).self) { try LoadedImage.load(path: truncated.path) }
	let invalid = root.appendingPathComponent("invalid.png")
	try Data("not an image".utf8).write(to: invalid)
	#expect(throws: (any Error).self) { try LoadedImage.load(path: invalid.path) }
}
