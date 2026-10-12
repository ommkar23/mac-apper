// @frontmatter:start
// Tests strict project manifest decoding and build-target validation.
// @frontmatter:end
import Foundation
import Testing

@testable import DevToolsApplication

private let appID = "F43B9B04-45CA-4BCC-AB27-E8D607DF3535"
func manifest(target: String = "GeneratedApp", version: Int = 1, extra: String = "") -> Data {
	Data(
		"""
		{"schemaVersion":\(version),"appID":"\(appID)","executableTarget":"\(target)","previewTarget":"PreviewApp","devServiceID":"com.macapper.generated.\(appID.lowercased())"\(extra)}
		""".utf8)
}

@Test func manifestRoundTrips() throws {
	let value = try ProjectManifest.decode(manifest())
	#expect(value.executableTarget == "GeneratedApp")

	#expect(try ProjectManifest.decode(JSONEncoder().encode(value)).appID == appID)
}

@Test(arguments: ["../outside", "/tmp/app", "a/b", "--help", "", "a b", "a\\\\b"])
func unsafeTargetsAreRejected(target: String) {
	#expect(throws: (any Error).self) { try ProjectManifest.decode(manifest(target: target)) }
}

@Test func manifestRejectsUnknownFieldsAndVersions() {
	#expect(throws: (any Error).self) { try ProjectManifest.decode(manifest(version: 2)) }
	#expect(throws: (any Error).self) {
		try ProjectManifest.decode(manifest(extra: ",\"root\":\"/tmp\""))
	}
	let data = Data(
		String(decoding: manifest(), as: UTF8.self)
			.replacingOccurrences(of: "com.macapper.generated.", with: "other.").utf8)
	#expect(throws: (any Error).self) { try ProjectManifest.decode(data) }
}
