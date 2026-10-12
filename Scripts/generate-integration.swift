// @frontmatter:start
// Generates a bounded integration catalog from custom manifests and built-in OpenXPC specifications.
// @frontmatter:end
import Foundation

private enum GenerationError: Error, CustomStringConvertible {
	case invalid(String)
	var description: String {
		switch self {
		case .invalid(let message): return message
		}
	}
}

private struct YAMLLine {
	let number: Int
	let indent: Int
	let text: String
}

private struct YAMLDocument {
	let url: URL
	let lines: [YAMLLine]

	init(url: URL) throws {
		self.url = url
		let source = try String(contentsOf: url, encoding: .utf8)
		lines = source.split(separator: "\n", omittingEmptySubsequences: false).enumerated().compactMap
		{
			index, raw in
			let value = String(raw)
			let content = value.trimmingCharacters(in: .whitespaces)
			guard
				!content.isEmpty,
				!content.hasPrefix("#")
			else { return nil }
			let indent = value.prefix { $0 == " " }.count
			return YAMLLine(number: index + 1, indent: indent, text: content)
		}
	}

	func scalar(_ key: String, indent: Int = 0, within range: Range<Int>? = nil) throws -> String {
		let bounds = range ?? lines.indices
		guard
			let line = bounds.compactMap({ lines.indices.contains($0) ? lines[$0] : nil }).first(where: {
				$0.indent == indent && $0.text.hasPrefix(key + ":")
			})
		else { throw error("missing \(key)") }
		let value = String(line.text.dropFirst(key.count + 1)).trimmingCharacters(in: .whitespaces)
		guard
			!value.isEmpty
		else { throw error("\(key) must not be empty", line: line) }
		return unquote(value)
	}

	func optionalScalar(_ key: String, indent: Int = 0, within range: Range<Int>? = nil) throws
		-> String?
	{
		let bounds = range ?? lines.indices
		guard
			let line = bounds.compactMap({ lines.indices.contains($0) ? lines[$0] : nil }).first(where: {
				$0.indent == indent && $0.text.hasPrefix(key + ":")
			})
		else { return nil }
		let value = String(line.text.dropFirst(key.count + 1)).trimmingCharacters(in: .whitespaces)
		guard
			!value.isEmpty
		else { throw error("\(key) must not be empty", line: line) }
		return unquote(value)
	}

	func integer(_ key: String) throws -> Int {
		guard
			let value = Int(try scalar(key))
		else { throw error("\(key) must be an integer") }
		return value
	}

	func section(_ key: String) throws -> Range<Int> {
		guard
			let start = lines.firstIndex(where: { $0.indent == 0 && $0.text == key + ":" })
		else { throw error("missing \(key)") }
		let end = lines[(start + 1)...].firstIndex(where: { $0.indent == 0 }) ?? lines.endIndex
		return (start + 1)..<end
	}

	func array(_ key: String, indent: Int = 0, within range: Range<Int>? = nil) throws -> [String] {
		let value = try scalar(key, indent: indent, within: range)
		guard
			value.first == "[",
			value.last == "]"
		else { throw error("\(key) must be an inline array") }
		let body = value.dropFirst().dropLast().trimmingCharacters(in: .whitespaces)
		if body.isEmpty { return [] }
		let values = body.split(separator: ",").map { unquote($0.trimmingCharacters(in: .whitespaces)) }
		guard
			values.allSatisfy({ !$0.isEmpty })
		else { throw error("\(key) contains an empty value") }
		return values
	}

	func blockScalar(_ key: String) throws -> String {
		guard
			let start = lines.firstIndex(where: { $0.indent == 0 && $0.text == key + ": >-" })
		else { throw error("missing folded scalar \(key)") }
		let values = lines[(start + 1)...].prefix { $0.indent > 0 }.map(\.text)
		guard
			!values.isEmpty
		else { throw error("\(key) must not be empty") }
		return values.joined(separator: " ")
	}

	func listEntries(in range: Range<Int>) throws -> [(Range<Int>, YAMLLine)] {
		let starts = range.filter { lines[$0].indent == 2 && lines[$0].text.hasPrefix("- path:") }
		guard
			!starts.isEmpty
		else { throw error("pi_extensions must not be empty") }
		return starts.enumerated().map { offset, start in
			let end = offset + 1 < starts.count ? starts[offset + 1] : range.upperBound
			return (start..<end, lines[start])
		}
	}

