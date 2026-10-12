// @frontmatter:start
// Checks that production transport code does not claim peer authentication.
// @frontmatter:end
import Foundation
import Testing

@Test func productionTransportDoesNotAuthenticatePeers() throws {
	let packageRoot = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
		.deletingLastPathComponent().deletingLastPathComponent()
	for path in [
		"Sources/Application/main.swift",
		"Sources/Application/Controllers/ControllerFactory.swift",
		"Sources/Application/ProjectResolver.swift",
	] {
		let source = try String(contentsOf: packageRoot.appendingPathComponent(path), encoding: .utf8)
		for forbidden in [
			"setCodeSigningRequirement", "SecStaticCode", "effectiveUserIdentifier", "Requirement.txt",
		] {
			#expect(!source.contains(forbidden), "\(path) retains \(forbidden)")
		}
	}
}
