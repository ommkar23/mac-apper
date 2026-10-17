// @frontmatter:start
// Rejects unsafe and oversized HTView resource staging and checks prompt and observer-only host contracts offline.
// @frontmatter:end
import Foundation
import Scenario
import Testing

@Test func htViewPromptAndObserverContractOffline() throws {
	let directory = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
	for name in [
		"CreateHTViewTests.swift", "HTViewEvidenceTests.swift", "CreateHTViewContractTests.swift",
	] {
		#expect(FileManager.default.fileExists(atPath: directory.appendingPathComponent(name).path))
	}
	let declaration = try String(
		contentsOf: directory.appendingPathComponent("CreateHTViewTests.swift"), encoding: .utf8)
	#expect(declaration.contains("makeCollection: createHTViewCollection"))
	for required in [
		"self-contained UTF-8 HTML", "openDocument(_ url: URL)", "documentURL: URL?",
		"errorMessage: String?", "isLoading: Bool", "same document action",
		"not a multi-file web project", "app-specific functional XPC",
		"user-visible app name must be HTView", "main window title must be HTView",
		"ProductionApp", "document title is not the main window title",
	] {
		#expect(htViewCreatePrompt.contains(required))
	}
	for forbidden in [
		"actual app metadata", "window evidence", "actual window title evidence",
	] {
		#expect(!htViewCreatePrompt.contains(forbidden))
	}
	#expect(htViewWebKitHostSource.contains("model.openDocument(file)"))
	#expect(htViewWebKitHostSource.contains("model.openDocument(file.deletingLastPathComponent()"))
	for forbidden in [
		".navigationDelegate =", ".loadFileURL(", ".loadHTMLString(", "WKWebView(frame:",
		"compileContentRuleList(",
	] {
		#expect(!htViewWebKitHostSource.contains(forbidden))
	}
}

// These are synthetic strings only. Never construct filesystem URLs from the alias spellings.
@Test func htViewResourceRelativePathOffline() throws {
	let module = "/tmp/htview-string-only/Sources/AppModel"
	let entry = "/private/tmp/htview-string-only/Sources/AppModel/example.html"
	#expect(String(entry.dropFirst(module.count + 1)) == "ppModel/example.html")
	let relative = try? htViewResourceRelativePath(modulePath: module, filePath: entry)
	// The wired old slice returns ppModel/example.html and fails this unchanged assertion.
	#expect(relative == nil || relative == "example.html")
}

@Test(arguments: ["AppModel", "AppViews"])
func htViewResourceRelativePathConsistentOffline(_ module: String) throws {
	let base = "/owned/project/Sources/" + module
	for relative in ["example.html", "Resources/日本語/café.html", "Nested/Model.swift"] {
		#expect(
			try htViewResourceRelativePath(modulePath: base, filePath: base + "/" + relative)
				== relative)
	}
}

@Test(arguments: [
	"reverse-spelling", "short-module-long-entry", "sibling", "outside", "module-itself",
	"dot", "traversal", "empty-component", "backslash", "nul", "relative-module",
	"relative-entry", "module-dot", "module-traversal",
])
func htViewResourceRelativePathRejectsUnsafeOffline(_ mutation: String) {
	var module = "/owned/project/Sources/AppModel"
	var entry = module + "/example.html"
	switch mutation {
	case "reverse-spelling":
		module = "/private/tmp/htview-string-only/Sources/AppModel"
		entry = "/tmp/htview-string-only/Sources/AppModel/example.html"
	case "short-module-long-entry":
		module = "/tmp/htview-string-only/Sources/AppModel"
		entry = "/private/tmp/htview-string-only/Sources/AppModel/example.html"
	case "sibling": entry = module + "Sibling/example.html"
	case "outside": entry = "/owned/other/Sources/AppModel/example.html"
	case "module-itself": entry = module
	case "dot": entry = module + "/./example.html"
	case "traversal": entry = module + "/Resources/../example.html"
	case "empty-component": entry = module + "//example.html"
	case "backslash": entry = module + "/Resources\\example.html"
	case "nul": entry = module + "/example\0.html"
	case "relative-module": module = "owned/project/Sources/AppModel"
	case "relative-entry": entry = "owned/project/Sources/AppModel/example.html"
	case "module-dot":
		module = "/owned/project/./Sources/AppModel"
		entry = module + "/example.html"
	case "module-traversal":
		module = "/owned/project/other/../Sources/AppModel"
		entry = module + "/example.html"
	default: Issue.record("Unknown relative-path control"); return
	}
	#expect(throws: (any Error).self) {
		try htViewResourceRelativePath(modulePath: module, filePath: entry)
	}
}

