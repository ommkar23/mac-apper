// @frontmatter:start
// Builds, assembles, and signs provider applications inside the packaged host.
// @frontmatter:end
import Foundation

private enum PackagingError: Error, CustomStringConvertible {
	case usage
	case invalidCatalog
	case commandFailed(String, Int32)
	case unsafePath(String)

	var description: String {
		switch self {
		case .usage: return "usage: package-providers.swift ROOT BUILD_ROOT APP SIGNING_IDENTITY"
		case .invalidCatalog: return "integration catalog is invalid"
		case .commandFailed(let command, let status): return "\(command) failed with status \(status)"
		case .unsafePath(let path): return "unsafe manifest path: \(path)"
		}
	}
}

private struct Catalog: Decodable {
	struct App: Decodable {
		struct Application: Decodable {
			let bundleName: String
			let executableProduct: String
			let serviceProduct: String?
			let serviceIdentifier: String?
			let xpcServicePlist: String?
			let infoPlist: String
		}
		let id: String
		let packagePath: String
		let application: Application
	}
	let schemaVersion: Int
	let apps: [App]
}

private let swiftBin = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(
	"Library/Developer/Toolchains/swift-6.4.0-RELEASE.xctoolchain/usr/bin")

private func run(_ executable: String, _ arguments: [String], directory: URL? = nil) throws {
	let process = Process()
	process.executableURL = URL(fileURLWithPath: executable)
	process.arguments = arguments
	var environment = ProcessInfo.processInfo.environment
	environment["SWIFT_EXEC"] = swiftBin.appendingPathComponent("swiftc").path
	process.environment = environment
	process.currentDirectoryURL = directory
	process.standardOutput = FileHandle.standardOutput
	process.standardError = FileHandle.standardError
	try process.run()
	process.waitUntilExit()
	guard
		process.terminationStatus == 0
	else {
		throw PackagingError.commandFailed(
			([executable] + arguments).joined(separator: " "), process.terminationStatus)
	}
}

private func safe(_ relative: String, under root: URL) throws -> URL {
	guard
		!relative.hasPrefix("/"),
		!NSString(string: relative).pathComponents.contains(".."),
		!relative.contains("\\")
	else { throw PackagingError.unsafePath(relative) }
	let url = root.appendingPathComponent(relative).standardizedFileURL
	guard
		url.path.hasPrefix(root.standardizedFileURL.path + "/")
	else { throw PackagingError.unsafePath(relative) }
	return url
}

private func replaceCopy(_ source: URL, _ destination: URL) throws {
	let manager = FileManager.default
	if manager.fileExists(atPath: destination.path) { try manager.removeItem(at: destination) }
	try manager.copyItem(at: source, to: destination)
}

