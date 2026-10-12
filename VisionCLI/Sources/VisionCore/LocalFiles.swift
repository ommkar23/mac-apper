// @frontmatter:start
// Reads bounded nonlinked files, validates PNG/JPEG decoding and pixel bounds, and loads private API credentials without shell evaluation.
// @frontmatter:end
import CryptoKit
import Darwin
import Foundation
import ImageIO

struct LocalFile {
	static func read(_ path: String, limit: Int, secret: Bool = false) throws -> Data {
		let code: VisionFailure.Code = secret ? .invalid_credentials : .invalid_image
		let failure = VisionFailure(
			code, "File must be bounded, regular, and nonlinked; credential files must be owner-only.")
		let components = path.split(separator: "/", omittingEmptySubsequences: false).dropFirst()
		guard
			path.hasPrefix("/"),
			path.utf8.count <= 4096,
			!path.unicodeScalars.contains(where: CharacterSet.controlCharacters.contains),
			!components.isEmpty,
			components.allSatisfy({ !$0.isEmpty && $0 != "." && $0 != ".." })
		else { throw failure }
		var directory = open("/", O_RDONLY | O_DIRECTORY | O_CLOEXEC)
		guard
			directory >= 0
		else { throw failure }
		defer { close(directory) }
		for component in components.dropLast() {
			let child = openat(
				directory, String(component), O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC)
			guard
				child >= 0
			else { throw failure }
			close(directory); directory = child
		}
		guard
			let name = components.last
		else { throw failure }
		let file = openat(directory, String(name), O_RDONLY | O_NONBLOCK | O_NOFOLLOW | O_CLOEXEC)
		guard
			file >= 0
		else { throw failure }
		defer { close(file) }
		var info = stat()
		guard
			fstat(file, &info) == 0,
			info.st_mode & S_IFMT == S_IFREG,
			info.st_size > 0,
			info.st_size <= limit,
			!secret || (info.st_uid == getuid() && info.st_mode & 0o077 == 0)
		else { throw failure }
		let handle = FileHandle(fileDescriptor: file, closeOnDealloc: false)
		let bytes = try handle.read(upToCount: limit + 1) ?? Data()
		guard
			bytes.count <= limit,
			bytes.count == info.st_size
		else { throw failure }
		return bytes
	}
}

public struct LoadedImage: Sendable {
	public let data: Data
	public let mimeType: String
	public let width: Int
	public let height: Int
	public let sha256: String

	public static func load(path: String) throws -> Self {
		let bytes = try LocalFile.read(path, limit: 8_388_608)
		guard
			let source = CGImageSourceCreateWithData(bytes as CFData, nil),
			CGImageSourceGetCount(source) == 1,
			let type = CGImageSourceGetType(source) as String?,
			["public.png", "public.jpeg"].contains(type),
			let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [String: Any],
			let width = properties[kCGImagePropertyPixelWidth as String] as? Int,
			let height = properties[kCGImagePropertyPixelHeight as String] as? Int,
			(1...8192).contains(width),
			(1...8192).contains(height),
			width * height <= 16_777_216,
			CGImageSourceCreateImageAtIndex(source, 0, nil) != nil,
			CGImageSourceGetStatus(source) == .statusComplete,
			CGImageSourceGetStatusAtIndex(source, 0) == .statusComplete,
			completeEnvelope(bytes, type: type)
		else {
			throw VisionFailure(
				.invalid_image, "Provide a decodable PNG/JPEG, at most 8 MiB and 16,777,216 pixels.")
		}
		return Self(
			data: bytes, mimeType: type == "public.png" ? "image/png" : "image/jpeg", width: width,
			height: height,
			sha256: SHA256.hash(data: bytes).map { String(format: "%02x", $0) }.joined())
	}

	private static func completeEnvelope(_ bytes: Data, type: String) -> Bool {
		if type == "public.jpeg" {
			return bytes.starts(with: [0xFF, 0xD8]) && bytes.suffix(2) == Data([0xFF, 0xD9])
		}
		guard
			bytes.starts(with: [137, 80, 78, 71, 13, 10, 26, 10])
		else { return false }
		var offset = 8
		while offset + 12 <= bytes.count {
			let length = bytes[offset..<offset + 4].reduce(0) { ($0 << 8) | Int($1) }
			guard
				length <= bytes.count - offset - 12
			else { return false }
			let chunk = String(decoding: bytes[offset + 4..<offset + 8], as: UTF8.self)
			offset += length + 12
			if chunk == "IEND" {
				return length == 0 && offset == bytes.count
					&& bytes.suffix(12) == Data([0, 0, 0, 0, 73, 69, 78, 68, 174, 66, 96, 130])
			}
		}
		return false
	}
}

public struct Credentials: Sendable {
	public let value: String
	public let source: String

	public static func load(environment: [String: String], file: URL?) throws -> Self {
		if let key = environment["GEMINI_API_KEY"], !key.isEmpty {
			return try checked(key, source: "environment")
		}
		guard
			let file
		else {
			throw VisionFailure(
				.missing_api_key, "Set GEMINI_API_KEY or configure a private project .env file.")
		}
		let data = try LocalFile.read(file.path, limit: 16_384, secret: true)
		guard
			let text = String(data: data, encoding: .utf8)
		else { throw VisionFailure(.invalid_credentials, "Credential file must be UTF-8 dotenv text.") }
		var value: String?
		for raw in text.split(separator: "\n") {
			let line = raw.trimmingCharacters(in: .whitespacesAndNewlines)
			if line.isEmpty || line.hasPrefix("#") { continue }
			guard
				line.hasPrefix("GEMINI_API_KEY="),
				value == nil
			else {
				throw VisionFailure(
					.invalid_credentials,
					"Credential file must contain one GEMINI_API_KEY assignment; it is not executed as a shell script."
				)
			}
			var key = String(line.dropFirst("GEMINI_API_KEY=".count)).trimmingCharacters(in: .whitespaces)
			if (key.hasPrefix("\"") && key.hasSuffix("\"")) || (key.hasPrefix("'") && key.hasSuffix("'"))
			{
				key = String(key.dropFirst().dropLast())
			}
			value = key
		}
		guard
			let value
		else { throw VisionFailure(.missing_api_key, "Credential file has no GEMINI_API_KEY.") }
		return try checked(value, source: "env_file")
	}

	private static func checked(_ value: String, source: String) throws -> Self {
		guard
			(1...256).contains(value.utf8.count),
			value.range(of: #"^[A-Za-z0-9_-]+$"#, options: .regularExpression) != nil
		else {
			throw VisionFailure(
				.invalid_credentials, "API key has an invalid format; its value is not logged.")
		}
		return Self(value: value, source: source)
	}
}