	func validateKeys(
		indent: Int, within range: Range<Int>? = nil, allowed: Set<String>, listEntry: Bool = false
	) throws {
		let bounds = range ?? lines.indices
		for index in bounds where lines.indices.contains(index) && lines[index].indent == indent {
			let line = lines[index]
			var text = line.text
			if listEntry, text.hasPrefix("- ") { text.removeFirst(2) }
			guard
				let colon = text.firstIndex(of: ":")
			else { throw error("expected a mapping key", line: line) }
			let key = String(text[..<colon])
			guard
				allowed.contains(key)
			else { throw error("unknown field \(key)", line: line) }
		}
	}

	func error(_ message: String, line: YAMLLine? = nil) -> GenerationError {
		.invalid("\(url.path):\(line?.number ?? 1): \(message)")
	}

	private func unquote(_ value: String) -> String {
		guard
			value.count >= 2,
			(value.first == "\"" && value.last == "\"" || value.first == "'" && value.last == "'")
		else { return value }
		return String(value.dropFirst().dropLast())
	}
}

private struct IntegrationCatalog: Codable {
	let schemaVersion: Int
	let apps: [App]

	struct App: Codable {
		let id: String
		let displayName: String
		let packagePath: String
		let packageIdentity: String
		let application: Application
		let piExtensions: [PiExtension]
	}

	struct Application: Codable {
		let bundleName: String
		let executableProduct: String
		let serviceProduct: String?
		let serviceIdentifier: String?
		let xpcServicePlist: String?
		let infoPlist: String
		let registersProjects: Bool?
	}

	struct PiExtension: Codable {
		let path: String
		let agents: [String]
		let tools: [String]
		let firstRequestOnly: Bool
	}

}

private let identifierPattern = try NSRegularExpression(pattern: "^[a-z][a-z0-9-]{0,63}$")
private let toolPattern = try NSRegularExpression(pattern: "^[a-z][a-z0-9_-]{0,63}$")

private func validate(
	_ value: String, pattern: NSRegularExpression, field: String, document: YAMLDocument
) throws -> String {
	let range = NSRange(value.startIndex..., in: value)
	guard
		pattern.firstMatch(in: value, range: range)?.range == range
	else { throw document.error("\(field) has an invalid value") }
	return value
}

private func validateRelative(_ value: String, field: String, document: YAMLDocument) throws
	-> String
{
	let components = NSString(string: value).pathComponents
	guard
		!value.hasPrefix("/"),
		!components.contains(".."),
		!value.contains("\\"),
		!value.isEmpty
	else { throw document.error("\(field) must be a safe relative path") }
	return value
}

private func unique(_ values: [String], field: String, document: YAMLDocument) throws -> [String] {
	guard
		Set(values).count == values.count
	else { throw document.error("\(field) contains duplicates") }
	return values
}

