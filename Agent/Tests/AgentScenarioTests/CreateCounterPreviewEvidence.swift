// @frontmatter:start
// Audits successful Preview, Build, and Run without tool ordering and returns the last validated PNG's archive path, dimensions, and hash.
// @frontmatter:end
import CoreFoundation
import CryptoKit
import Darwin
import Foundation
import AgentScenarioSupport
import ImageIO
import Testing

struct VerifiedCounterPreview: Sendable {
	let reviewPath: URL
	let width: Int
	let height: Int
	let sha256: String
}

func verifyPreview(session: URL, project: URL) throws -> VerifiedCounterPreview {
	let evidence = try ScenarioToolEvidence(session: session)
	let projectValues = try project.resourceValues(forKeys: [.isDirectoryKey, .isSymbolicLinkKey])
	try #require(projectValues.isDirectory == true && projectValues.isSymbolicLink != true)
	let manifestURL = project.appendingPathComponent("app-manifest.json")
	let manifestValues = try manifestURL.resourceValues(forKeys: [
		.isRegularFileKey, .isSymbolicLinkKey, .fileSizeKey,
	])
	try #require(
		manifestValues.isRegularFile == true && manifestValues.isSymbolicLink != true
			&& (manifestValues.fileSize ?? Int.max) <= 4096)
	let manifest = try #require(
		JSONSerialization.jsonObject(with: Data(contentsOf: manifestURL)) as? [String: Any])
	let executableTarget = try #require(manifest["executableTarget"] as? String)
	try #require(
		executableTarget.range(of: #"^[A-Za-z][A-Za-z0-9_]{0,63}$"#, options: .regularExpression) != nil
	)
	try #require(
		!evidence.calls.contains { $0.name.hasPrefix("mcp__parallel__") }, "Unexpected Parallel call")
	var preview: VerifiedCounterPreview?
	var buildCompleted = false, runCompleted = false
	for call in evidence.calls.sorted(by: { $0.finished < $1.finished }) where call.succeeded {
		switch call.name {
		case "preview":
			let result = try #require(call.typedResult)
			if result["status"] as? String == "error" {
				// Typed rendering errors no longer throw through an automatic image loader.
				// Preserve recovery semantics: only a rendered result can satisfy Preview success.
				let summary = try #require(result["summary"] as? String)
				try #require(!summary.isEmpty && summary.utf8.count <= 4096)
				try #require(result["artifact"] == nil && result["width"] == nil && result["height"] == nil)
				continue
			}
			let arguments = call.arguments
			let viewPath = try #require(arguments["viewPath"] as? String)
			try #require(viewPath.utf8.count <= 1024)
			try #require(
				viewPath.range(
					of: #"^Sources/AppViews/(?:[A-Za-z0-9_-]+/)*[A-Za-z0-9_-]+\.swift$"#,
					options: .regularExpression) != nil)
			var sourceURL = project
			for component in viewPath.split(separator: "/") {
				sourceURL.appendPathComponent(String(component))
				try #require(
					try sourceURL.resourceValues(forKeys: [.isSymbolicLinkKey]).isSymbolicLink != true)
			}
			let sourceValues = try sourceURL.resourceValues(forKeys: [.isRegularFileKey, .fileSizeKey])
			try #require(
				sourceValues.isRegularFile == true && (sourceValues.fileSize ?? Int.max) <= 1_048_576)
			try #require(result["status"] as? String == "rendered")
			let width = try #require(previewInteger(result["width"]))
			let height = try #require(previewInteger(result["height"]))
			try #require((64...2048).contains(width) && (64...2048).contains(height))
			try #require(width * height <= 2_097_152)
			if let suppliedSize = arguments["screenSize"] {
				let size = try #require(suppliedSize as? [String: Any])
				try #require(
					previewInteger(size["width"]) == width && previewInteger(size["height"]) == height)
			} else {
				try #require(width == 640 && height == 480)
			}
			let artifact = try #require(result["artifact"] as? [String: Any])
			try #require(artifact["kind"] as? String == "png")
			let path = try #require(artifact["relativePath"] as? String)
			let components = path.split(separator: "/", omittingEmptySubsequences: false)
			try #require(components.count == 4)
			try #require(components[0] == ".mac-apper" && components[1] == "Artifacts")
			try #require(UUID(uuidString: String(components[2])) != nil && components[3] == "render.png")
			var url = project
			for component in components {
				url.appendPathComponent(String(component))
				try #require(try url.resourceValues(forKeys: [.isSymbolicLinkKey]).isSymbolicLink != true)
			}
			let attributes = try url.resourceValues(forKeys: [.isRegularFileKey, .fileSizeKey])
			try #require(
				attributes.isRegularFile == true && (attributes.fileSize ?? Int.max) <= 2_097_152)
			let bytes = try previewBytes(url)
			try verifyPNG(bytes, width: width, height: height)
			let reviewPath = try #require(artifact["reviewPath"] as? String)
			try #require(reviewPath.hasPrefix("/") && reviewPath.utf8.count <= 4096)
			try #require(!reviewPath.contains("\0") && !reviewPath.contains("\\"))
			try #require(
				reviewPath.dropFirst().split(separator: "/", omittingEmptySubsequences: false)
					.allSatisfy { !$0.isEmpty && $0 != "." && $0 != ".." })
			let review = URL(fileURLWithPath: reviewPath)
			let sessionID = try #require(
				UUID(uuidString: String(session.deletingPathExtension().lastPathComponent.suffix(36))))
			let expected = project.deletingLastPathComponent().appendingPathComponent(
				"previews/\(project.lastPathComponent)/\(sessionID.uuidString.lowercased())")
			// Validate both existing directory identities, accepting only trusted OS aliases.
			try #require(
				try ScenarioDirectoryIdentity.read(review.deletingLastPathComponent().path)
					== ScenarioDirectoryIdentity.read(expected.path))
			try #require(
				review.lastPathComponent.range(of: #"^preview-[0-9]+\.png$"#, options: .regularExpression)
					!= nil)
			var archive = project.deletingLastPathComponent()
			for component in [
				"previews", project.lastPathComponent, sessionID.uuidString.lowercased(),
				review.lastPathComponent,
			] {
				archive.appendPathComponent(component)
				try #require(
					try archive.resourceValues(forKeys: [.isSymbolicLinkKey]).isSymbolicLink != true)
			}
			try #require(try canonicalArchiveBytes(reviewPath) == bytes)
			print("CREATE_PREVIEW_RETAINED: \(review.path)")
			print(
				"CREATE_PREVIEW: \(width)x\(height) validated PNG, matching archive bytes (inspection not asserted), path: \(url.path)"
			)
			preview = VerifiedCounterPreview(
				reviewPath: review, width: width, height: height,
				sha256: SHA256.hash(data: bytes).map { String(format: "%02x", $0) }.joined())
		case "build":
			let result = try #require(call.typedResult)
			try #require(result["target"] as? String == executableTarget)
			try #require(!(result["summary"] as? String ?? "").isEmpty)
			buildCompleted = true
		case "run":
			let result = try #require(call.typedResult)
			let target = try #require(result["target"] as? String)
			try #require(target == executableTarget)
			let relative = try #require(result["relativePath"] as? String)
			let components = relative.split(separator: "/", omittingEmptySubsequences: false)
			try #require(
				components.count == 4 && components[0] == ".mac-apper" && components[1] == "DevBuild")
			try #require(
				UUID(uuidString: String(components[2])) != nil && components[3] == "\(target).app")
			runCompleted = true
		default: break
		}
	}
	let verified = try #require(
		preview, "Missing successful preview with valid PNG and matching archive")
	try #require(buildCompleted, "Missing successful build tool result")
	try #require(runCompleted, "Missing successful run tool result")
	let temporary = project.appendingPathComponent(".mac-apper/PreviewBuild")
	if (try? FileManager.default.attributesOfItem(atPath: temporary.path)) != nil {
		let values = try temporary.resourceValues(forKeys: [.isDirectoryKey, .isSymbolicLinkKey])
		try #require(values.isDirectory == true && values.isSymbolicLink != true)
		try #require(try FileManager.default.contentsOfDirectory(atPath: temporary.path).isEmpty)
	}
	return verified
}

