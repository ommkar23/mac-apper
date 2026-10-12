// @frontmatter:start
// Locates and runs Pi RPC, framing its input and output and managing process lifecycle.
// @frontmatter:end
import Darwin
import Foundation

public enum PiProcessError: Error, CustomStringConvertible {
	case executableUnavailable
	case extensionUnavailable
	case launchFailed(String)
	case transportClosed

	public var description: String {
		switch self {
		case .executableUnavailable:
			return "The local Pi CLI was not found. Install Pi and make it executable."
		case .extensionUnavailable:
			return "The bundled Mac Apper Pi extension is missing or unreadable."
		case .launchFailed(let message): return "Pi could not start: \(message)"
		case .transportClosed: return "The Pi RPC transport is closed."
		}
	}
}

public enum PiExecutableLocator {
	public static func locate(
		home: URL = FileManager.default.homeDirectoryForCurrentUser,
		environment: [String: String] = ProcessInfo.processInfo.environment
	) -> URL? {
		var candidates: [URL] = []
		for entry in (environment["PATH"] ?? "").split(separator: ":") {
			candidates.append(
				URL(fileURLWithPath: String(entry), isDirectory: true).appendingPathComponent("pi"))
		}
		candidates += [
			home.appendingPathComponent(".local/bin/pi"),
			URL(fileURLWithPath: "/opt/homebrew/bin/pi"),
			URL(fileURLWithPath: "/usr/local/bin/pi"),
		]
		let nvm = home.appendingPathComponent(".nvm/versions/node", isDirectory: true)
		if let versions = try? FileManager.default.contentsOfDirectory(
			at: nvm, includingPropertiesForKeys: nil)
		{
			candidates += versions.sorted { $0.lastPathComponent > $1.lastPathComponent }.map {
				$0.appendingPathComponent("bin/pi")
			}
		}
		return candidates.first { FileManager.default.isExecutableFile(atPath: $0.path) }
	}
}

private final class PiOutputRelay: @unchecked Sendable {
	private let lock = NSLock()
	private let standardErrorByteLimit: Int
	private var parser = PiRPCParser()
	private var continuation: AsyncThrowingStream<PiRPCEvent, any Error>.Continuation?
	private var stderr = Data()

	init(standardErrorByteLimit: Int) {
		self.standardErrorByteLimit = standardErrorByteLimit
	}

	func attach(_ continuation: AsyncThrowingStream<PiRPCEvent, any Error>.Continuation) {
		lock.withLock { self.continuation = continuation }
	}

	func receive(_ data: Data) {
		lock.withLock {
			do { for event in try parser.feed(data) { continuation?.yield(event) } } catch {
				continuation?.finish(throwing: error)
				continuation = nil
			}
		}
	}

	func receiveError(_ data: Data) {
		lock.withLock {
			guard
				stderr.count < standardErrorByteLimit
			else { return }
			stderr.append(data.prefix(standardErrorByteLimit - stderr.count))
		}
	}

	func finish(status: Int32) {
		lock.withLock {
			do { _ = try parser.finish() } catch {
				continuation?.finish(throwing: error)
				continuation = nil
				return
			}
			if status == 0 {
				continuation?.finish()
			} else {
				let detail = String(decoding: stderr.suffix(2_000), as: UTF8.self)
				continuation?.finish(
					throwing: PiProcessError.launchFailed(detail.isEmpty ? "exit status \(status)" : detail))
			}
			continuation = nil
		}
	}
}

public struct PiProcessConfiguration: Sendable {
	public let executable: URL?
	public let sessionDirectory: URL?
	public let outputRoot: URL?
	public let persistsSessions: Bool
	public let environment: [String: String]
	public let inheritsParentEnvironment: Bool
	public let provider: String?
	public let model: String?
	public let thinking: String?
	public let tools: [String]?
	public let extensions: [URL]?
	public let systemPrompt: String?
	public let loadsSkills: Bool?
	public let loadsPromptTemplates: Bool?
	public let loadsThemes: Bool?
	public let loadsContextFiles: Bool?
	public let approvesProjectFiles: Bool
	public let offline: Bool
	public let telemetryEnabled: Bool?
	public let usesIntegrationCatalog: Bool
	public let startsProviderServices: Bool
	public let eventBufferLimit: Int
	public let standardErrorByteLimit: Int
	public let abortGraceMilliseconds: UInt64
	public let terminationPollMilliseconds: UInt64
	public let terminationPollCount: Int

