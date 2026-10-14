// @frontmatter:start
// Builds a private native host of generated AppViews/AppModel and checks the embedded WebKit engine against a local HTML fixture.
// @frontmatter:end
import Darwin
import Foundation
import Scenario

struct HTViewWebKitEvidence: Codable {
	let title: String
	let color: String
	let marker: String
	let clicked: Bool
	let rendered: Bool
	let fileURL: String
}

func validateHTViewWebKitEvidence(_ data: Data, fixture: URL) throws {
	guard
		data.count <= 8192,
		htViewEvidenceHasExactFields(data),
		let evidence = try? JSONDecoder().decode(HTViewWebKitEvidence.self, from: data),
		evidence.title == HTViewHTMLFixture.title,
		evidence.color == HTViewHTMLFixture.expectedColor,
		evidence.marker == HTViewHTMLFixture.scriptMarker,
		evidence.clicked,
		evidence.rendered,
		URL(string: evidence.fileURL)?.standardizedFileURL == fixture.standardizedFileURL
	else {
		throw ScenarioFailure.message("Embedded WebKit fixture assertions failed or evidence malformed")
	}
}

// The evidence contract is one flat object with string and Boolean values only.
// Check decoded keys before Codable can discard unknown fields or collapse duplicate keys.
private func htViewEvidenceHasExactFields(_ data: Data) -> Bool {
	let bytes = Array(data)
	let strings: Set<String> = ["title", "color", "marker", "fileURL"]
	let booleans: Set<String> = ["clicked", "rendered"]
	let expected = strings.union(booleans)
	var index = 0
	var seen: Set<String> = []
	func whitespace() {
		while index < bytes.count && [9, 10, 13, 32].contains(bytes[index]) { index += 1 }
	}
	func consume(_ byte: UInt8) -> Bool {
		whitespace()
		guard
			index < bytes.count,
			bytes[index] == byte
		else { return false }
		index += 1
		return true
	}
	func string() -> String? {
		whitespace()
		let start = index
		guard
			index < bytes.count,
			bytes[index] == 34
		else { return nil }
		index += 1
		while index < bytes.count {
			let byte = bytes[index]
			index += 1
			if byte == 34 {
				return try? JSONDecoder().decode(String.self, from: Data(bytes[start..<index]))
			}
			if byte == 92 {
				guard
					index < bytes.count
				else { return nil }
				index += 1
			}
		}
		return nil
	}
	guard
		consume(123)
	else { return false }
	repeat {
		guard
			let key = string(),
			expected.contains(key),
			seen.insert(key).inserted,
			consume(58)
		else { return false }
		if strings.contains(key) {
			guard
				string() != nil
			else { return false }
		} else {
			whitespace()
			let start = index
			while index < bytes.count && (97...122).contains(bytes[index]) { index += 1 }
			let value = String(decoding: bytes[start..<index], as: UTF8.self)
			guard
				value == "true" || value == "false"
			else { return false }
		}
		if consume(125) {
			whitespace()
			return index == bytes.count && seen == expected
		}
		guard
			consume(44)
		else { return false }
	} while index < bytes.count
	return false
}

struct HTViewResource {
	let path: String
	let rule: String
	var manifest: String { ".\(rule)(\(String(reflecting: path)))" }
}

