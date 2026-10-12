// @frontmatter:start
// Builds a fresh scaffold and checks typed Core Data CRUD, rollback, ownership, storage paths, and presentation.
// @frontmatter:end
import Foundation
import Scenario
import Testing

@testable import AgentApplication

@Test func generatedScaffoldSupportsOfflineFirstPersistenceAndPresentation() throws {
	let parent = URL(fileURLWithPath: "/private/tmp/mac-apper-scaffold-\(UUID().uuidString)")
	try FileManager.default.createDirectory(at: parent, withIntermediateDirectories: false)
	var completed = false
	defer {
		if completed {
			try? FileManager.default.removeItem(at: parent)
		} else {
			print("Retained failed scaffold fixture: \(parent.path)")
		}
	}
	let project = try ProjectScaffold.create(under: parent)
	try ProjectScaffold.validate(project)
	#expect(BaseAppTemplate.version == "8")
	let production = try String(
		contentsOf: project.appendingPathComponent("Sources/ProductionApp/ProductionApp.swift"),
		encoding: .utf8)
	#expect(production.contains("ApplicationModel.production(appID:"))
	let views = try String(
		contentsOf: project.appendingPathComponent("Sources/AppViews/ApplicationRoot.swift"),
		encoding: .utf8)
	#expect(!views.contains("CoreData") && !views.contains("SwiftData") && !views.contains("@Query"))
	#expect(!views.contains("NSManagedObject") && views.contains("model.state"))
	let persistence = try String(
		contentsOf: project.appendingPathComponent("Sources/AppModel/Persistence.swift"),
		encoding: .utf8)
	#expect(!persistence.contains("SwiftData") && !persistence.contains("@Model"))
	// Only the test-owned package gains a fixture entity and a fresh-process probe.
	let manifestURL = project.appendingPathComponent("Package.swift")
	let manifest = try String(contentsOf: manifestURL, encoding: .utf8)
	try manifest.replacingOccurrences(
		of: ".target(name: \"AppModel\"),",
		with: """
			.target(name: "AppModel"),
			.target(name: "ProbeSupport", dependencies: ["AppModel"]),
			.executableTarget(name: "PersistenceProbe", dependencies: ["AppModel", "ProbeSupport"]),
			"""
	).replacingOccurrences(
		of: "dependencies: [\"AppModel\", .product",
		with: "dependencies: [\"AppModel\", \"ProbeSupport\", .product"
	)
	.write(to: manifestURL, atomically: true, encoding: .utf8)
	for (path, source) in [
		"Sources/ProbeSupport/Probe.swift": PersistenceFixture.entity,
		"Sources/PersistenceProbe/main.swift": PersistenceFixture.executable,
		"Tests/AppModelTests/ScaffoldPersistenceChecks.swift": PersistenceFixture.tests,
	] {
		let url = project.appendingPathComponent(path)
		try FileManager.default.createDirectory(
			at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
		try source.write(to: url, atomically: true, encoding: .utf8)
	}
	let scratch = parent.appendingPathComponent("build")
	try FileManager.default.createDirectory(at: scratch, withIntermediateDirectories: false)
	try runPersistenceCommand(
		try SwiftToolchain.executable("swift"),
		[
			"test", "-j", "2", "--scratch-path", scratch.path,
			"-Xswiftc", "-strict-concurrency=complete", "-Xswiftc", "-warnings-as-errors",
		], in: project, log: parent.appendingPathComponent("test.log"), timeout: 600)
	let binLog = parent.appendingPathComponent("bin.log")
	try runPersistenceCommand(
		try SwiftToolchain.executable("swift"),
		[
			"build", "--scratch-path", scratch.path, "--show-bin-path",
		], in: project, log: binLog, timeout: 60)
	let bin = try String(contentsOf: binLog, encoding: .utf8).trimmingCharacters(
		in: .whitespacesAndNewlines)
	let probe = URL(fileURLWithPath: bin).appendingPathComponent("PersistenceProbe")
	for mode in ["write", "check", "delete", "absent"] {
		try runPersistenceCommand(
			probe, [mode, parent.appendingPathComponent("process.sqlite").path],
			in: project, log: parent.appendingPathComponent("\(mode).log"), timeout: 30)
	}
	completed = true
}

private func runPersistenceCommand(
	_ executable: URL, _ arguments: [String], in directory: URL, log: URL, timeout: Double
) throws {
	let process = Process()
	process.executableURL = executable
	process.arguments = arguments
	process.currentDirectoryURL = directory
	var environment = ProcessInfo.processInfo.environment
	environment["SWIFT_EXEC"] = try SwiftToolchain.executable("swiftc").path
	environment["DEVELOPER_DIR"] = "/Library/Developer/CommandLineTools"
	environment["SDKROOT"] = "/Library/Developer/CommandLineTools/SDKs/MacOSX26.2.sdk"
	process.environment = environment
	_ = FileManager.default.createFile(atPath: log.path, contents: nil)
	let output = try FileHandle(forWritingTo: log)
	defer { try? output.close() }
	process.standardOutput = output
	process.standardError = output
	let finished = DispatchSemaphore(value: 0)
	process.terminationHandler = { _ in finished.signal() }
	try process.run()
	let deadline = Date().addingTimeInterval(timeout)
	while finished.wait(timeout: .now() + 0.1) == .timedOut {
		let size = try log.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0
		if Date() >= deadline || size > 4 * 1024 * 1024 {
			process.terminate()
			_ = finished.wait(timeout: .now() + 5)
			// Retain the owned fixture on failure; do not remove paths that children may still use.
			throw NSError(domain: "ScaffoldPersistence.TimeOrOutputLimit", code: 1)
		}
	}
	let size = try log.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0
	guard
		size <= 4 * 1024 * 1024
	else { throw NSError(domain: "ScaffoldPersistence.OutputLimit", code: 1) }
	let text = try String(contentsOf: log, encoding: .utf8)
	print("Scaffold command: \(executable.path) \(arguments.joined(separator: " "))\n\(text)")
	#expect(process.terminationStatus == 0, "Scaffold persistence verification failed:\n\(text)")
	guard
		process.terminationStatus == 0
	else { throw NSError(domain: "Scaffold.Command", code: Int(process.terminationStatus)) }
}

private enum PersistenceFixture {
	static let entity = #"""
		import AppModel
		import CoreData
		import Foundation

		@objc(ScaffoldProbeRecord) public final class Probe: NSManagedObject {
		    @NSManaged public var id: UUID
		    @NSManaged public var text: String
		    @NSManaged public var count: Int64
		}
		public struct Row: Equatable, Sendable {
		    public let id: UUID
		    public let text: String
		    public let count: Int64
		    public init(id: UUID, text: String, count: Int64) { self.id = id; self.text = text; self.count = count }
		}
		@MainActor public enum ProbeSchema {
		    public static func make() -> NSManagedObjectModel {
		        let model = NSManagedObjectModel()
		        model.versionIdentifiers = ["probe-1"]
		        let entity = NSEntityDescription()
		        entity.name = "Probe"
		        entity.managedObjectClassName = NSStringFromClass(Probe.self)
		        func attribute(_ name: String, _ type: NSAttributeType) -> NSAttributeDescription {
		            let value = NSAttributeDescription()
		            value.name = name; value.attributeType = type; value.isOptional = false
		            return value
		        }
		        let count = attribute("count", .integer64AttributeType)
		        count.setValidationPredicates([NSPredicate(format: "SELF >= 0")], withValidationWarnings: ["count must be nonnegative"])
		        entity.properties = [attribute("id", .UUIDAttributeType), attribute("text", .stringAttributeType), count]
		        model.entities = [entity]
		        return model
		    }
		    public static func insert(_ context: NSManagedObjectContext, id: UUID, text: String, count: Int64) {
		        let record = Probe(entity: context.persistentStoreCoordinator!.managedObjectModel.entities[0], insertInto: context)
		        record.id = id; record.text = text; record.count = count
		    }
		    public static func records(_ context: NSManagedObjectContext) throws -> [Probe] {
		        try context.fetch(NSFetchRequest<Probe>(entityName: "Probe"))
		    }
		    public static func rows(_ context: NSManagedObjectContext) throws -> [Row] {
		        try records(context).map { Row(id: $0.id, text: $0.text, count: $0.count) }.sorted { $0.id.uuidString < $1.id.uuidString }
		    }
		}
		"""#
	static let executable = #"""
		import AppModel
		import CoreData
		import Foundation
		import ProbeSupport

		@MainActor func run() throws {
		    let mode = CommandLine.arguments[1]
		    let stack = try ApplicationPersistence.disk(at: URL(fileURLWithPath: CommandLine.arguments[2]), schema: ProbeSchema.make())
		    let model = ApplicationModel(persistence: stack)
		    let id = UUID(uuidString: "11111111-1111-4111-8111-111111111111")!
		    switch mode {
		    case "write":
		        precondition(model.persist { ProbeSchema.insert($0, id: id, text: "initial", count: 1) })
		        precondition(model.persist { let r = try ProbeSchema.records($0)[0]; r.text = "updated"; r.count = 42 })
		        precondition(!model.persist { let r = try ProbeSchema.records($0)[0]; r.count = -1 })
		        precondition(model.persist { let r = try ProbeSchema.records($0)[0]; r.count = 43 })
		    case "check":
		        let rows = try ProbeSchema.rows(stack.context)
		        precondition(rows == [Row(id: id, text: "updated", count: 43)])
		    case "delete": precondition(model.persist { for r in try ProbeSchema.records($0) { $0.delete(r) } })
		    case "absent":
		        let rows = try ProbeSchema.rows(stack.context)
		        precondition(rows.isEmpty)
		    default: fatalError("Unknown probe mode")
		    }
		    try stack.close()
		    precondition(stack.isClosed && stack.coordinator.persistentStores.isEmpty)
		    print("fresh-process \(mode) passed pid=\(ProcessInfo.processInfo.processIdentifier)")
		}
		try run()
		"""#
	static let tests = #"""
		import AppModel
		import CoreData
		import Foundation
		import ProbeSupport
		import Testing

		let id = UUID(uuidString: "11111111-1111-4111-8111-111111111111")!
		enum Rejected: Error { case mutation }
		func fixtureRoot() throws -> URL {
		    let url = URL(fileURLWithPath: "/private/tmp/mac-apper-coredata-fixture-\(UUID().uuidString)")
		    try FileManager.default.createDirectory(at: url, withIntermediateDirectories: false)
		    return url
		}
		// An app-specific action publishes only value rows, refreshing after success AND rollback.
		@MainActor final class ProbeActions {
		    let model: ApplicationModel
		    let stack: ApplicationPersistence
		    private(set) var rows: [Row] = []
		    init(_ stack: ApplicationPersistence) { self.stack = stack; model = ApplicationModel(persistence: stack) }
		    func act(_ mutation: (NSManagedObjectContext) throws -> Void) throws -> Bool {
		        let saved = model.persist(mutation)
		        rows = try ProbeSchema.rows(stack.context)
		        return saved
		    }
		}
		@Test(arguments: [false, true]) @MainActor func rollbackValidationRetry(disk: Bool) throws {
		    let root = try fixtureRoot(); defer { try? FileManager.default.removeItem(at: root) }
		    let stack = try disk ? ApplicationPersistence.disk(at: root.appendingPathComponent("data.sqlite"), schema: ProbeSchema.make()) : ApplicationPersistence.inMemory(schema: ProbeSchema.make())
		    defer { try! stack.close() }
		    let actions = ProbeActions(stack)
		    #expect(try actions.act { ProbeSchema.insert($0, id: id, text: "committed", count: 10) })
		    for operation in ["insert", "update", "delete", "save validation"] {
		        #expect(try !actions.act { context in
		            switch operation {
		            case "insert": ProbeSchema.insert(context, id: UUID(), text: "rejected", count: 1)
		            case "update": let row = try #require(ProbeSchema.records(context).first); row.text = "rejected"
		            case "delete": context.delete(try #require(ProbeSchema.records(context).first))
		            default:
		                let row = try #require(ProbeSchema.records(context).first); row.count = -1
		                ProbeSchema.insert(context, id: UUID(), text: "also rejected", count: 1)
		                return // Genuine context.save failure, not a thrown mutation.
		            }
		            throw Rejected.mutation
		        })
		        #expect(actions.rows == [Row(id: id, text: "committed", count: 10)])
		        #expect(!stack.context.hasChanges)
		        #expect(actions.model.state.persistenceError != nil)
		        #expect(actions.model.animation.trigger == .cancelled)
		        if operation == "save validation" {
		            let error = try #require(actions.model.persistenceFailure as NSError?)
		            #expect(error.domain == NSCocoaErrorDomain && error.code == NSManagedObjectValidationError)
		            #expect(error.userInfo[NSValidationKeyErrorKey] as? String == "count")
		        }
		    }
		    #expect(try actions.act { let row = try #require(ProbeSchema.records($0).first); row.text = "retry"; row.count = 11 })
		    #expect(actions.rows == [Row(id: id, text: "retry", count: 11)])
		    #expect(actions.model.state.persistenceError == nil && actions.model.persistenceFailure == nil)
		    #expect(actions.model.animation.trigger == .contentChanged)
		    actions.model.setReduceMotion(true)
		    #expect(try actions.act { _ in })
		    #expect(actions.model.animation.phases.isEmpty)
		    try stack.close()
		    #expect(!actions.model.persist { _ in Issue.record("Closed context must not be used") })
		    #expect(!actions.model.state.storageAvailable)
		}
		@Test @MainActor func isolatedStoresAndOwnership() throws {
		    let root = try fixtureRoot(); defer { try? FileManager.default.removeItem(at: root) }
		    for disk in [false, true] {
		        let first = try disk ? ApplicationPersistence.disk(at: root.appendingPathComponent("first.sqlite"), schema: ProbeSchema.make()) : ApplicationPersistence.inMemory(schema: ProbeSchema.make())
		        let second = try disk ? ApplicationPersistence.disk(at: root.appendingPathComponent("second.sqlite"), schema: ProbeSchema.make()) : ApplicationPersistence.inMemory(schema: ProbeSchema.make())
		        defer { try! first.close(); try! second.close() }
		        #expect(first.context.parent == nil && first.context.persistentStoreCoordinator === first.coordinator)
		        #expect(first.context.concurrencyType == .mainQueueConcurrencyType)
		        #expect(ApplicationModel(persistence: first).persist { ProbeSchema.insert($0, id: id, text: "first", count: 1) })
		        #expect(try ProbeSchema.rows(second.context).isEmpty)
		        #expect(ApplicationModel(persistence: second).persist { ProbeSchema.insert($0, id: id, text: "second", count: 2) })
		        #expect(try ProbeSchema.rows(first.context) == [Row(id: id, text: "first", count: 1)])
		        #expect(try ProbeSchema.rows(second.context) == [Row(id: id, text: "second", count: 2)])
		    }
		    weak var owned: ApplicationPersistence?
		    var model: ApplicationModel?
		    do { let stack = try ApplicationPersistence.inMemory(); owned = stack; model = ApplicationModel(persistence: stack) }
		    #expect(owned != nil)
		    #expect(model!.persist { _ in })
		    try owned!.close(); try owned!.close()
		    #expect(owned!.isClosed && owned!.coordinator.persistentStores.isEmpty)
		    model = nil
		    #expect(owned == nil) // No assertion about immediate framework context deallocation.
		}
		@Test @MainActor func pathsCollisionAndUnavailable() throws {
		    let home = try fixtureRoot(); defer { try? FileManager.default.removeItem(at: home) }
		    let appID = UUID().uuidString
		    let url = try ApplicationPersistence.productionURL(appID: appID, home: home)
		    #expect(url.path == home.appendingPathComponent("Library/Application Support/MacApperGenerated/\(appID.lowercased())/CoreData/data.sqlite").path)
		    let first = try ApplicationPersistence.production(appID: appID, home: home)
		    let model = ApplicationModel(persistence: first)
		    model.title = "Renamed display name"
		    #expect(try ApplicationPersistence.productionURL(appID: appID.lowercased(), home: home) == url)
		    let second = try ApplicationPersistence.production(appID: UUID().uuidString, home: home)
		    #expect(first.coordinator.persistentStores.first?.url != second.coordinator.persistentStores.first?.url)
		    try first.close(); try second.close()
		    let collisionID = UUID().uuidString
		    let collisionURL = try ApplicationPersistence.productionURL(appID: collisionID, home: home)
		    let legacy = collisionURL.deletingLastPathComponent().deletingLastPathComponent().appendingPathComponent("data.store")
		    try FileManager.default.createDirectory(at: legacy.deletingLastPathComponent(), withIntermediateDirectories: true)
		    let bytes = Data("synthetic legacy store: do not open".utf8)
		    for suffix in ["", "-wal", "-shm"] { try bytes.write(to: URL(fileURLWithPath: legacy.path + suffix)) }
		    let unavailable = ApplicationModel.production(appID: collisionID, home: home)
		    #expect(!unavailable.state.storageAvailable && !unavailable.state.controlsEnabled)
		    #expect(unavailable.state.persistenceError?.contains("legacy") == true)
		    #expect(!unavailable.persist { _ in Issue.record("No collision fallback") })
		    #expect(!FileManager.default.fileExists(atPath: collisionURL.deletingLastPathComponent().path))
		    for suffix in ["", "-wal", "-shm"] { #expect(try Data(contentsOf: URL(fileURLWithPath: legacy.path + suffix)) == bytes) }
		    let blockedHome = home.appendingPathComponent("parent-file")
		    try bytes.write(to: blockedHome)
		    let blocked = ApplicationModel.production(appID: UUID().uuidString, home: blockedHome)
		    #expect(!blocked.state.storageAvailable && blocked.state.persistenceError != nil)
		    #expect(!blocked.persist { _ in Issue.record("No load failure fallback") })
		    #expect(try Data(contentsOf: blockedHome) == bytes)
		    let loadFailureID = UUID().uuidString
		    let directoryStore = try ApplicationPersistence.productionURL(appID: loadFailureID, home: home)
		    try FileManager.default.createDirectory(at: directoryStore, withIntermediateDirectories: true)
		    let sentinel = directoryStore.appendingPathComponent("sentinel")
		    try bytes.write(to: sentinel)
		    let loadFailure = ApplicationModel.production(appID: loadFailureID, home: home)
		    #expect(!loadFailure.state.storageAvailable && loadFailure.persistenceFailure != nil)
		    #expect(!loadFailure.persist { _ in Issue.record("No coordinator-load fallback") })
		    #expect(try Data(contentsOf: sentinel) == bytes)
		    #expect(!ApplicationModel.production(appID: "invalid-id", home: home).state.storageAvailable)
		    #expect(throws: (any Error).self) { try ApplicationPersistence.disk(at: URL(string: "https://invalid.test/store")!) }
		}
		@Test @MainActor func emptySchemaAndTransientPresentation() throws {
		    let root = try fixtureRoot(); defer { try? FileManager.default.removeItem(at: root) }
		    let stack = try ApplicationPersistence.disk(at: root.appendingPathComponent("empty.sqlite"))
		    #expect(stack.schema.entities.isEmpty)
		    #expect(ApplicationModel(persistence: stack).persist { _ in })
		    try stack.close()
		    let reopened = try ApplicationPersistence.disk(at: root.appendingPathComponent("empty.sqlite"))
		    defer { try! reopened.close() }
		    #expect(reopened.schema.entities.isEmpty)
		    let model = ApplicationModel()
		    let other = ApplicationModel()
		    var firstCoordinator: NSPersistentStoreCoordinator?
		    let firstSaved = model.persist { context in
		        firstCoordinator = context.persistentStoreCoordinator
		        #expect(firstCoordinator?.persistentStores.first?.type == NSInMemoryStoreType)
		        #expect(firstCoordinator?.persistentStores.first?.url?.isFileURL != true)
		    }
		    #expect(firstSaved)
		    let secondSaved = other.persist { context in
		        #expect(context.persistentStoreCoordinator !== firstCoordinator)
		        #expect(context.persistentStoreCoordinator?.persistentStores.first?.type == NSInMemoryStoreType)
		    }
		    #expect(secondSaved)
		    #expect(model.state.storageAvailable && model.title == "Your app")
		    model.apply(title: "Edited", detail: "Detail")
		    #expect(model.state.resetEnabled && model.animation.trigger == .contentChanged)
		    model.setReduceMotion(true); model.reset()
		    #expect(model.title == "Your app" && model.detail == "Ready to create." && model.animation.phases.isEmpty)
		}
		"""#
}