private func loadApp(at url: URL, root: URL) throws -> IntegrationCatalog.App {
	let document = try YAMLDocument(url: url)
	try document.validateKeys(
		indent: 0,
		allowed: [
			"schema_version", "id", "display_name", "swift_package", "application", "pi_extensions",
		])
	guard
		try document.integer("schema_version") == 1
	else { throw document.error("unsupported schema_version") }
	let id = try validate(
		try document.scalar("id"), pattern: identifierPattern, field: "id", document: document)
	let package = try document.section("swift_package")
	let application = try document.section("application")
	try document.validateKeys(
		indent: 2, within: package,
		allowed: ["path", "identity"])
	try document.validateKeys(
		indent: 2, within: application,
		allowed: [
			"bundle_name", "executable_product", "service_product", "service_identifier",
			"xpc_service_plist", "info_plist", "registers_projects",
		])
	let packagePath = try validateRelative(
		try document.scalar("path", indent: 2, within: package), field: "swift_package.path",
		document: document)
	let packageURL = root.appendingPathComponent(packagePath, isDirectory: true).standardizedFileURL
	guard
		packageURL.path.hasPrefix(root.path + "/"),
		FileManager.default.fileExists(atPath: packageURL.appendingPathComponent("Package.swift").path)
	else { throw document.error("swift package is missing or outside the workspace") }
	let extensionSection = try document.section("pi_extensions")
	let serviceProduct = try document.optionalScalar(
		"service_product", indent: 2, within: application)
	let serviceIdentifier = try document.optionalScalar(
		"service_identifier", indent: 2, within: application)
	let xpcServicePlist = try document.optionalScalar(
		"xpc_service_plist", indent: 2, within: application)
	let registersProjectsValue = try document.optionalScalar(
		"registers_projects", indent: 2, within: application)
	let serviceFields = [serviceProduct, serviceIdentifier, xpcServicePlist]
	guard
		serviceFields.allSatisfy({ $0 == nil }) || serviceFields.allSatisfy({ $0 != nil })
	else {
		throw document.error(
			"service_product, service_identifier, and xpc_service_plist must be declared together")
	}
	if let value = registersProjectsValue, value != "true", value != "false" {
		throw document.error("registers_projects must be true or false")
	}
	let extensions: [IntegrationCatalog.PiExtension] = try document.listEntries(in: extensionSection)
		.map { range, first in
			try document.validateKeys(indent: 2, within: range, allowed: ["path"], listEntry: true)
			try document.validateKeys(
				indent: 4, within: range, allowed: ["agents", "tools", "first_request_only"])
			let path = try validateRelative(
				String(first.text.dropFirst("- path:".count)).trimmingCharacters(in: .whitespaces),
				field: "pi_extensions.path", document: document)
			let generated = ["OpenXPC.yaml", "OpenXPCGen.yaml"].allSatisfy { name in
				let values = try? packageURL.appendingPathComponent(name).resourceValues(
					forKeys: [.isRegularFileKey, .isSymbolicLinkKey])
				return values?.isRegularFile == true && values?.isSymbolicLink != true
			}
			guard
				FileManager.default.fileExists(atPath: packageURL.appendingPathComponent(path).path)
					|| (path == "PiExtension/Extension.ts" && serviceProduct != nil && generated)
			else { throw document.error("Pi extension is missing: \(path)", line: first) }
			let agents = try unique(
				try document.array("agents", indent: 4, within: range), field: "agents", document: document)
			let tools = try unique(
				try document.array("tools", indent: 4, within: range), field: "tools", document: document)
			for value in agents {
				_ = try validate(value, pattern: identifierPattern, field: "agent", document: document)
			}
			for value in tools {
				_ = try validate(value, pattern: toolPattern, field: "tool", document: document)
			}
			let firstRequestOnly =
				(try? document.scalar("first_request_only", indent: 4, within: range)) == "true"
			return .init(path: path, agents: agents, tools: tools, firstRequestOnly: firstRequestOnly)
		}
	return .init(
		id: id,
		displayName: try document.scalar("display_name"),
		packagePath: packagePath,
		packageIdentity: try validate(
			try document.scalar("identity", indent: 2, within: package), pattern: identifierPattern,
			field: "identity", document: document),
		application: .init(
			bundleName: try document.scalar("bundle_name", indent: 2, within: application),
			executableProduct: try document.scalar("executable_product", indent: 2, within: application),
			serviceProduct: serviceProduct,
			serviceIdentifier: serviceIdentifier,
			xpcServicePlist: try xpcServicePlist.map {
				try validateRelative($0, field: "xpc_service_plist", document: document)
			},
			infoPlist: try validateRelative(
				try document.scalar("info_plist", indent: 2, within: application), field: "info_plist",
				document: document),
			registersProjects: registersProjectsValue.map { $0 == "true" }),
		piExtensions: extensions)
}