// SwiftPM processes resources and generates Bundle.module from a bounded manifest copy.
func htViewDeclaredResources(project: URL, owned: URL) throws -> [String: [HTViewResource]] {
	let manager = FileManager.default
	for directory in [
		project, project.appendingPathComponent("Sources"),
		project.appendingPathComponent("Sources/AppModel"),
		project.appendingPathComponent("Sources/AppViews"),
	] {
		let metadata = try directory.resourceValues(forKeys: [.isDirectoryKey, .isSymbolicLinkKey])
		guard
			metadata.isDirectory == true,
			metadata.isSymbolicLink == false
		else { throw ScenarioFailure.message("Missing or linked HTView module directory") }
	}
	let manifest = project.appendingPathComponent("Package.swift")
	let metadata = try manifest.resourceValues(forKeys: [
		.isRegularFileKey, .isSymbolicLinkKey, .fileSizeKey,
	])
	guard
		metadata.isRegularFile == true,
		metadata.isSymbolicLink == false,
		(metadata.fileSize ?? Int.max) <= 65536
	else { throw ScenarioFailure.message("Missing, linked or oversized HTView Package.swift") }
	let staging = owned.appendingPathComponent("manifest")
	try manager.createDirectory(at: staging, withIntermediateDirectories: false)
	let handle = try FileHandle(forReadingFrom: manifest)
	defer { try? handle.close() }
	let data = try handle.read(upToCount: 65537) ?? Data()
	guard
		data.count <= 65536,
		(try handle.read(upToCount: 1) ?? Data()).isEmpty
	else { throw ScenarioFailure.message("HTView manifest read exceeded bound") }
	try data.write(to: staging.appendingPathComponent("Package.swift"), options: .withoutOverwriting)
	let swift = try SwiftToolchain.executable("swift")
	let dump = try htViewCommand(
		swift, ["package", "--package-path", staging.path, "dump-package"], timeout: 30)
	if dump.status != 0 && dump.output.contains("invalid relative path") {
		throw ScenarioFailure.message(
			"HTView resource path escape rejected by SwiftPM; see command log")
	}
	guard
		dump.status == 0,
		let package = try JSONSerialization.jsonObject(with: Data(dump.output.utf8)) as? [String: Any],
		package["defaultLocalization"] is NSNull,
		let targets = package["targets"] as? [[String: Any]]
	else {
		throw ScenarioFailure.message(
			"HTView manifest unavailable or localized package unsupported; see command log")
	}
	var result: [String: [HTViewResource]] = [:]
	for module in ["AppModel", "AppViews"] {
		let matches = targets.filter { $0["name"] as? String == module }
		guard
			matches.count == 1,
			let target = matches.first,
			target["path"] == nil || target["path"] as? String == "Sources/" + module,
			(target["exclude"] as? [String])?.isEmpty == true,
			target["sources"] == nil,
			(target["settings"] as? [[String: Any]])?.isEmpty == true,
			target["pluginUsages"] == nil || (target["pluginUsages"] as? [Any])?.isEmpty == true,
			let declarations = target["resources"] as? [[String: Any]],
			declarations.count <= 32
		else {
			throw ScenarioFailure.message(
				"Unsupported HTView module path, exclusions, source selection, settings, plugins or resource inventory: \(module)"
			)
		}
		var resources: [HTViewResource] = []
		for declaration in declarations {
			guard
				let path = declaration["path"] as? String,
				path.utf8.count <= 1024,
				let rules = declaration["rule"] as? [String: Any],
				rules.count == 1,
				let rule = rules.keys.first,
				["process", "copy"].contains(rule),
				let options = rules[rule] as? [String: Any],
				options.isEmpty
			else { throw ScenarioFailure.message("Unsupported HTView resource declaration: \(module)") }
			let parts = path.split(separator: "/", omittingEmptySubsequences: false)
			guard
				!parts.isEmpty,
				parts.allSatisfy({
					!$0.isEmpty && $0 != "." && $0 != ".." && !$0.contains("\\") && !$0.contains("\0")
				})
			else { throw ScenarioFailure.message("HTView resource path escape: \(module)") }
			var file = project.appendingPathComponent("Sources/" + module)
			for part in parts {
				file.appendPathComponent(String(part))
				guard
					try file.resourceValues(forKeys: [.isSymbolicLinkKey]).isSymbolicLink == false
				else { throw ScenarioFailure.message("Linked HTView resource path: \(module)/\(path)") }
			}
			resources.append(HTViewResource(path: path, rule: rule))
		}
		result[module] = resources
	}
	return result
}