	public init(
		executable: URL? = PiExecutableLocator.locate(), sessionDirectory: URL? = nil,
		outputRoot: URL? = nil, persistsSessions: Bool = true, environment: [String: String] = [:],
		inheritsParentEnvironment: Bool = true, provider: String? = nil, model: String? = nil,
		thinking: String? = nil, tools: [String]? = nil, extensions: [URL]? = nil,
		systemPrompt: String? = nil, loadsSkills: Bool? = nil,
		loadsPromptTemplates: Bool? = nil, loadsThemes: Bool? = nil,
		loadsContextFiles: Bool? = nil, approvesProjectFiles: Bool = true, offline: Bool = false,
		telemetryEnabled: Bool? = nil, usesIntegrationCatalog: Bool = true,
		startsProviderServices: Bool = true, eventBufferLimit: Int = 2_048,
		standardErrorByteLimit: Int = 131_072, abortGraceMilliseconds: UInt64 = 250,
		terminationPollMilliseconds: UInt64 = 25, terminationPollCount: Int = 20
	) {
		self.executable = executable
		self.sessionDirectory = sessionDirectory
		self.outputRoot = outputRoot
		self.persistsSessions = persistsSessions
		self.environment = environment
		self.inheritsParentEnvironment = inheritsParentEnvironment
		self.provider = provider
		self.model = model
		self.thinking = thinking
		self.tools = tools
		self.extensions = extensions
		self.systemPrompt = systemPrompt
		self.loadsSkills = loadsSkills
		self.loadsPromptTemplates = loadsPromptTemplates
		self.loadsThemes = loadsThemes
		self.loadsContextFiles = loadsContextFiles
		self.approvesProjectFiles = approvesProjectFiles
		self.offline = offline
		self.telemetryEnabled = telemetryEnabled
		self.usesIntegrationCatalog = usesIntegrationCatalog
		self.startsProviderServices = startsProviderServices
		self.eventBufferLimit = min(max(eventBufferLimit, 1), 8_192)
		self.standardErrorByteLimit = min(max(standardErrorByteLimit, 0), 1_048_576)
		self.abortGraceMilliseconds = min(abortGraceMilliseconds, 60_000)
		self.terminationPollMilliseconds = min(terminationPollMilliseconds, 1_000)
		self.terminationPollCount = min(max(terminationPollCount, 1), 1_000)
	}
}

@MainActor public final class PiRPCProcess: PiSessionRuntime {
	nonisolated public static var availableAgents: [AgentDefinition] {
		AgentCatalog.definitions
	}

	private let configuration: PiProcessConfiguration
	private let integrationCatalog: AgentIntegrationCatalog?
	private let integrationRootURL: URL?
	private var process: Process?
	private var input: FileHandle?
	private var outputRelay: PiOutputRelay?

	public init(
		executable: URL? = PiExecutableLocator.locate(),
		integrationCatalog: AgentIntegrationCatalog? = AgentIntegrationCatalog.defaultCatalog(),
		integrationRootURL: URL? = AgentIntegrationCatalog.defaultRootURL()
	) {
		configuration = .init(executable: executable)
		self.integrationCatalog = integrationCatalog
		self.integrationRootURL = integrationRootURL
	}

	public init(
		configuration: PiProcessConfiguration,
		integrationCatalog: AgentIntegrationCatalog? = AgentIntegrationCatalog.defaultCatalog(),
		integrationRootURL: URL? = AgentIntegrationCatalog.defaultRootURL()
	) {
		self.configuration = configuration
		self.integrationCatalog = integrationCatalog
		self.integrationRootURL = integrationRootURL
	}

	public func sessionDirectory(in project: URL) -> URL {
		configuration.sessionDirectory ?? ChatSessionCatalog.defaultDirectory(in: project)
	}

	public func start(in project: URL) async throws -> AsyncThrowingStream<PiRPCEvent, any Error> {
		try await launch(agentID: "create", in: project, sessionFile: nil, title: nil)
	}