private func verifyPNG(_ bytes: Data, width: Int, height: Int) throws {
	try #require(bytes.starts(with: [137, 80, 78, 71, 13, 10, 26, 10]))
	var offset = 8, complete = false
	while offset + 12 <= bytes.count {
		let length = bytes[offset..<offset + 4].reduce(0) { ($0 << 8) | Int($1) }
		try #require(length <= bytes.count - offset - 12)
		let chunk = String(decoding: bytes[offset + 4..<offset + 8], as: UTF8.self)
		offset += length + 12
		if chunk == "IEND" {
			complete =
				length == 0 && offset == bytes.count
				&& bytes.suffix(12) == Data([0, 0, 0, 0, 73, 69, 78, 68, 174, 66, 96, 130])
			break
		}
	}
	try #require(complete)
	let source = try #require(CGImageSourceCreateWithData(bytes as CFData, nil))
	try #require(CGImageSourceGetType(source) as String? == "public.png")
	try #require(CGImageSourceGetCount(source) == 1)
	let properties = try #require(
		CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [String: Any])
	try #require(
		previewInteger(properties[kCGImagePropertyPixelWidth as String]) == width
			&& previewInteger(properties[kCGImagePropertyPixelHeight as String]) == height)
	let image = try #require(CGImageSourceCreateImageAtIndex(source, 0, nil))
	try #require(
		CGImageSourceGetStatus(source) == .statusComplete
			&& CGImageSourceGetStatusAtIndex(source, 0) == .statusComplete)
	try #require(image.width == width && image.height == height)
}

