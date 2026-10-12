// @frontmatter:start
// Loads the integration catalog and resolves agent tools, extensions, and provider executables.
// @frontmatter:end
import Foundation

public struct AgentIntegrationCatalog: Decodable, Sendable {
	public enum CatalogError: Error {
		case invalidSchema
		case unknownAgent
		case missingApplication
		case missingExtension
	}

	public struct App: Decodable, Sendable {
		public struct Application: Decodable, Sendable {
			public let bundleName: String
			public let executableProduct: String
			public let serviceProduct: String?
			public let serviceIdentifier: String?
			public let xpcServicePlist: String?
			public let infoPlist: String
			public let registersProjects: Bool?
		}

		public struct PiExtension: Decodable, Sendable {
			public let path: String
			public let agents: [String]
			public let tools: [String]
			public let firstRequestOnly: Bool
		}

		public let id: String
		public let packagePath: String
		public let application: Application
		public let piExtensions: [PiExtension]
	}

	public struct Configuration: Sendable {
		public let id: String
		public let runtimeMode: AgentRuntimeMode
		public let extensionURLs: [URL]
		public let tools: [String]
		public let systemPrompt: String
		public let applications: [Application]
	}

	public struct Application: Sendable {
		public let id: String
		public let controlExecutableURL: URL
		public let serviceExecutableURL: URL
		public let clientExecutableURL: URL
		public let registersProjects: Bool
	}

	private let schemaVersion: Int
	private let apps: [App]
	public var availableAgents: [AgentDefinition] { AgentCatalog.definitions }

	public static func load(from url: URL) throws -> Self {
		let catalog = try JSONDecoder().decode(Self.self, from: Data(contentsOf: url))
		guard
			catalog.schemaVersion == 1
		else { throw CatalogError.invalidSchema }
		return catalog
	}

	public func configuration(agentID: String, firstRequest: Bool, root: URL) throws -> Configuration
	{
		guard
			let agent = availableAgents.first(where: { $0.id == agentID })
		else { throw CatalogError.unknownAgent }
		let selectedApps = try agent.appIDs.map { id in
			guard
				let app = apps.first(where: { $0.id == id })
			else { throw CatalogError.missingApplication }
			return app
		}
		var extensionURLs: [URL] = []
		var tools = agent.baseTools
		var applications: [Application] = []
		let authoredExtensions =
			agentID == "chat" ? AgentCatalog.chatExtensions : AgentCatalog.createExtensions
		if !authoredExtensions.isEmpty {
			let authored = root.appendingPathComponent("Agent/Extensions", isDirectory: true)
			let bundled = root.appendingPathComponent("Resources/AgentExtensions", isDirectory: true)
			let directory = FileManager.default.fileExists(atPath: authored.path) ? authored : bundled
			for entry in authoredExtensions where firstRequest || !entry.firstRequestOnly {
				let url = directory.appendingPathComponent(entry.name).standardizedFileURL
				guard
					url.path.hasPrefix(directory.standardizedFileURL.path + "/"),
					FileManager.default.isReadableFile(atPath: url.path)
				else { throw CatalogError.missingExtension }
				extensionURLs.append(url)
				for tool in entry.tools where !tools.contains(tool) { tools.append(tool) }
			}
		}
		for app in selectedApps {
			let sourceRoot = root.appendingPathComponent(app.packagePath, isDirectory: true)
			let bundledRoot = root.appendingPathComponent(
				"Applications/\(app.application.bundleName)/Contents", isDirectory: true)
			let resources =
				FileManager.default.fileExists(atPath: sourceRoot.path)
				? sourceRoot : bundledRoot.appendingPathComponent("Resources", isDirectory: true)
			let appExtensions = app.piExtensions.filter {
				$0.agents.contains(agentID) && (firstRequest || !$0.firstRequestOnly)
			}
			for entry in appExtensions {
				let url = resources.appendingPathComponent(entry.path).standardizedFileURL
				guard
					url.path.hasPrefix(resources.standardizedFileURL.path + "/"),
					FileManager.default.isReadableFile(atPath: url.path)
				else { throw CatalogError.missingExtension }
				extensionURLs.append(url)
				for tool in entry.tools where !tools.contains(tool) { tools.append(tool) }
			}
			if !FileManager.default.fileExists(atPath: sourceRoot.path),
				let serviceProduct = app.application.serviceProduct
			{
				guard
					serviceProduct.hasSuffix("Application")
				else { throw CatalogError.missingApplication }
				let appName = String(serviceProduct.dropLast("Application".count))
				let clientProduct =
					app.application.executableProduct.hasSuffix("AgentClient")
					? app.application.executableProduct : appName + "TerminalClient"
				let clientExecutableURL = bundledRoot.appendingPathComponent("MacOS/\(clientProduct)")
				applications.append(
					.init(
						id: app.id,
						controlExecutableURL: bundledRoot.appendingPathComponent(
							"MacOS/\(app.application.executableProduct)"),
						serviceExecutableURL: bundledRoot.appendingPathComponent(
							"XPCServices/\(serviceProduct).xpc/Contents/MacOS/\(serviceProduct)"),
						clientExecutableURL: clientExecutableURL,
						registersProjects: app.application.registersProjects ?? false))
			}
		}
		return .init(
			id: agent.id, runtimeMode: agent.runtimeMode, extensionURLs: extensionURLs, tools: tools,
			systemPrompt: agent.systemPrompt, applications: applications)
	}

	public static func bundledCatalogURL() -> URL {
		Bundle.main.bundleURL.appendingPathComponent("Contents/Resources/IntegrationCatalog.json")
	}

	public static func defaultCatalog() -> Self? {
		let bundled = bundledCatalogURL()
		if FileManager.default.isReadableFile(atPath: bundled.path) {
			return try? load(from: bundled)
		}
		return nil
	}

	public static func defaultRootURL() -> URL {
		let bundled = bundledCatalogURL()
		if FileManager.default.isReadableFile(atPath: bundled.path) {
			return Bundle.main.bundleURL.appendingPathComponent("Contents", isDirectory: true)
		}
		return URL(fileURLWithPath: FileManager.default.currentDirectoryPath, isDirectory: true)
	}
}