	public func start(in project: URL, sessionFile: URL, title: String?) async throws
		-> AsyncThrowingStream<PiRPCEvent, any Error>
	{
		try ChatSessionCatalog.validate(
			sessionFile, in: project, sessionDirectory: sessionDirectory(in: project))
		if FileManager.default.fileExists(atPath: sessionFile.path) {
			_ = try ChatSessionCatalog.load(
				sessionFile, in: project, sessionDirectory: sessionDirectory(in: project))
		}
		return try await launch(agentID: "create", in: project, sessionFile: sessionFile, title: title)
	}

	public func start(in project: URL, sessionFile: URL, title: String?, createApp: Bool) async throws
		-> AsyncThrowingStream<PiRPCEvent, any Error>
	{
		try ChatSessionCatalog.validate(
			sessionFile, in: project, sessionDirectory: sessionDirectory(in: project))
		return try await launch(
			agentID: "create", in: project, sessionFile: sessionFile, title: title,
			firstRequest: createApp)
	}

	public func startChat(in project: URL, sessionFile: URL, title: String?) async throws
		-> AsyncThrowingStream<PiRPCEvent, any Error>
	{
		try ChatSessionCatalog.validate(
			sessionFile, in: project, sessionDirectory: sessionDirectory(in: project))
		if FileManager.default.fileExists(atPath: sessionFile.path) {
			_ = try ChatSessionCatalog.load(
				sessionFile, in: project, sessionDirectory: sessionDirectory(in: project))
		}
		return try await launch(agentID: "chat", in: project, sessionFile: sessionFile, title: title)
	}

	public func start(
		agentID: String, in project: URL, sessionFile: URL, title: String?, firstRequest: Bool
	) async throws -> AsyncThrowingStream<PiRPCEvent, any Error> {
		try ChatSessionCatalog.validate(
			sessionFile, in: project, sessionDirectory: sessionDirectory(in: project))
		if FileManager.default.fileExists(atPath: sessionFile.path) {
			_ = try ChatSessionCatalog.load(
				sessionFile, in: project, sessionDirectory: sessionDirectory(in: project))
		}
		return try await launch(
			agentID: agentID, in: project, sessionFile: sessionFile, title: title,
			firstRequest: firstRequest)
	}