// Paths must already have the same validated representation; this helper performs no I/O.
func htViewResourceRelativePath(modulePath: String, filePath: String) throws -> String {
	let module = try htViewAbsolutePathComponents(modulePath)
	let file = try htViewAbsolutePathComponents(filePath)
	guard
		file.count > module.count,
		file.starts(with: module)
	else { throw ScenarioFailure.message("HTView resource relative path is outside its module") }
	return file.dropFirst(module.count).joined(separator: "/")
}

private func htViewAbsolutePathComponents(_ path: String) throws -> [String] {
	guard
		path.hasPrefix("/"),
		!path.contains("\\"),
		!path.contains("\0")
	else { throw ScenarioFailure.message("Unsafe HTView resource absolute path") }
	let parts = path.dropFirst().split(separator: "/", omittingEmptySubsequences: false).map(
		String.init)
	guard
		!parts.isEmpty,
		parts.allSatisfy({ !$0.isEmpty && $0 != "." && $0 != ".." })
	else { throw ScenarioFailure.message("Unsafe HTView resource path components") }
	return parts
}

private struct HTViewPhysicalInput {
	let descriptor: Int32
	let path: String
	let metadata: stat
}

// Strict physical .tmp inputs only: never resolve aliases or follow original ancestor links.
// The caller owns the returned descriptor; all rejected traversals close their descriptors here.
private func htViewOpenPhysicalInput(_ path: String, directory: Bool) throws -> HTViewPhysicalInput
{
	let temporaryPath = ProjectTemporaryDirectory.repositoryRoot.appendingPathComponent(".tmp").path
	_ = try htViewResourceRelativePath(modulePath: temporaryPath, filePath: path)
	let parts = try htViewAbsolutePathComponents(path)
	let temporaryParts = try htViewAbsolutePathComponents(temporaryPath)
	var descriptor = open("/", O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC)
	guard
		descriptor >= 0
	else { throw ScenarioFailure.message("Cannot open physical HTView input root") }
	defer { if descriptor >= 0 { Darwin.close(descriptor) } }
	var info = stat()
	for (index, part) in parts.enumerated() {
		let requiresDirectory = index < parts.count - 1 || directory
		let flags = O_RDONLY | O_NOFOLLOW | O_NONBLOCK | O_CLOEXEC
		let next = openat(descriptor, part, flags | (requiresDirectory ? O_DIRECTORY : 0))
		guard
			next >= 0
		else { throw ScenarioFailure.message("Unsafe or linked generated source path") }
		Darwin.close(descriptor)
		descriptor = next
		guard
			fstat(descriptor, &info) == 0,
			requiresDirectory
				? info.st_mode & S_IFMT == S_IFDIR
				: (info.st_mode & S_IFMT == S_IFDIR || info.st_mode & S_IFMT == S_IFREG)
		else { throw ScenarioFailure.message("Unsupported generated resource file type") }
		if index == temporaryParts.count - 1 {
			guard
				info.st_uid == getuid(),
				info.st_mode & 0o077 == 0
			else { throw ScenarioFailure.message("Unsafe HTView repository temporary directory") }
		}
	}
	var canonical = [CChar](repeating: 0, count: Int(MAXPATHLEN))
	guard
		fcntl(descriptor, F_GETPATH, &canonical) == 0
	else { throw ScenarioFailure.message("Cannot identify physical HTView input path") }
	let canonicalPath = String(
		decoding: canonical.prefix { $0 != 0 }.map { UInt8(bitPattern: $0) }, as: UTF8.self)
	let result = HTViewPhysicalInput(
		descriptor: descriptor, path: canonicalPath, metadata: info)
	descriptor = -1
	return result
}