private func main() throws {
	guard
		CommandLine.arguments.count == 5
	else { throw PackagingError.usage }
	let root = URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true).standardizedFileURL
	let buildRoot = URL(fileURLWithPath: CommandLine.arguments[2], isDirectory: true)
		.standardizedFileURL
	let hostApp = URL(fileURLWithPath: CommandLine.arguments[3], isDirectory: true)
		.standardizedFileURL
	let identity = CommandLine.arguments[4]
	let catalogURL = buildRoot.appendingPathComponent("generated/IntegrationCatalog.json")
	let catalog = try JSONDecoder().decode(Catalog.self, from: Data(contentsOf: catalogURL))
	guard
		catalog.schemaVersion == 1
	else { throw PackagingError.invalidCatalog }
	let manager = FileManager.default

	for app in catalog.apps {
		let package = try safe(app.packagePath, under: root)
		let scratch = buildRoot.appendingPathComponent("provider-\(app.id)", isDirectory: true)
		try run(
			swiftBin.appendingPathComponent("swift").path,
			[
				"build", "--package-path", package.path, "-c", "release",
				"--scratch-path", scratch.path, "-j", "2",
			])

		let contents = hostApp.appendingPathComponent(
			"Contents/Applications/\(app.application.bundleName)/Contents", isDirectory: true)
		let macOS = contents.appendingPathComponent("MacOS", isDirectory: true)
		let resources = contents.appendingPathComponent("Resources", isDirectory: true)
		let xpcServices = contents.appendingPathComponent("XPCServices", isDirectory: true)
		try manager.createDirectory(at: macOS, withIntermediateDirectories: true)
		try manager.createDirectory(at: resources, withIntermediateDirectories: true)
		try manager.createDirectory(at: xpcServices, withIntermediateDirectories: true)

		let executable = macOS.appendingPathComponent(app.application.executableProduct)
		try replaceCopy(
			scratch.appendingPathComponent("release/\(app.application.executableProduct)"), executable)
		try replaceCopy(
			try safe(app.application.infoPlist, under: package),
			contents.appendingPathComponent("Info.plist"))
		let manifest = package.appendingPathComponent("AppManifest.yaml")
		if manager.fileExists(atPath: manifest.path) {
			try replaceCopy(manifest, resources.appendingPathComponent("AppManifest.yaml"))
		}
		let packagedExtensions = resources.appendingPathComponent("PiExtension", isDirectory: true)
		try manager.createDirectory(at: packagedExtensions, withIntermediateDirectories: true)
		try manager.setAttributes([.posixPermissions: 0o755], ofItemAtPath: executable.path)
		var plists = [contents.appendingPathComponent("Info.plist").path]
		if let serviceProduct = app.application.serviceProduct,
			let serviceIdentifier = app.application.serviceIdentifier,
			let xpcServicePlist = app.application.xpcServicePlist
		{
			guard
				serviceProduct.hasSuffix("Application")
			else { throw PackagingError.invalidCatalog }
			let appName = String(serviceProduct.dropLast("Application".count))
			let clientProduct =
				app.application.executableProduct.hasSuffix("AgentClient")
				? app.application.executableProduct : appName + "TerminalClient"
			let xpcContents = xpcServices.appendingPathComponent(
				"\(serviceProduct).xpc/Contents", isDirectory: true)
			let service = xpcContents.appendingPathComponent("MacOS/\(serviceProduct)")
			let client = macOS.appendingPathComponent(clientProduct)
			guard
				let extensionFile = Bundle(
					url: scratch.appendingPathComponent(
						"release/\(appName)_\(clientProduct).bundle"))?.url(
						forResource: "Extension", withExtension: "ts")
			else { throw PackagingError.invalidCatalog }
			let extensionValues = try extensionFile.resourceValues(forKeys: [
				.isRegularFileKey, .isSymbolicLinkKey, .fileSizeKey,
			])
			guard
				extensionValues.isRegularFile == true,
				extensionValues.isSymbolicLink != true,
				let size = extensionValues.fileSize,
				size <= 1_048_576
			else { throw PackagingError.invalidCatalog }
			let staged = buildRoot.appendingPathComponent(
				"generated/PiExtensions/\(app.id)/PiExtension/Extension.ts")
			try manager.createDirectory(
				at: staged.deletingLastPathComponent(), withIntermediateDirectories: true)
			try replaceCopy(extensionFile, staged)
			try replaceCopy(extensionFile, packagedExtensions.appendingPathComponent("Extension.ts"))
			try manager.createDirectory(
				at: service.deletingLastPathComponent(), withIntermediateDirectories: true)
			try replaceCopy(scratch.appendingPathComponent("release/\(serviceProduct)"), service)
			let serviceResources = scratch.appendingPathComponent(
				"release/\(appName)_\(serviceProduct).bundle")
			if manager.fileExists(atPath: serviceResources.path) {
				let destination = xpcContents.appendingPathComponent(
					"Resources/\(serviceResources.lastPathComponent)")
				try manager.createDirectory(
					at: destination.deletingLastPathComponent(), withIntermediateDirectories: true)
				try replaceCopy(serviceResources, destination)
			}
			if client != executable {
				try replaceCopy(scratch.appendingPathComponent("release/\(clientProduct)"), client)
			}
			let servicePlist = xpcContents.appendingPathComponent("Info.plist")
			try replaceCopy(try safe(xpcServicePlist, under: package), servicePlist)
			let bundledServiceID = serviceIdentifier
			try manager.setAttributes([.posixPermissions: 0o755], ofItemAtPath: service.path)
			try manager.setAttributes([.posixPermissions: 0o755], ofItemAtPath: client.path)
			try run(
				"/usr/bin/codesign",
				[
					"--force", "--sign", identity,
					"--identifier", bundledServiceID, xpcContents.deletingLastPathComponent().path,
				])
			try run(
				"/usr/bin/codesign",
				[
					"--force", "--sign", identity, "--identifier", serviceIdentifier + ".client",
					client.path,
				])
			plists.append(servicePlist.path)
		}
		let bundle = contents.deletingLastPathComponent()
		try run("/usr/bin/codesign", ["--force", "--sign", identity, bundle.path])
		try run("/usr/bin/codesign", ["--verify", "--deep", "--strict", "--verbose=2", bundle.path])
		try run("/usr/bin/plutil", ["-lint"] + plists)
	}
}

do {
	try main()
} catch {
	FileHandle.standardError.write(Data("package-providers: \(error)\n".utf8))
	exit(1)
}