private func previewInteger(_ value: Any?) -> Int? {
	guard
		let number = value as? NSNumber,
		CFGetTypeID(number) != CFBooleanGetTypeID(),
		number.doubleValue == Double(number.intValue)
	else { return nil }
	return number.intValue
}

// The producer path is preserved, not normalized: every ancestor and the leaf must
// open without following links. Descriptor reads bind byte checks to that file.
// This is point-in-time validation, not protection against later replacement.
private func canonicalArchiveBytes(_ path: String) throws -> Data {
	var descriptor = open("/", O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC)
	try #require(descriptor >= 0)
	defer { Darwin.close(descriptor) }
	let components = path.dropFirst().split(separator: "/").map(String.init)
	for (index, component) in components.enumerated() {
		let directory = index < components.count - 1
		let next = openat(
			descriptor, component,
			O_RDONLY | O_NOFOLLOW | O_CLOEXEC | O_NONBLOCK | (directory ? O_DIRECTORY : 0))
		try #require(next >= 0, "Linked or missing canonical archive component")
		Darwin.close(descriptor)
		descriptor = next
	}
	var info = stat()
	try #require(fstat(descriptor, &info) == 0 && info.st_mode & S_IFMT == S_IFREG)
	try #require(info.st_size > 0 && info.st_size <= 2_097_152)
	var canonical = [CChar](repeating: 0, count: Int(MAXPATHLEN))
	try #require(fcntl(descriptor, F_GETPATH, &canonical) == 0)
	try #require(
		String(decoding: canonical.prefix { $0 != 0 }.map { UInt8(bitPattern: $0) }, as: UTF8.self)
			== path)
	let handle = FileHandle(fileDescriptor: descriptor, closeOnDealloc: false)
	let bytes = try handle.read(upToCount: 2_097_153) ?? Data()
	try #require(bytes.count == info.st_size && bytes.count <= 2_097_152)
	return bytes
}

private func previewBytes(_ url: URL) throws -> Data {
	let handle = try FileHandle(forReadingFrom: url)
	defer { try? handle.close() }
	let bytes = try handle.read(upToCount: 2_097_153) ?? Data()
	try #require(!bytes.isEmpty && bytes.count <= 2_097_152)
	return bytes
}