// DirectoryEnumerator.makeIterator is unavailable in Swift 6.4 async contexts.
// Keep enumeration and bounded copying synchronous; the caller owns scratch cleanup.
func copyHTViewGeneratedSources(
	project: URL, owned: URL, resources: [String: [HTViewResource]]
) throws -> URL {
	let manager = FileManager.default
	for directory in [project, project.appendingPathComponent("Sources"), owned] {
		let validated = try htViewOpenPhysicalInput(directory.path, directory: true)
		Darwin.close(validated.descriptor)
	}
	let sources = owned.appendingPathComponent("Sources")
	try manager.createDirectory(at: sources, withIntermediateDirectories: false)
	// Copy bounded, nonlinked Swift and declared resource inputs without rewriting app logic.
	for module in ["AppModel", "AppViews"] {
		let input = project.appendingPathComponent("Sources/" + module)
		let validatedModule = try htViewOpenPhysicalInput(input.path, directory: true)
		defer { Darwin.close(validatedModule.descriptor) }
		var traversalError: (any Error)?
		guard
			let enumerator = manager.enumerator(
				at: input,
				includingPropertiesForKeys: [.isSymbolicLinkKey, .isRegularFileKey, .fileSizeKey],
				options: [],
				errorHandler: { _, error in
					traversalError = error
					return false
				})
		else { throw ScenarioFailure.message("Missing or linked generated \(module) sources") }
		var count = 0, bytes = 0
		for case let file as URL in enumerator {
			count += 1
			guard
				count <= 256
			else { throw ScenarioFailure.message("Unsafe or oversized generated source tree") }
			let validated = try htViewOpenPhysicalInput(file.path, directory: false)
			let handle = FileHandle(fileDescriptor: validated.descriptor, closeOnDealloc: true)
			defer { try? handle.close() }
			let relative = try htViewResourceRelativePath(
				modulePath: validatedModule.path, filePath: validated.path)
			if validated.metadata.st_mode & S_IFMT == S_IFDIR { continue }
			let declared = (resources[module] ?? []).contains {
				relative == $0.path || relative.hasPrefix($0.path + "/")
			}
			guard
				file.pathExtension == "swift" || declared,
				let size = Int(exactly: validated.metadata.st_size),
				size >= 0,
				size <= 262144
			else {
				throw ScenarioFailure.message(
					"Undeclared or oversized generated module resource: \(module)/\(relative)")
			}
			bytes += size
			guard
				bytes <= 2097152
			else { throw ScenarioFailure.message("Generated module source bound exceeded") }
			let destination = sources.appendingPathComponent(module + "/" + relative)
			try manager.createDirectory(
				at: destination.deletingLastPathComponent(), withIntermediateDirectories: true)
			let data = try handle.read(upToCount: 262145) ?? Data()
			var current = stat()
			guard
				data.count == size,
				(try handle.read(upToCount: 1) ?? Data()).isEmpty,
				fstat(validated.descriptor, &current) == 0,
				current.st_mode & S_IFMT == S_IFREG,
				current.st_size == validated.metadata.st_size
			else { throw ScenarioFailure.message("Generated source changed or exceeded bounded read") }
			try data.write(to: destination, options: .withoutOverwriting)
		}
		if let traversalError { throw traversalError }
	}
	return sources
}