private func loadBuiltInProvider(
	name: String, id: String, agents: [String], root: URL
) throws -> IntegrationCatalog.App {
	let packagePath = "apps/built-in/\(id)"
	let package = root.appendingPathComponent(packagePath, isDirectory: true)
	let document = try YAMLDocument(url: package.appendingPathComponent("OpenXPC.yaml"))
	let generation = try YAMLDocument(url: package.appendingPathComponent("OpenXPCGen.yaml"))
	let service = try document.section("service")
	let generatedService = try generation.section("service")
	let clients = try generation.section("clients")
	let operations = try document.section("operations")
	let serviceProduct = try generation.scalar("target", indent: 2, within: generatedService)
	let serviceIdentifier = try document.scalar("identifier", indent: 2, within: service)
	let clientProduct = try generation.scalar("- target", indent: 2, within: clients)
	let expectedClient = "DevToolsTerminalClient"
	guard
		serviceProduct == "\(name)Application",
		serviceIdentifier == "com.macapper.\(id).xpc",
		clientProduct == expectedClient,
		FileManager.default.fileExists(atPath: package.appendingPathComponent("Package.swift").path)
	else { throw document.error("\(name) OpenXPC service or client does not match its bundle") }
	let declaredOperations = try unique(
		operations.compactMap { index -> String? in
			let line = document.lines[index]
			guard
				line.indent == 2,
				line.text.hasPrefix("- name:")
			else { return nil }
			return String(line.text.dropFirst("- name:".count))
				.trimmingCharacters(in: .whitespaces)
		}, field: "operations", document: document)
	let tools = try unique(
		try generation.array("operations", indent: 4, within: clients),
		field: "client operations", document: generation)
	guard
		!tools.isEmpty,
		Set(tools).isSubset(of: Set(declaredOperations))
	else { throw document.error("\(name) client operations are missing or unknown") }
	for tool in tools {
		_ = try validate(tool, pattern: toolPattern, field: "operation", document: document)
	}
	for path in [
		"Resources/Info.plist", "Resources/\(name)XPCService-Info.plist",
	] {
		let values = try package.appendingPathComponent(path).resourceValues(
			forKeys: [.isRegularFileKey, .isSymbolicLinkKey])
		guard
			values.isRegularFile == true,
			values.isSymbolicLink != true
		else { throw document.error("\(name) bundle input is missing: \(path)") }
	}
	return .init(
		id: id, displayName: name, packagePath: packagePath,
		packageIdentity: id,
		application: .init(
			bundleName: "\(name).app", executableProduct: clientProduct,
			serviceProduct: serviceProduct, serviceIdentifier: serviceIdentifier,
			xpcServicePlist: "Resources/\(name)XPCService-Info.plist",
			infoPlist: "Resources/Info.plist", registersProjects: false),
		piExtensions: [
			.init(
				path: "PiExtension/Extension.ts", agents: agents, tools: tools,
				firstRequestOnly: false)
		])
}

private func manifestURLs(under root: URL, component: String) throws -> [URL] {
	let directory = root.appendingPathComponent(component, isDirectory: true)
	guard
		let children = try? FileManager.default.contentsOfDirectory(
			at: directory, includingPropertiesForKeys: [.isDirectoryKey], options: [.skipsHiddenFiles])
	else { return [] }
	return children.map { $0.appendingPathComponent("AppManifest.yaml") }
		.filter { FileManager.default.fileExists(atPath: $0.path) }.sorted { $0.path < $1.path }
}

private func run() throws {
	guard
		CommandLine.arguments.count == 2
	else { throw GenerationError.invalid("usage: generate-integration.swift OUTPUT_DIRECTORY") }
	let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
		.standardizedFileURL
	let generated = URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true)
		.standardizedFileURL
	let appURLs = try manifestURLs(under: root, component: "apps/custom")
	let apps =
		try appURLs.map { try loadApp(at: $0, root: root) }
		+ [
			loadBuiltInProvider(name: "DevTools", id: "dev-tools", agents: ["create"], root: root)
		]
	guard
		Set(apps.map(\.id)).count == apps.count
	else { throw GenerationError.invalid("duplicate app ids") }
	let agents = ["chat", "create"]
	let agentSet = Set(agents)
	for app in apps {
		for entry in app.piExtensions {
			let unknown = Set(entry.agents).subtracting(agentSet)
			guard
				unknown.isEmpty
			else {
				throw GenerationError.invalid(
					"app \(app.id) references unknown agents: \(unknown.sorted())")
			}
		}
	}

	try FileManager.default.createDirectory(at: generated, withIntermediateDirectories: true)
	let encoder = JSONEncoder()
	encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
	try encoder.encode(IntegrationCatalog(schemaVersion: 1, apps: apps))
		.write(to: generated.appendingPathComponent("IntegrationCatalog.json"), options: .atomic)

	print(
		"Generated \(apps.count) app integrations for \(agents.count) built-in agents."
	)
}

do {
	try run()
} catch {
	FileHandle.standardError.write(Data("generate-integration: \(error)\n".utf8))
	exit(1)
}