	private func launch(
		agentID: String, in project: URL, sessionFile: URL?, title: String?,
		firstRequest: Bool = false
	)
		async throws -> AsyncThrowingStream<PiRPCEvent, any Error>
	{
		guard
			process == nil
		else { throw PiProcessError.launchFailed("a session is already running") }
		guard
			let executable = configuration.executable
		else { throw PiProcessError.executableUnavailable }
		let projectID = project.lastPathComponent
		let sessionID =
			sessionFile?.deletingPathExtension().lastPathComponent
			?? UUID().uuidString.lowercased()
		let catalogConfiguration: AgentIntegrationCatalog.Configuration?
		if configuration.usesIntegrationCatalog {
			guard
				let integrationCatalog,
				let integrationRootURL
			else { throw PiProcessError.extensionUnavailable }
			catalogConfiguration = try integrationCatalog.configuration(
				agentID: agentID, firstRequest: firstRequest, root: integrationRootURL)
		} else {
			catalogConfiguration = nil
		}
		let conversationOnly = catalogConfiguration?.runtimeMode == .conversation
		let applications =
			configuration.startsProviderServices
			? (catalogConfiguration?.applications ?? []) : []
		for application in applications {
			let id = application.id
			if application.registersProjects {
				guard
					FileManager.default.isExecutableFile(atPath: application.controlExecutableURL.path)
				else { throw PiProcessError.launchFailed("\(id) service control is unavailable") }
			}
			guard
				FileManager.default.isExecutableFile(atPath: application.clientExecutableURL.path)
			else { throw PiProcessError.launchFailed("\(application.id) terminal client is unavailable") }
			guard
				FileManager.default.isExecutableFile(atPath: application.serviceExecutableURL.path)
			else { throw PiProcessError.launchFailed("\(application.id) XPC service is unavailable") }
			if application.registersProjects {
				try await Self.invokeProviderService(
					executable: application.controlExecutableURL,
					arguments: ["--register-project", projectID, sessionID], in: project)
			}
		}
		guard
			configuration.persistsSessions || sessionFile == nil
		else { throw PiProcessError.launchFailed("An ephemeral Pi run cannot receive a session file") }

		let process = Process()
		process.executableURL = executable
		process.currentDirectoryURL = project
		process.arguments = ["--mode", "rpc"]
		if configuration.persistsSessions {
			let sessionDirectory = sessionDirectory(in: project)
			try FileManager.default.createDirectory(
				at: sessionDirectory, withIntermediateDirectories: true,
				attributes: [.posixPermissions: 0o700])
			process.arguments! += ["--session-dir", sessionDirectory.path]
		} else {
			process.arguments!.append("--no-session")
		}
		process.arguments!.append("--no-extensions")
		for url in configuration.extensions ?? catalogConfiguration?.extensionURLs ?? [] {
			process.arguments! += ["--extension", url.path]
		}
		let tools = configuration.tools ?? catalogConfiguration?.tools ?? []
		process.arguments! +=
			tools.isEmpty ? ["--no-tools"] : ["--tools", tools.joined(separator: ",")]
		process.arguments!.append(configuration.approvesProjectFiles ? "--approve" : "--no-approve")
		if let provider = configuration.provider { process.arguments! += ["--provider", provider] }
		if let model = configuration.model { process.arguments! += ["--model", model] }
		if let thinking = configuration.thinking { process.arguments! += ["--thinking", thinking] }
		if configuration.loadsSkills == false || (configuration.loadsSkills == nil && conversationOnly)
		{
			process.arguments!.append("--no-skills")
		}
		if configuration.loadsPromptTemplates == false
			|| (configuration.loadsPromptTemplates == nil && conversationOnly)
		{
			process.arguments!.append("--no-prompt-templates")
		}
		if configuration.loadsThemes == false { process.arguments!.append("--no-themes") }
		if configuration.loadsContextFiles == false
			|| (configuration.loadsContextFiles == nil && conversationOnly)
		{
			process.arguments!.append("--no-context-files")
		}
		if configuration.offline { process.arguments!.append("--offline") }
		let systemPrompt = configuration.systemPrompt ?? catalogConfiguration?.systemPrompt
		if let systemPrompt {
			process.arguments! += [
				conversationOnly || !configuration.usesIntegrationCatalog
					? "--system-prompt" : "--append-system-prompt",
				systemPrompt,
			]
		}
		if !conversationOnly && configuration.usesIntegrationCatalog {
			process.arguments! += ["--exclude-tools", "bash,powershell"]
		}
		if let sessionFile { process.arguments! += ["--session", sessionFile.path] }
		if let title { process.arguments! += ["--name", ChatSessionCatalog.title(for: title)] }
		var environment =
			configuration.inheritsParentEnvironment ? ProcessInfo.processInfo.environment : [:]
		for (key, value) in configuration.environment { environment[key] = value }
		if configuration.inheritsParentEnvironment {
			environment["PATH"] =
				"/usr/bin:/bin:/usr/sbin:/sbin:/usr/local/bin:"
				+ executable.deletingLastPathComponent().path
		}
		if let telemetryEnabled = configuration.telemetryEnabled {
			environment["PI_TELEMETRY"] = telemetryEnabled ? "1" : "0"
		}
		for application in applications {
			let key =
				"MAC_APPER_"
				+ application.id.uppercased().map {
					$0.isLetter || $0.isNumber ? String($0) : "_"
				}.joined() + "_TERMINAL_CLIENT_PATH"
			let clientName = application.clientExecutableURL.lastPathComponent
			if clientName.hasSuffix("AgentClient") {
				environment["OPENXPC_\(clientName.uppercased())_CLIENT_PATH"] =
					application.clientExecutableURL.path
			} else {
				environment[key] = application.clientExecutableURL.path
				if clientName == "DevToolsTerminalClient" {
					environment["OPENXPC_DEVTOOLSTERMINALCLIENT_CLIENT_PATH"] =
						application.clientExecutableURL.path
				}
			}
		}
		environment["OPENXPC_PROJECT_ROOT"] = project.path
		environment["MAC_APPER_OUTPUT_ROOT"] =
			(configuration.outputRoot
			?? project.deletingLastPathComponent().appendingPathComponent("output", isDirectory: true))
			.path
		environment["MAC_APPER_PROJECT_ID"] =
			conversationOnly
			? "00000000-0000-4000-8000-000000000001" : projectID
		environment["MAC_APPER_SESSION_ID"] = sessionID
		environment["OPENXPC_PROJECT_ID"] = environment["MAC_APPER_PROJECT_ID"]
		let openXPCSessionID =
			UUID(uuidString: sessionID)
			?? UUID(uuidString: String(sessionID.suffix(36))) ?? UUID()
		environment["OPENXPC_SESSION_ID"] = openXPCSessionID.uuidString.lowercased()
		process.environment = environment
		let stdin = Pipe()
		let stdout = Pipe()
		let stderr = Pipe()
		process.standardInput = stdin
		process.standardOutput = stdout
		process.standardError = stderr
		let outputRelay = PiOutputRelay(standardErrorByteLimit: configuration.standardErrorByteLimit)
		let stream = AsyncThrowingStream<PiRPCEvent, any Error>(
			bufferingPolicy: .bufferingOldest(configuration.eventBufferLimit)
		) { continuation in
			outputRelay.attach(continuation)
		}
		stdout.fileHandleForReading.readabilityHandler = { handle in
			let data = handle.availableData
			if !data.isEmpty { outputRelay.receive(data) }
		}
		stderr.fileHandleForReading.readabilityHandler = { handle in
			let data = handle.availableData
			if !data.isEmpty { outputRelay.receiveError(data) }
		}
		process.terminationHandler = { process in
			stdout.fileHandleForReading.readabilityHandler = nil
			stderr.fileHandleForReading.readabilityHandler = nil
			outputRelay.finish(status: process.terminationStatus)
		}
		do { try process.run() } catch {
			stdout.fileHandleForReading.readabilityHandler = nil
			stderr.fileHandleForReading.readabilityHandler = nil
			throw PiProcessError.launchFailed(String(describing: error))
		}
		self.process = process
		input = stdin.fileHandleForWriting
		self.outputRelay = outputRelay
		return stream
	}