@MainActor func verifyHTViewWebKit(project: URL, compiler: SDKCompiler) async throws {
	let manager = FileManager.default
	let owned = try ProjectTemporaryDirectory.appending(
		"mac-apper-htview-webkit-\(UUID().uuidString)")
	try manager.createDirectory(
		at: owned, withIntermediateDirectories: false, attributes: [.posixPermissions: 0o700])
	var passed = false
	defer {
		if passed {
			try? manager.removeItem(at: owned)
		} else {
			print("HTVIEW_RETAINED_HOST: \(owned.path)")
		}
	}
	let resources = try htViewDeclaredResources(project: project, owned: owned)
	let sources = try copyHTViewGeneratedSources(project: project, owned: owned, resources: resources)
	let modelResources = (resources["AppModel"] ?? []).map(\.manifest).joined(separator: ", ")
	let viewResources = (resources["AppViews"] ?? []).map(\.manifest).joined(separator: ", ")
	try """
	// swift-tools-version: 6.0
	import PackageDescription
	let package = Package(name: "HTViewIndependentHost", platforms: [.macOS(.v14)], targets: [
	    .target(name: "AppModel", resources: [\(modelResources)]),
	    .target(name: "AppViews", dependencies: ["AppModel"], resources: [\(viewResources)]),
	    .executableTarget(name: "HTViewHost", dependencies: ["AppModel", "AppViews"])])
	""".write(to: owned.appendingPathComponent("Package.swift"), atomically: true, encoding: .utf8)
	let host = sources.appendingPathComponent("HTViewHost")
	try manager.createDirectory(at: host, withIntermediateDirectories: false)
	try htViewWebKitHostSource.write(
		to: host.appendingPathComponent("Host.swift"), atomically: true, encoding: .utf8)
	let fixture = owned.appendingPathComponent("fixture.html")
	guard
		HTViewHTMLFixture.html.utf8.count <= 65536
	else { throw ScenarioFailure.message("HTView HTML fixture exceeds bound") }
	try HTViewHTMLFixture.html.write(to: fixture, atomically: true, encoding: .utf8)
	let swift = try SwiftToolchain.executable("swift")
	guard
		compiler.executable == swift.deletingLastPathComponent().appendingPathComponent("swiftc")
	else {
		throw ScenarioFailure.message("HTView compiler must match standalone Swift Build toolchain")
	}
	let scratch = owned.appendingPathComponent("build")
	let arguments = [
		"build", "--package-path", owned.path, "--scratch-path", scratch.path,
		"--sdk", compiler.sdk.path, "-j", "2",
	]
	let build = try htViewCommand(swift, arguments + ["--product", "HTViewHost"])
	guard
		build.status == 0
	else {
		throw ScenarioFailure.message(
			"HTView native host failed to compile; missing prerequisites are not behavioral evidence")
	}
	let location = try htViewCommand(swift, arguments + ["--show-bin-path"], timeout: 15)
	guard
		location.status == 0,
		let path = location.output.split(separator: "\n").last,
		path.hasPrefix("/"),
		String(path).hasPrefix(scratch.path + "/")
	else { throw ScenarioFailure.message("HTView native host product location unavailable") }
	let resultFile = owned.appendingPathComponent("evidence.json")
	let home = owned.appendingPathComponent("home")
	try manager.createDirectory(
		at: home, withIntermediateDirectories: false, attributes: [.posixPermissions: 0o700])
	let run = try htViewCommand(
		URL(fileURLWithPath: String(path)).appendingPathComponent("HTViewHost"),
		[fixture.path, resultFile.path, HTViewHTMLFixture.scriptMarker], timeout: 45, home: home)
	guard
		run.status == 0,
		(try resultFile.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? Int.max) <= 8192
	else {
		throw ScenarioFailure.message("HTView embedded WebKit host failed; see bounded command log")
	}
	try validateHTViewWebKitEvidence(Data(contentsOf: resultFile), fixture: fixture)
	passed = true
	print("HTVIEW_WEBKIT: embedded engine title/DOM/CSS/load-script/scripted-button passed")
	print(
		"HTVIEW_DOCUMENT_ACTION: missing-file error and valid-file recovery passed through generated root/model"
	)
	print(
		"HTVIEW_LIMITATION: user picker, Safari parity, general navigation security and production delivery unverified"
	)
}

private struct HTViewCommandResult {
	let status: Int32
	let output: String
}

