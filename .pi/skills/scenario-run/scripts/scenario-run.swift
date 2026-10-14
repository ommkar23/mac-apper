// Launches sequential package-local swift test selections and reports exact-run progress without owning scenario cleanup.
import Darwin
import Foundation

struct Entry: Codable, Equatable {
	let package: String
	let filter: String
	let caseName: String?
}
struct Plan: Codable {
	let root: String
	let entries: [Entry]
}
struct Prepared: Codable {
	let plan: Plan
	let swift: String
	let authorizedLive: Bool
}
struct State: Codable {
	var phase: String
	var index: Int
	var total: Int
	var started: Date
	var updated: Date
	var exitCode: Int32?
	var workerPID: Int32?
	var testPID: Int32?
}
struct Failure: Error, CustomStringConvertible {
	let description: String
	init(_ description: String) { self.description = description }
}
let manager = FileManager.default
func temporaryRoot(_ project: String) throws -> URL {
	let directory = URL(fileURLWithPath: project).appendingPathComponent(".tmp", isDirectory: true)
	guard
		mkdir(directory.path, 0o700) == 0 || errno == EEXIST
	else { throw Failure("cannot create repository .tmp") }
	var info = stat()
	guard
		lstat(directory.path, &info) == 0,
		info.st_mode & S_IFMT == S_IFDIR,
		info.st_uid == getuid(),
		info.st_mode & 0o077 == 0
	else { throw Failure("repository .tmp must be private, owner-owned and nonlinked") }
	return directory
}
let agentFilters = [
	"agentChatScenarios", "agentCreateCounterScenario", "agentCreatePlanScenario",
	"agentCreateHTViewScenario", "agentBundledResourceScenario", "agentScaffoldDevToolsScenario",
]
let providerFilters = [
	"devToolsPlanScenarios", "devToolsPreviewScenarios", "devToolsTestScenarios",
	"devToolsToolchainBuildRunScenario",
]
let selectors: [String: Set<String>] = [
	"agentChatScenarios": [
		"chat-model-greeting", "country-news-japan", "chat-follow-up", "chat-disconnect-replay",
		"chat-resume", "chat-session-isolation", "chat-abort-reuse", "chat-capabilities",
	],
	"devToolsPlanScenarios": [
		"plan-initial-tasks", "plan-lifecycle", "plan-rejections", "plan-project-isolation",
	],
	"devToolsPreviewScenarios": [
		"preview-render", "preview-size", "preview-factories", "preview-failure-recovery",
		"preview-scope", "preview-path-content",
	],
	"devToolsTestScenarios": ["test-package"],
]
func read<T: Decodable>(_ type: T.Type, _ url: URL) throws -> T {
	let values = try url.resourceValues(forKeys: [
		.isRegularFileKey, .isSymbolicLinkKey, .fileSizeKey,
	])
	guard
		values.isRegularFile == true,
		values.isSymbolicLink != true,
		let size = values.fileSize,
		size <= 1_048_576
	else { throw Failure("invalid bounded nonlinked JSON file") }
	return try JSONDecoder().decode(type, from: Data(contentsOf: url))
}
func save<T: Encodable>(_ value: T, _ url: URL) throws {
	let encoder = JSONEncoder()
	encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
	try encoder.encode(value).write(to: url, options: .atomic)
	try manager.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
}
func isLive(_ entry: Entry) -> Bool {
	[
		"agentChatScenarios", "agentCreateCounterScenario", "agentCreatePlanScenario",
		"agentCreateHTViewScenario",
	].contains(entry.filter)
}
func validate(_ plan: Plan, authorized: Bool) throws {
	guard
		plan.root.hasPrefix("/"),
		manager.fileExists(atPath: plan.root + "/AGENTS.md"),
		manager.fileExists(atPath: plan.root + "/Scenario/Package.swift"),
		!plan.entries.isEmpty,
		plan.entries.count <= 64
	else { throw Failure("plan requires an absolute project root and 1...64 selections") }
	for (index, entry) in plan.entries.enumerated() {
		let filters =
			entry.package == "Agent"
			? agentFilters : entry.package == "apps/built-in/dev-tools" ? providerFilters : []
		guard
			filters.contains(entry.filter),
			!plan.entries[..<index].contains(entry)
		else { throw Failure("invalid or duplicate package/filter selection") }
		if let selected = entry.caseName {
			guard
				selectors[entry.filter]?.contains(selected) == true
			else { throw Failure("invalid case selector for \(entry.filter)") }
		}
		guard
			!isLive(entry) || authorized
		else { throw Failure("live selection requires explicit --authorize-live authorization") }
	}
}
func loadPlan(_ url: URL, authorized: Bool) throws -> Plan {
	// Unknown fields fail rather than silently accepting environment overrides or retry policies.
	let data = try Data(contentsOf: url)
	guard
		data.count <= 1_048_576,
		let object = try JSONSerialization.jsonObject(with: data) as? [String: Any],
		Set(object.keys) == ["root", "entries"],
		let entries = object["entries"] as? [[String: Any]],
		entries.allSatisfy({ Set($0.keys).isSubset(of: ["package", "filter", "caseName"]) })
	else { throw Failure("invalid plan fields") }
	let plan = try read(Plan.self, url)
	try validate(plan, authorized: authorized)
	return plan
}
func arguments(_ entry: Entry) -> [String] {
	["test", "--package-path", entry.package, "-j", "2", "--filter", entry.filter]
}
func overrides(_ entry: Entry) -> [String: String] {
	var result: [String: String] = [:]
	if isLive(entry) { result["AGENT_SCENARIO_LIVE"] = "1" }
	if entry.filter == "agentBundledResourceScenario" { result["AGENT_RESOURCE_SCENARIO"] = "1" }
	if entry.filter == "agentScaffoldDevToolsScenario" {
		result["AGENT_SCAFFOLD_DEVTOOLS_SCENARIO"] = "1"
	}
	if let selected = entry.caseName {
		result[entry.package == "Agent" ? "AGENT_SCENARIO_CASE" : "DEV_TOOLS_SCENARIO_CASE"] = selected
	}
	return result
}
func environment(_ entry: Entry, root: String) throws -> [String: String] {
	var result = ProcessInfo.processInfo.environment
	for key in Array(result.keys)
	where key.hasPrefix("AGENT_") || key.hasPrefix("DEV_TOOLS_SCENARIO_")
		|| [
			"SCENARIO_SWIFT64_HOSTED", "SDKROOT", "SWIFT_EXEC", "TOOLCHAINS",
			"COUNTER_OFFLINE_RETAINED_MODEL",
		].contains(key)
	{
		result.removeValue(forKey: key)
	}
	// Credentials and ordinary configuration remain inherited but are never serialized or printed.
	result["TMPDIR"] = try temporaryRoot(root).path + "/"
	return result.merging(overrides(entry)) { _, new in new }
}
func swiftPath() throws -> String {
	let path = manager.homeDirectoryForCurrentUser.appendingPathComponent(
		"Library/Developer/Toolchains/swift-6.4.0-RELEASE.xctoolchain/usr/bin/swift"
	).path
	guard
		manager.isExecutableFile(atPath: path)
	else { throw Failure("standalone Swift 6.4 is unavailable") }
	return path
}
func worker(_ directory: URL) throws {
	let marker = directory.appendingPathComponent("worker.started")
	let descriptor = open(marker.path, O_WRONLY | O_CREAT | O_EXCL | O_NOFOLLOW, 0o600)
	guard
		descriptor >= 0
	else { throw Failure("run already started; retries require a new authorized plan") }
	close(descriptor)
	let prepared = try read(Prepared.self, directory.appendingPathComponent("plan.json"))
	try validate(prepared.plan, authorized: prepared.authorizedLive)
	var state = State(
		phase: "starting", index: 0, total: prepared.plan.entries.count,
		started: Date(), updated: Date(), workerPID: getpid())
	let stateURL = directory.appendingPathComponent("state.json")
	try save(state, stateURL)
	for (index, entry) in prepared.plan.entries.enumerated() {
		let log = directory.appendingPathComponent("selection-\(index + 1).log")
		guard
			manager.createFile(atPath: log.path, contents: nil, attributes: [.posixPermissions: 0o600])
		else { throw Failure("cannot create selection log") }
		let output = try FileHandle(forWritingTo: log)
		defer { try? output.close() }
		let process = Process()
		process.executableURL = URL(fileURLWithPath: prepared.swift)
		process.arguments = arguments(entry)
		process.currentDirectoryURL = URL(fileURLWithPath: prepared.plan.root)
		process.environment = try environment(entry, root: prepared.plan.root)
		process.standardInput = FileHandle.nullDevice
		process.standardOutput = output
		process.standardError = output
		try process.run()
		state.phase = "running"
		state.index = index + 1
		state.testPID = process.processIdentifier
		state.exitCode = nil
		state.updated = Date()
		try save(state, stateURL)
		process.waitUntilExit()
		state.exitCode = process.terminationStatus
		state.testPID = nil
		state.updated = Date()
		try save(state, directory.appendingPathComponent("selection-\(index + 1).result.json"))
		// Fail closed: no automatic retries or later selections after any command failure.
		if process.terminationStatus != 0 {
			state.phase = "failed"
			try save(state, stateURL)
			return
		}
	}
	state.phase = "commands-completed"
	state.updated = Date()
	try save(state, stateURL)
}
func main() throws {
	let args = Array(CommandLine.arguments.dropFirst())
	guard
		let command = args.first
	else {
		throw Failure(
			"usage: scenario-run.swift check|start PLAN [--authorize-live] | status RUN_DIRECTORY [--tail] | worker RUN_DIRECTORY"
		)
	}
	if command == "check" || command == "start" {
		guard
			args.count == 2 || (args.count == 3 && args[2] == "--authorize-live")
		else { throw Failure("invalid arguments") }
		let authorized = args.count == 3
		let plan = try loadPlan(URL(fileURLWithPath: args[1]), authorized: authorized)
		let swift = try swiftPath()
		for entry in plan.entries {
			print(
				overrides(entry).sorted { $0.key < $1.key }.map { "\($0.key)=\($0.value)" }.joined(
					separator: " "))
			print(([swift] + arguments(entry)).joined(separator: " "))
		}
		if command == "check" { print("CHECK ONLY: no tests or paid startup executed"); return }
		let directory = try temporaryRoot(plan.root).appendingPathComponent(
			"scenario-run-\(UUID().uuidString)")
		try manager.createDirectory(
			at: directory, withIntermediateDirectories: false, attributes: [.posixPermissions: 0o700])
		try save(
			Prepared(plan: plan, swift: swift, authorizedLive: authorized),
			directory.appendingPathComponent("plan.json"))
		try save(
			State(phase: "queued", index: 0, total: plan.entries.count, started: Date(), updated: Date()),
			directory.appendingPathComponent("state.json"))
		let log = directory.appendingPathComponent("supervisor.log")
		manager.createFile(atPath: log.path, contents: nil, attributes: [.posixPermissions: 0o600])
		let handle = try FileHandle(forWritingTo: log)
		defer { try? handle.close() }
		let process = Process()
		process.executableURL = URL(fileURLWithPath: swift)
		process.arguments = [URL(fileURLWithPath: #filePath).path, "worker", directory.path]
		var environment = ProcessInfo.processInfo.environment
		environment["TMPDIR"] = directory.deletingLastPathComponent().path + "/"
		process.environment = environment
		process.standardInput = FileHandle.nullDevice
		process.standardOutput = handle
		process.standardError = handle
		try process.run()
		print("RUN_DIRECTORY=\(directory.path)")
		print(
			"Monitor only this directory; scenario tests own process cleanup; supervisor PID=\(process.processIdentifier)"
		)
	} else if command == "worker" {
		guard
			args.count == 2
		else { throw Failure("invalid worker arguments") }
		try worker(URL(fileURLWithPath: args[1]))
	} else if command == "status" {
		guard
			args.count == 2 || (args.count == 3 && args[2] == "--tail")
		else { throw Failure("invalid status arguments") }
		let directory = URL(fileURLWithPath: args[1])
		let state = try read(State.self, directory.appendingPathComponent("state.json"))
		print(
			"Last recorded phase=\(state.phase) selection=\(state.index)/\(state.total) elapsed=\(Int(Date().timeIntervalSince(state.started)))s stateAge=\(Int(Date().timeIntervalSince(state.updated)))s exit=\(state.exitCode.map(String.init) ?? "none")"
		)
		print(
			"Command exit 0 alone is not a scenario pass; selected test execution and cleanup need log verification."
		)
		if args.count == 3, state.index > 0 {
			let log = directory.appendingPathComponent("selection-\(state.index).log")
			let handle = try FileHandle(forReadingFrom: log)
			defer { try? handle.close() }
			let size = try handle.seekToEnd()
			try handle.seek(toOffset: size > 4096 ? size - 4096 : 0)
			print(String(decoding: try handle.read(upToCount: 4096) ?? Data(), as: UTF8.self))
		}
	} else {
		throw Failure("unknown command")
	}
}
umask(0o077)
do { try main() } catch {
	FileHandle.standardError.write(Data("scenario-run: \(error)\n".utf8))
	exit(1)
}
