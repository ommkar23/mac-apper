// @frontmatter:start
// Audits first-request naming order and canonical results, and reads bounded nonlinked branding metadata.
// @frontmatter:end
import Darwin
import Foundation

private enum CreateNamingFailure: Error {
	case invocation, result, ordering, implementation, path, branding, notification
}

// This audit is for a single first Create request, not cumulative resumed-session history.
@discardableResult
func verifyCreateNaming(
	evidence: ScenarioToolEvidence, project: URL, expectedName: String
) throws -> String {
	let naming = evidence.calls.filter { $0.name == "set_app_name" }
	guard
		naming.count == 1,
		let call = naming.first,
		call.succeeded
	else { throw CreateNamingFailure.invocation }
	guard
		let result = call.typedResult,
		let name = result["name"] as? String,
		name == expectedName,
		!name.isEmpty,
		name != "Generated App",
		let summary = result["summary"] as? String,
		!summary.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
	else { throw CreateNamingFailure.result }
	var implemented = false
	for mutation in evidence.calls where ["write", "edit"].contains(mutation.name) {
		guard
			let path = mutation.arguments["path"] as? String
		else { throw CreateNamingFailure.path }
		let relative = try namingRelativePath(path, project: project)
		// Metadata edits cannot substitute for the provider's canonical mutation.
		guard
			relative != "Info.plist"
		else { throw CreateNamingFailure.branding }
		let implementation =
			relative.hasPrefix("Sources/") || relative.hasPrefix("Tests/")
			|| relative.hasPrefix("Resources/")
			|| ["Package.swift", "app-manifest.json"].contains(relative)
		if implementation {
			guard
				call.finished < mutation.started
			else { throw CreateNamingFailure.ordering }
			var file = stat()
			if mutation.succeeded,
				lstat(project.appendingPathComponent(relative).path, &file) == 0,
				(file.st_mode & S_IFMT) == S_IFREG, file.st_size > 0
			{
				implemented = true
			}
		}
	}
	guard
		implemented
	else { throw CreateNamingFailure.implementation }
	for operation in evidence.calls where ["build", "run"].contains(operation.name) {
		guard
			call.finished < operation.started
		else { throw CreateNamingFailure.ordering }
	}
	return name
}

// Validate components before URL normalization. Missing mutation leaves are allowed; existing links are not.
func namingRelativePath(_ path: String, project: URL) throws -> String {
	guard
		!path.isEmpty,
		path.utf8.count <= 4096,
		!path.contains("\\"),
		!path.contains("\0")
	else { throw CreateNamingFailure.path }
	let prefix = project.path + "/"
	let relative: String
	if path.hasPrefix("/") {
		guard
			path.hasPrefix(prefix)
		else { throw CreateNamingFailure.path }
		relative = String(path.dropFirst(prefix.count))
	} else {
		relative = path
	}
	guard
		relative.split(separator: "/", omittingEmptySubsequences: false)
			.allSatisfy({ !$0.isEmpty && $0 != "." && $0 != ".." })
	else { throw CreateNamingFailure.path }
	try requireNamingNonlinked(project.appendingPathComponent(relative))
	return relative
}

private func requireNamingNonlinked(_ url: URL) throws {
	var current = URL(fileURLWithPath: "/")
	for component in url.pathComponents.dropFirst() {
		current.appendPathComponent(component)
		var info = stat()
		if lstat(current.path, &info) != 0 {
			guard
				errno == ENOENT
			else { throw CreateNamingFailure.path }
			continue
		}
		guard
			(info.st_mode & S_IFMT) != S_IFLNK
		else { throw CreateNamingFailure.path }
	}
}

func verifyNamingPlist(_ url: URL, expectedName: String) throws {
	try requireNamingNonlinked(url)
	let descriptor = open(url.path, O_RDONLY | O_NOFOLLOW | O_NONBLOCK | O_CLOEXEC)
	guard
		descriptor >= 0
	else { throw CreateNamingFailure.branding }
	let handle = FileHandle(fileDescriptor: descriptor, closeOnDealloc: true)
	defer { try? handle.close() }
	var info = stat()
	guard
		fstat(descriptor, &info) == 0,
		(info.st_mode & S_IFMT) == S_IFREG,
		info.st_size > 0,
		info.st_size <= 65_536,
		let bytes = try handle.read(upToCount: 65_537),
		bytes.count <= 65_536,
		let plist = try PropertyListSerialization.propertyList(from: bytes, format: nil)
			as? [String: Any],
		plist["CFBundleDisplayName"] as? String == expectedName,
		plist["CFBundleName"] as? String == expectedName
	else { throw CreateNamingFailure.branding }
}

func verifyNoNativeNamingNotification(journal: Data) throws {
	guard
		journal.count <= 16_777_216
	else { throw CreateNamingFailure.notification }
	for line in journal.split(separator: 10) {
		guard
			let record = try JSONSerialization.jsonObject(with: Data(line)) as? [String: Any],
			let event = record["event"] as? [String: Any]
		else { throw CreateNamingFailure.notification }
		// Check notification events, not arbitrary assistant/script mentions or normal Run activity.
		if let notification = event["notification"] {
			let bytes = try JSONSerialization.data(
				withJSONObject: notification, options: [.fragmentsAllowed])
			guard
				!String(decoding: bytes, as: UTF8.self).contains("MAC_APPER_RENAMED:")
			else { throw CreateNamingFailure.notification }
		}
	}
}