private func htViewCommand(
	_ executable: URL, _ arguments: [String], timeout: Int = 180, home: URL? = nil
) throws
	-> HTViewCommandResult
{
	let log = try ProjectTemporaryDirectory.appending(
		"mac-apper-htview-command-\(UUID().uuidString).log")
	try FileManager.default.createDirectory(
		at: log.deletingLastPathComponent(), withIntermediateDirectories: true)
	guard
		FileManager.default.createFile(
			atPath: log.path, contents: Data(), attributes: [.posixPermissions: 0o600])
	else { throw ScenarioFailure.message("Cannot create private HTView command log") }
	let handle = try FileHandle(forWritingTo: log)
	defer { try? handle.close() }
	let process = Process()
	process.executableURL = executable
	process.arguments = arguments
	var environment = ProcessInfo.processInfo.environment
	environment.removeValue(forKey: "SDKROOT")
	if executable.lastPathComponent == "swift" {
		environment["SWIFT_EXEC"] =
			executable.deletingLastPathComponent().appendingPathComponent("swiftc").path
	}
	if let home {
		environment["HOME"] = home.path
		environment["CFFIXED_USER_HOME"] = home.path
	}
	process.environment = environment
	process.standardInput = FileHandle.nullDevice
	process.standardOutput = handle
	process.standardError = handle
	try process.run()
	let identity = try OwnedProcessIdentity.capture(process.processIdentifier)
	do {
		let deadline = Date().addingTimeInterval(Double(timeout))
		while process.isRunning {
			try Task.checkCancellation()
			let limitFailure = "HTView command time/output bound exceeded: \(log.path)"
			guard
				Date() < deadline,
				(try log.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? Int.max) <= 4_194_304
			else { throw ScenarioFailure.message(limitFailure) }
			Thread.sleep(forTimeInterval: 0.05)
		}
		process.waitUntilExit()
		try identity.requireReaped()
	} catch {
		try identity.reap()
		process.waitUntilExit()
		try identity.requireReaped()
		throw error
	}
	guard
		(try log.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? Int.max) <= 4_194_304
	else { throw ScenarioFailure.message("Oversized HTView command output: \(log.path)") }
	let output = try String(contentsOf: log, encoding: .utf8)
	print(
		"HTVIEW_COMMAND: exit=\(process.terminationStatus) reaped log=\(log.path)\n\(output.suffix(2048))"
	)
	return HTViewCommandResult(status: process.terminationStatus, output: output)
}