	private static func invokeProviderService(executable: URL, arguments: [String], in directory: URL)
		async throws
	{
		try await Task.detached {
			let process = Process()
			let output = Pipe()
			process.executableURL = executable
			process.arguments = arguments
			process.currentDirectoryURL = directory
			process.standardOutput = output
			process.standardError = output
			try process.run()
			process.waitUntilExit()
			guard
				process.terminationStatus == 0
			else {
				let detail = String(
					decoding: output.fileHandleForReading.readDataToEndOfFile().suffix(2_000), as: UTF8.self)
				throw PiProcessError.launchFailed("\(arguments.first ?? "service") failed: \(detail)")
			}
		}.value
	}

	public func prompt(_ message: String) async throws {
		try write(.prompt(id: UUID().uuidString.lowercased(), message: message))
	}

	public func abort() async throws {
		guard
			process?.isRunning == true
		else { return }
		try write(.abort(id: UUID().uuidString.lowercased()))
		try? await Task.sleep(for: .milliseconds(configuration.abortGraceMilliseconds))
	}

	private func write(_ command: PiRPCCommand) throws {
		guard
			let input,
			process?.isRunning == true
		else { throw PiProcessError.transportClosed }
		do { try input.write(contentsOf: command.encodedLine()) } catch {
			throw PiProcessError.transportClosed
		}
	}

	@discardableResult public func stop() async -> Bool {
		guard
			let process
		else { return true }
		if process.isRunning {
			try? write(.abort(id: UUID().uuidString.lowercased()))
			try? await Task.sleep(for: .milliseconds(configuration.abortGraceMilliseconds))
			process.terminate()
			for _ in 0..<configuration.terminationPollCount {
				if !process.isRunning { break }
				try? await Task.sleep(for: .milliseconds(configuration.terminationPollMilliseconds))
			}
			if process.isRunning { kill(process.processIdentifier, SIGKILL) }
		}
		input?.closeFile()
		self.input = nil
		self.process = nil
		outputRelay = nil
		return !process.isRunning
	}
}
