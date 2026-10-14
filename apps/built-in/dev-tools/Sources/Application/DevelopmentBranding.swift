// @frontmatter:start
// Reads bounded nonlinked development branding and sanitizes full-length bundle display names.
// @frontmatter:end
import Darwin
import Foundation

struct DevelopmentBranding: Sendable {
	static let maximumPlistBytes = 16_384
	let name: String

	static func load(scope: ProjectScope, fallback: String) throws -> Self {
		let url = try scope.resolve("Info.plist")
		let descriptor = open(url.path, O_RDONLY | O_NOFOLLOW | O_NONBLOCK | O_CLOEXEC)
		guard
			descriptor >= 0
		else {
			if errno == ENOENT { return Self(name: fallback) }
			throw DevelopmentLaunchError.invalidBranding
		}
		defer { close(descriptor) }
		var status = stat()
		guard
			fstat(descriptor, &status) == 0,
			(status.st_mode & S_IFMT) == S_IFREG,
			status.st_size > 0,
			status.st_size <= maximumPlistBytes
		else { throw DevelopmentLaunchError.invalidBranding }
		var data = Data()
		var buffer = [UInt8](repeating: 0, count: 4_096)
		while true {
			let count = Darwin.read(descriptor, &buffer, buffer.count)
			if count < 0 && errno == EINTR { continue }
			guard
				count >= 0,
				data.count + count <= maximumPlistBytes
			else { throw DevelopmentLaunchError.invalidBranding }
			if count == 0 { break }
			data.append(contentsOf: buffer.prefix(count))
		}
		guard
			let plist = try? PropertyListSerialization.propertyList(
				from: data, options: [], format: nil) as? [String: Any]
		else { throw DevelopmentLaunchError.invalidBranding }
		var names: [String: String] = [:]
		for key in ["CFBundleDisplayName", "CFBundleName"] {
			if let value = plist[key] {
				guard
					let raw = value as? String
				else { throw DevelopmentLaunchError.invalidBranding }
				names[key] = try sanitize(raw)
			}
		}
		guard
			let name = names["CFBundleDisplayName"] ?? names["CFBundleName"]
		else { throw DevelopmentLaunchError.invalidBranding }
		return Self(name: name)
	}

	private static func sanitize(_ input: String) throws -> String {
		let cleaned = input.unicodeScalars.map { scalar -> Character in
			if CharacterSet.controlCharacters.contains(scalar)
				|| scalar == "/" || scalar == ":" || scalar == "\\"
			{
				return " "
			}
			return Character(scalar)
		}
		var name = String(cleaned).split(whereSeparator: { $0.isWhitespace }).joined(separator: " ")
		while name.lowercased().hasSuffix(".app") {
			name.removeLast(4)
			name = name.trimmingCharacters(in: .whitespacesAndNewlines)
		}
		guard
			!name.isEmpty,
			!name.hasPrefix("."),
			name.count <= 64
		else { throw DevelopmentLaunchError.invalidBranding }
		return name
	}
}