let htViewWebKitHostSource = #"""
	import AppKit
	import SwiftUI
	import WebKit
	import AppModel
	import AppViews
	import Darwin

	@MainActor final class HTViewLayoutWindow: NSWindow {
	    override var canBecomeKey: Bool { false }
	    override var canBecomeMain: Bool { false }
	}
	@MainActor func embeddedWebViews(_ view: NSView) -> [WKWebView] {
	    (view as? WKWebView).map { [$0] } ?? view.subviews.flatMap { embeddedWebViews($0) }
	}
	@MainActor func evaluate(_ web: WKWebView, _ script: String) async throws -> String {
	    try await withCheckedThrowingContinuation { continuation in
	        web.evaluateJavaScript(script) { value, error in
	            if let error { continuation.resume(throwing: error) }
	            else if let value = value as? String { continuation.resume(returning: value) }
	            else { continuation.resume(throwing: NSError(domain: "HTViewInvalidDOM", code: 1)) }
	        }
	    }
	}
	@main struct HTViewHost {
	    @MainActor static func main() async {
	        do {
	            guard CommandLine.arguments.count == 4 else { throw NSError(domain: "HTViewArguments", code: 1) }
	            let file = URL(fileURLWithPath: CommandLine.arguments[1])
	            let output = URL(fileURLWithPath: CommandLine.arguments[2])
	            let home = file.deletingLastPathComponent().appendingPathComponent("home")
	            guard ProcessInfo.processInfo.environment["HOME"] == home.path,
	                  ProcessInfo.processInfo.environment["CFFIXED_USER_HOME"] == home.path else {
	                throw NSError(domain: "HTViewHostHomeNotScopedBeforeStartup", code: 1)
	            }
	            _ = NSApplication.shared
	            NSApp.setActivationPolicy(.prohibited)
	            let persistence = try ApplicationPersistence.inMemory()
	            defer { try? persistence.close() }
	            let model = ApplicationModel(persistence: persistence)
	            let root = NSHostingView(rootView: ApplicationRoot(model: model))
	            root.frame = NSRect(x: 0, y: 0, width: 800, height: 600)
	            // Match PreviewRenderer's off-desktop, non-key/non-main layout window mechanics.
	            // This is a live layout host, not a desktop capture or capture-fidelity guarantee.
	            let window = HTViewLayoutWindow(contentRect: root.frame,
	                                            styleMask: [.borderless], backing: .buffered, defer: false)
	            window.isReleasedWhenClosed = false
	            window.setFrameOrigin(NSPoint(x: -10000, y: -10000))
	            defer { window.orderOut(nil); window.contentView = nil; window.close() }
	            window.contentView = root
	            window.orderBack(nil)
	            model.openDocument(file.deletingLastPathComponent().appendingPathComponent("missing.html"))
	            let errorDeadline = Date().addingTimeInterval(3)
	            while (model.errorMessage ?? "").isEmpty && Date() < errorDeadline {
	                try await Task.sleep(for: .milliseconds(50))
	            }
	            guard !(model.errorMessage ?? "").isEmpty else { throw NSError(domain: "HTViewMissingFileErrorNotObservable", code: 1) }
	            model.openDocument(file)
	            let deadline = Date().addingTimeInterval(15)
	            var views: [WKWebView] = []
	            repeat {
	                root.layoutSubtreeIfNeeded()
	                views = embeddedWebViews(root)
	                if !views.isEmpty { break }
	                try await Task.sleep(for: .milliseconds(100))
	            } while Date() < deadline
	            guard views.count == 1, let web = views.first else { throw NSError(domain: "HTViewMissingOrAmbiguousEmbeddedWKWebView", code: 1) }
	            // Observe only. Generated navigation, preprocessing, rules and load lifecycle stay active.
	            defer { web.stopLoading() }
	            let markerJSON = String(data: try JSONEncoder().encode(CommandLine.arguments[3]), encoding: .utf8)!
	            var ready = false
	            repeat {
	                if let state = try? await evaluate(web, "String(document.readyState === 'complete' && document.getElementById('script-status')?.textContent === " + markerJSON + ")"), state == "true", !model.isLoading, (model.errorMessage ?? "").isEmpty {
	                    ready = true; break
	                }
	                try await Task.sleep(for: .milliseconds(100))
	            } while Date() < deadline
	            guard ready, !model.isLoading, (model.errorMessage ?? "").isEmpty else {
	                throw NSError(domain: "HTViewScriptOrLoadFailed: " + (model.errorMessage ?? "loading or script timeout"), code: 1)
	            }
	            let fileJSON = String(data: try JSONEncoder().encode(file.absoluteString), encoding: .utf8)!
	            let record = try await evaluate(web, """
	            (() => {
	                const styled = document.getElementById('inline-style');
	                const status = document.getElementById('script-status');
	                const button = document.getElementById('script-button');
	                if (!styled || !status || !button || document.querySelector('h1')?.textContent !== document.title) throw Error('missing fixture DOM');
	                const marker = status.textContent;
	                button.click();
	                const box = styled.getBoundingClientRect();
	                const css = getComputedStyle(styled);
	                return JSON.stringify({title: document.title, color: css.color, marker,
	                    clicked: status.textContent === marker + '-clicked',
	                    rendered: box.width > 0 && box.height > 0 && css.display !== 'none' && css.visibility === 'visible',
	                    fileURL: \(fileJSON)});
	            })()
	            """)
	            guard record.utf8.count <= 8192 else { throw NSError(domain: "HTViewOutputBound", code: 1) }
	            guard model.documentURL?.standardizedFileURL == file.standardizedFileURL else {
	                throw NSError(domain: "HTViewDocumentIdentityMismatch", code: 1)
	            }
	            try Data(record.utf8).write(to: output, options: .withoutOverwriting)
	        } catch {
	            FileHandle.standardError.write(Data("HTView host failed: \(error)\n".utf8))
	            exit(1)
	        }
	    }
	}
	"""#
