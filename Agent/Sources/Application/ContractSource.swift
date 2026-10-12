// @frontmatter:start
// Loads bundled preview and development contract sources and builds app manifest JSON.
// @frontmatter:end
import Foundation

public enum ContractSource {
	public static var text: String {
		get throws {
			try String(
				contentsOf: Bundle.module.url(forResource: "PreviewProtocol", withExtension: "swift")!,
				encoding: .utf8)
		}
	}

	public static var developmentFiles: [String: String] {
		get throws {
			let names = ["GeneratedAppXPCService"]
			var files: [String: String] = [:]
			for name in names {
				guard
					let url = Bundle.module.url(
						forResource: name, withExtension: "swift.txt", subdirectory: "DevExtension")
				else { throw CocoaError(.fileNoSuchFile) }
				files["Sources/DevExtension/\(name).swift"] = try String(
					contentsOf: url, encoding: .utf8)
			}
			return files
		}
	}

	public static func appManifest(appID: String) throws -> String {
		guard
			appID == appID.lowercased(),
			UUID(uuidString: appID) != nil
		else { throw CocoaError(.coderInvalidValue) }
		return
			#"{"schemaVersion":1,"appID":"\#(appID)","executableTarget":"ProductionApp","previewTarget":"PreviewApp","devServiceID":"com.macapper.generated.\#(appID)"}"#
	}
}