@Test(.serialized, arguments: ["process-root", "copy-root", "process-directory", "copy-directory"])
func htViewResourceStagingPreservesBytesOffline(_ fixture: String) throws {
	let manager = FileManager.default
	let root = try ProjectTemporaryDirectory.appending(
		"mac-apper-htview-resource-bytes-\(UUID().uuidString)")
	try manager.createDirectory(
		at: root, withIntermediateDirectories: false, attributes: [.posixPermissions: 0o700])
	defer { try? manager.removeItem(at: root) }
	let project = root.appendingPathComponent("project", isDirectory: true)
	let owned = root.appendingPathComponent("host", isDirectory: true)
	try manager.createDirectory(at: owned, withIntermediateDirectories: false)
	let rule = fixture.hasPrefix("process") ? "process" : "copy"
	let resourcePath = fixture.hasSuffix("root") ? "example.html" : "Resources"
	var expected: [String: Data] = [:]
	for module in ["AppModel", "AppViews"] {
		let directory = project.appendingPathComponent("Sources/" + module, isDirectory: true)
		try manager.createDirectory(at: directory, withIntermediateDirectories: true)
		let htmlPaths =
			resourcePath == "example.html"
			? ["example.html"] : ["Resources/example.html", "Resources/日本語/café.html"]
		for path in htmlPaths {
			// Preserve UTF-8, CRLF and trailing whitespace, not just a decoded HTML equivalent.
			let bytes = Data((HTViewHTMLFixture.html + "\r\n<!-- \(module)/\(path) café -->  \r\n").utf8)
			let source = directory.appendingPathComponent(path)
			try manager.createDirectory(
				at: source.deletingLastPathComponent(), withIntermediateDirectories: true)
			try bytes.write(to: source, options: .withoutOverwriting)
			expected[module + "/" + path] = bytes
		}
		for path in ["Source.swift", "Nested/日本語.swift"] {
			let bytes = Data("// \(module): café\r\nstruct Fixture {}  \r\n".utf8)
			let source = directory.appendingPathComponent(path)
			try manager.createDirectory(
				at: source.deletingLastPathComponent(), withIntermediateDirectories: true)
			try bytes.write(to: source, options: .withoutOverwriting)
			expected[module + "/" + path] = bytes
		}
	}
	try """
	// swift-tools-version: 6.0
	import PackageDescription
	let package = Package(name: "BytePreservation", targets: [
	    .target(name: "AppModel", resources: [.\(rule)(\(String(reflecting: resourcePath)))]),
	    .target(name: "AppViews", resources: [.\(rule)(\(String(reflecting: resourcePath)))])])
	""".write(to: project.appendingPathComponent("Package.swift"), atomically: true, encoding: .utf8)
	let declarations = try htViewDeclaredResources(project: project, owned: owned)
	for module in ["AppModel", "AppViews"] {
		let declaration = try #require(declarations[module]?.first)
		#expect(declarations[module]?.count == 1)
		#expect(declaration.path == resourcePath)
		#expect(declaration.rule == rule)
		#expect(declaration.manifest == ".\(rule)(\(String(reflecting: resourcePath)))")
	}
	let sources = try copyHTViewGeneratedSources(
		project: project, owned: owned, resources: declarations)
	#expect(sources.isFileURL)
	#expect(sources.pathComponents == owned.appendingPathComponent("Sources").pathComponents)
	for (relative, bytes) in expected {
		#expect(try Data(contentsOf: sources.appendingPathComponent(relative)) == bytes)
	}
	let enumerator = try #require(
		manager.enumerator(at: sources, includingPropertiesForKeys: [.isRegularFileKey]))
	var fileCount = 0
	for case let file as URL in enumerator {
		if try file.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile == true {
			fileCount += 1
		}
	}
	#expect(fileCount == expected.count)
}

