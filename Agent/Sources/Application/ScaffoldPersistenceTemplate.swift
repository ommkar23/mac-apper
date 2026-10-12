// @frontmatter:start
// Provides editable Core Data persistence and presentation-state source templates for offline-first generated apps.
// @frontmatter:end
import Foundation

extension BaseAppTemplate {
	static var persistenceFiles: [String: String] {
		[
			"Sources/AppModel/Persistence.swift": #"""
			import Foundation
			import CoreData

			/// One main-queue, directly store-backed context. Model actions explicitly save or roll back.
			@MainActor public final class ApplicationPersistence {
			    /// Extend with app-specific NSManagedObject subclasses and NSEntityDescription definitions.
			    /// Set explicit entity/class names, attribute types, optionality and validation predicates.
			    /// No universal placeholder entity, automatic migration, or backend sync is supplied.
			    public static func makeSchema() -> NSManagedObjectModel {
			        let schema = NSManagedObjectModel()
			        schema.versionIdentifiers = ["application-1"] // App schema identity, not scaffold version.
			        schema.entities = []
			        return schema
			    }
			    public let schema: NSManagedObjectModel
			    public let coordinator: NSPersistentStoreCoordinator
			    private var ownedContext: NSManagedObjectContext?
			    public private(set) var isClosed = false
			    public var context: NSManagedObjectContext {
			        precondition(!isClosed, "Persistence is closed")
			        return ownedContext!
			    }

			    private init(schema: NSManagedObjectModel, type: String, url: URL?) throws {
			        self.schema = schema
			        coordinator = NSPersistentStoreCoordinator(managedObjectModel: schema)
			        let context = NSManagedObjectContext(concurrencyType: .mainQueueConcurrencyType)
			        ownedContext = context
			        context.persistentStoreCoordinator = coordinator
			        context.mergePolicy = NSMergePolicy(merge: .errorMergePolicyType)
			        context.undoManager = nil
			        _ = try coordinator.addPersistentStore(ofType: type, configurationName: nil, at: url, options: [
			            NSMigratePersistentStoresAutomaticallyOption: false,
			            NSInferMappingModelAutomaticallyOption: false
			        ])
			    }

			    public static func inMemory(schema: NSManagedObjectModel? = nil) throws -> ApplicationPersistence {
			        try ApplicationPersistence(schema: schema ?? makeSchema(), type: NSInMemoryStoreType, url: nil)
			    }

			    public static func disk(at url: URL, schema: NSManagedObjectModel? = nil) throws -> ApplicationPersistence {
			        guard url.isFileURL else { throw CocoaError(.fileWriteUnsupportedScheme) }
			        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(),
			            withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
			        return try ApplicationPersistence(schema: schema ?? makeSchema(), type: NSSQLiteStoreType, url: url)
			    }

			    /// Explicit home injection is for isolated fixtures. Display names never select storage.
			    public static func productionURL(appID: String, home: URL? = nil) throws -> URL {
			        guard let id = UUID(uuidString: appID) else { throw CocoaError(.fileWriteInvalidFileName) }
			        let home = home ?? FileManager.default.homeDirectoryForCurrentUser
			        guard home.isFileURL else { throw CocoaError(.fileWriteUnsupportedScheme) }
			        return home.appendingPathComponent(
			            "Library/Application Support/MacApperGenerated/\(id.uuidString.lowercased())/CoreData/data.sqlite")
			    }
			    public static func production(appID: String, home: URL? = nil) throws -> ApplicationPersistence {
			        let url = try productionURL(appID: appID, home: home)
			        let legacy = url.deletingLastPathComponent().deletingLastPathComponent().appendingPathComponent("data.store")
			        for suffix in ["", "-wal", "-shm"] {
			            if FileManager.default.fileExists(atPath: legacy.path + suffix) {
			                throw StorageError.legacyStorePresent
			            }
			        }
			        return try disk(at: url)
			    }
			    private enum StorageError: LocalizedError {
			        case legacyStorePresent
			        var errorDescription: String? {
			            "Preserved legacy storage exists for this app identity. It was not opened or converted. Core Data storage cannot start."
			        }
			    }
			    /// Close fixture connections before removing directories; framework objects may outlive this call.
			    public func close() throws {
			        if isClosed { return }
			        context.rollback()
			        context.reset()
			        for store in coordinator.persistentStores { try coordinator.remove(store) }
			        ownedContext = nil
			        isClosed = true
			    }
			}
			"""#,
			"Sources/AppModel/ApplicationState.swift": #"""
			import Foundation

			/// A model-owned presentation projection, not an independently mutable copy of persistent records.
			public struct ApplicationState {
			    public var title = "Your app"
			    public var detail = "Ready to create."
			    public var titleLabel = "Title"
			    public var detailLabel = "Detail"
			    public var resetLabel = "Reset"
			    public var storageAvailable = false
			    public var persistenceError: String?
			    public var animation = AnimationIntent.transition(trigger: .cancelled, reduceMotion: false)
			    public var controlsEnabled: Bool { storageAvailable }
			    public var resetEnabled: Bool { controlsEnabled && (title != "Your app" || detail != "Ready to create.") }
			    public var statusMessage: String { persistenceError ?? "" }
			    public init() {}
			}
			"""#,
		]
	}
}
