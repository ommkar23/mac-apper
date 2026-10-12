// @frontmatter:start
// Supplies synthetic typed Core Data records, model actions, tests and fresh-process probes for the offline scaffold scenario.
// @frontmatter:end
import Foundation
import Testing

@MainActor enum ScaffoldDevToolsFixture {
	static func install(in root: URL) throws {
		let persistence = root.appendingPathComponent("Sources/AppModel/Persistence.swift")
		let original = try String(contentsOf: persistence, encoding: .utf8)
		try #require(original.contains("schema.entities = []"))
		try original.replacingOccurrences(
			of: "schema.entities = []", with: "schema.entities = [FixtureRecords.entity()]"
		)
		.write(to: persistence, atomically: true, encoding: .utf8)
		let model = root.appendingPathComponent("Sources/AppModel/ApplicationModel.swift")
		let modelSource = try String(contentsOf: model, encoding: .utf8)
		try (modelSource + action).write(to: model, atomically: true, encoding: .utf8)
		let manifest = root.appendingPathComponent("Package.swift")
		let package = try String(contentsOf: manifest, encoding: .utf8)
		try #require(package.contains("exact: \"6.2.3\""))
		try package.replacingOccurrences(
			of: ".target(name: \"AppModel\"),",
			with:
				".target(name: \"AppModel\"), .executableTarget(name: \"PersistenceProbe\", dependencies: [\"AppModel\"]),"
		)
		.write(to: manifest, atomically: true, encoding: .utf8)
		for (path, source) in [
			"Sources/AppModel/FixtureRecords.swift": entity,
			"Tests/AppModelTests/PackagedPersistenceTests.swift": tests,
			"Sources/PersistenceProbe/main.swift": probe,
			"Sources/AppViews/PersistencePreview.swift": preview,
		] {
			let url = root.appendingPathComponent(path)
			try FileManager.default.createDirectory(
				at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
			try source.write(to: url, atomically: true, encoding: .utf8)
		}
	}

	static let entity = #"""
		#if compiler(<6.4)
		#error("Swift 6.4 is required")
		#endif
		import Foundation
		import CoreData
		@objc(PackagedFixtureRecord) public final class FixtureRecord: NSManagedObject {
		    @NSManaged public var id: UUID
		    @NSManaged public var text: String
		    @NSManaged public var count: Int64
		}
		@MainActor public enum FixtureRecords {
		    public static let id = UUID(uuidString: "11111111-1111-4111-8111-111111111111")!
		    public static func entity() -> NSEntityDescription {
		        let entity = NSEntityDescription()
		        entity.name = "FixtureRecord"
		        entity.managedObjectClassName = NSStringFromClass(FixtureRecord.self)
		        func attribute(_ name: String, _ type: NSAttributeType) -> NSAttributeDescription {
		            let value = NSAttributeDescription()
		            value.name = name; value.attributeType = type; value.isOptional = false
		            return value
		        }
		        let count = attribute("count", .integer64AttributeType)
		        count.setValidationPredicates([NSPredicate(format: "SELF >= 0")], withValidationWarnings: ["nonnegative count"])
		        entity.properties = [attribute("id", .UUIDAttributeType), attribute("text", .stringAttributeType), count]
		        return entity
		    }
		    public static func records(_ context: NSManagedObjectContext) throws -> [FixtureRecord] {
		        try context.fetch(NSFetchRequest<FixtureRecord>(entityName: "FixtureRecord"))
		    }
		    public static func put(_ context: NSManagedObjectContext, count: Int64) throws {
		        let rows = try records(context)
		        let row = rows.first ?? FixtureRecord(entity: context.persistentStoreCoordinator!.managedObjectModel.entities[0], insertInto: context)
		        row.id = id; row.text = "saved fixture"; row.count = count
		    }
		}
		"""#
	static let action = #"""

		extension ApplicationModel {
		    @discardableResult public func saveFixture(count: Int64) -> Bool {
		        let saved = persist { try FixtureRecords.put($0, count: count) }
		        // Re-fetch after save OR rollback; only value presentation leaves this model.
		        if let persistence, !persistence.isClosed {
		            do {
		                let rows = try FixtureRecords.records(persistence.context)
		                state.title = String(rows.first?.count ?? 0)
		                state.detail = rows.first?.text ?? "No fixture record"
		            } catch { state.persistenceError = error.localizedDescription }
		        }
		        return saved
		    }
		}
		"""#
	static let tests = #"""
		import AppModel
		import CoreData
		import Foundation
		import Testing
		@Test @MainActor func packagedTypedCoreDataSaveRollbackReopen() throws {
		    let home = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("packaged-coredata-\(UUID().uuidString)")
		    defer { try? FileManager.default.removeItem(at: home) }
		    let url = try ApplicationPersistence.productionURL(appID: FixtureRecords.id.uuidString, home: home)
		    #expect(url.path.hasSuffix("MacApperGenerated/11111111-1111-4111-8111-111111111111/CoreData/data.sqlite"))
		    let stack = try ApplicationPersistence.disk(at: url)
		    defer { try? stack.close() }
		    #expect(stack.context.concurrencyType == .mainQueueConcurrencyType)
		    #expect(stack.context.persistentStoreCoordinator === stack.coordinator)
		    let model = ApplicationModel(persistence: stack)
		    let saved = model.saveFixture(count: 43)
		    #expect(saved && model.title == "43")
		    let rejected = model.saveFixture(count: -1)
		    #expect(!rejected && model.title == "43" && model.persistenceFailure != nil)
		    try stack.close()
		    #expect(stack.isClosed && stack.coordinator.persistentStores.isEmpty)
		    let reopened = try ApplicationPersistence.disk(at: url)
		    defer { try? reopened.close() }
		    let rows = try FixtureRecords.records(reopened.context)
		    #expect(rows.count == 1)
		    #expect(rows.first?.id == FixtureRecords.id && rows.first?.text == "saved fixture" && rows.first?.count == 43)
		    let memory = try ApplicationPersistence.inMemory()
		    defer { try? memory.close() }
		    #expect(try FixtureRecords.records(memory.context).isEmpty)
		    let transient = ApplicationModel(persistence: memory)
		    transient.apply(title: "Transient only", detail: "Not a stored record")
		    #expect(try FixtureRecords.records(memory.context).isEmpty)
		    print("PACKAGED_TYPED_ASSERTIONS: save rollback UUID text count reopen memory/transient passed; compiler >=6.4")
		}
		"""#
	static let probe = #"""
		import AppModel
		import Foundation
		@MainActor func run() throws {
		    let mode = CommandLine.arguments[1]
		    let home = URL(fileURLWithPath: CommandLine.arguments[2])
		    let url = try ApplicationPersistence.productionURL(appID: FixtureRecords.id.uuidString, home: home)
		    let stack = try ApplicationPersistence.disk(at: url)
		    defer { try? stack.close() }
		    let model = ApplicationModel(persistence: stack)
		    switch mode {
		    case "write": precondition(model.saveFixture(count: 43))
		    case "check":
		        let rows = try FixtureRecords.records(stack.context)
		        precondition(rows.count == 1 && rows[0].id == FixtureRecords.id && rows[0].text == "saved fixture" && rows[0].count == 43)
		    case "delete": precondition(model.persist { for row in try FixtureRecords.records($0) { $0.delete(row) } })
		    case "absent":
		        let rows = try FixtureRecords.records(stack.context)
		        precondition(rows.isEmpty)
		    default: fatalError("unknown mode")
		    }
		    try stack.close()
		    precondition(stack.isClosed && stack.coordinator.persistentStores.isEmpty)
		    print("PACKAGED_FRESH_PROCESS: \(mode) passed pid=\(ProcessInfo.processInfo.processIdentifier) path=\(url.path)")
		}
		try run()
		"""#
	static let preview = #"""
		import AppModel
		import SwiftUI
		private struct PersistenceFixtureView: View {
		    let model: ApplicationModel
		    var body: some View { model.title == "43" ? Color.red : Color.blue }
		}
		#if MAC_APPER_PREVIEW
		@MainActor public func apperPreview_PersistenceFixture() -> some View {
		    let model = ApplicationModel()
		    precondition(model.saveFixture(count: 43))
		    return PersistenceFixtureView(model: model)
		}
		#endif
		"""#
}