@Test(arguments: [
	"file-link", "directory-link", "module-link", "project-link", "sources-link", "ancestor-link",
	"oversized-file", "oversized-total", "oversized-inventory", "undeclared", "declaration-sibling",
])
func htViewResourceStagingRejectsUnsafeOffline(_ mutation: String) throws {
	let manager = FileManager.default
	let root = try ProjectTemporaryDirectory.appending(
		"mac-apper-htview-resources-\(UUID().uuidString)")
	try manager.createDirectory(
		at: root, withIntermediateDirectories: false, attributes: [.posixPermissions: 0o700])
	defer { try? manager.removeItem(at: root) }
	var project = root.appendingPathComponent("project")
	let owned = root.appendingPathComponent("host")
	let model = project.appendingPathComponent("Sources/AppModel")
	let resources = model.appendingPathComponent("Resources")
	try manager.createDirectory(at: resources, withIntermediateDirectories: true)
	try manager.createDirectory(
		at: project.appendingPathComponent("Sources/AppViews"), withIntermediateDirectories: true)
	try manager.createDirectory(at: owned, withIntermediateDirectories: false)
	let file = resources.appendingPathComponent("example.html")
	try Data(HTViewHTMLFixture.html.utf8).write(to: file)
	let declarations = ["AppModel": [HTViewResource(path: "Resources", rule: "process")]]
	var expected = ""
	switch mutation {
	case "file-link", "directory-link", "module-link", "project-link", "sources-link":
		let original: URL
		switch mutation {
		case "file-link": original = file
		case "directory-link": original = resources
		case "module-link": original = model
		case "project-link": original = project
		default: original = project.appendingPathComponent("Sources")
		}
		let target = root.appendingPathComponent("target")
		try manager.moveItem(at: original, to: target)
		try manager.createSymbolicLink(at: original, withDestinationURL: target)
		expected =
			["module-link", "project-link", "sources-link"].contains(mutation) ? "linked" : "Unsafe"
	case "ancestor-link":
		let ancestor = root.appendingPathComponent("ancestor", isDirectory: true)
		try manager.createDirectory(at: ancestor, withIntermediateDirectories: false)
		try manager.moveItem(at: project, to: ancestor.appendingPathComponent("project"))
		let alias = root.appendingPathComponent("alias", isDirectory: true)
		try manager.createSymbolicLink(at: alias, withDestinationURL: ancestor)
		project = alias.appendingPathComponent("project", isDirectory: true)
		expected = ""
	case "declaration-sibling":
		let sibling = model.appendingPathComponent("ResourcesSibling", isDirectory: true)
		try manager.createDirectory(at: sibling, withIntermediateDirectories: false)
		try Data(HTViewHTMLFixture.html.utf8).write(to: sibling.appendingPathComponent("example.html"))
		expected = "Undeclared"
	case "oversized-file":
		try Data(repeating: 32, count: 262145).write(to: file)
		expected = "oversized"
	case "oversized-total":
		for index in 0..<9 {
			try Data(repeating: 32, count: 262144).write(
				to: resources.appendingPathComponent("\(index).html"))
		}
		expected = "bound exceeded"
	case "oversized-inventory":
		for index in 0..<256 {
			try Data().write(to: resources.appendingPathComponent("\(index).html"))
		}
		expected = "oversized"
	case "undeclared":
		try Data().write(to: model.appendingPathComponent("unexpected.html"))
		expected = "Undeclared"
	default: throw ScenarioFailure.message("Unknown resource control")
	}
	var rejection: String?
	do {
		_ = try copyHTViewGeneratedSources(project: project, owned: owned, resources: declarations)
	} catch { rejection = String(describing: error) }
	let message = try #require(rejection)
	if mutation == "ancestor-link" {
		#expect(!message.isEmpty)
	} else {
		#expect(message.contains(expected))
	}
}

@Test(
	.serialized,
	arguments: [
		"../escape", "/absolute", "Resources/../../escape", "../../escape", "Resources\\escape",
	])
func htViewResourceDeclarationRejectsEscapesOffline(_ path: String) throws {
	let manager = FileManager.default
	let root = try ProjectTemporaryDirectory.appending(
		"mac-apper-htview-declarations-\(UUID().uuidString)")
	try manager.createDirectory(
		at: root, withIntermediateDirectories: false, attributes: [.posixPermissions: 0o700])
	defer { try? manager.removeItem(at: root) }
	let project = root.appendingPathComponent("project")
	let owned = root.appendingPathComponent("host")
	for module in ["AppModel", "AppViews"] {
		try manager.createDirectory(
			at: project.appendingPathComponent("Sources/" + module), withIntermediateDirectories: true)
	}
	try manager.createDirectory(at: owned, withIntermediateDirectories: false)
	try """
	// swift-tools-version: 6.0
	import PackageDescription
	let package = Package(name: "EscapeControl", targets: [
	    .target(name: "AppModel", resources: [.process(\(String(reflecting: path)))]),
	    .target(name: "AppViews")])
	""".write(to: project.appendingPathComponent("Package.swift"), atomically: true, encoding: .utf8)
	var rejection: String?
	do { _ = try htViewDeclaredResources(project: project, owned: owned) } catch {
		rejection = String(describing: error)
	}
	#expect(try #require(rejection).contains("resource path escape"))
}
