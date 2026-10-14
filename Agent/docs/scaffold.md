# Scaffold and persistence

[Agent introduction](../README.md) · [Runtime](runtime.md) · [Verification](verification.md) · [Recorded evidence](evidence.md)

## New-project contract

- **Project contract**
  - Generated projects are working Swift packages with shared model/views, separate production and no-input preview executables, tests, protected rendering/packaging infrastructure and an initial Git commit.
  - Scaffold v9 supplies offline-first programmatic Core Data for new Create projects.
  - It adds bundle-derived default window titles without automatic source or store migration.
- **Persistence ownership**
  - `Sources/AppModel/Persistence.swift` defines main-actor ApplicationPersistence owning an NSManagedObjectModel, coordinator and directly store-backed main-queue context.
  - Editable `makeSchema()` registers app-specific typed NSManagedObject subclasses with `@NSManaged` properties, explicit entity/class names, attributes, optionality and validation, starting from an empty schema without a universal entity, SwiftData macros, momc or Xcode model files.
  - Independent `inMemory(schema:)` and `disk(at:schema:)` factories isolate stores, with default models/previews in memory and production at `~/Library/Application Support/MacApperGenerated/<lowercase-app-uuid>/CoreData/data.sqlite` rather than display-name or v7 `data.store` paths.
  - Any same-ID legacy main file/sidecar visibly refuses startup without opening, converting or modifying it or silently creating a replacement empty store.
  - Test-only homes may be passed explicitly, while production defaults to the user's home.
  - The context uses an owned error merge policy with automatic/inferred migration disabled, and model actions explicitly save or roll back before re-fetching value projections.
  - Initialization/save errors remain visible without reset or memory fallback.
  - `close()` rolls back, resets and removes attached stores for orderly teardown, is idempotent after success, and sets `isClosed` to prevent mutation and make later context access a precondition failure without promising immediate framework deallocation.
- **Model and view ownership**
  - `ApplicationModel.swift` retains persistence and owns rules/actions/errors/transition intent, preserving protected `ApplicationModel()`, `production(appID:)`, title/detail/apply/reset and reduced-motion APIs.
  - Starter title/detail are transient presentation rather than persistent user records.
  - `ApplicationState.swift` is model-owned value presentation and `ApplicationRoot.swift` renders it and forwards actions without receiving contexts or managed objects.
  - Backend support, relationships, schema evolution/conversion and sync/background/multiwriter architecture require separately scoped implementation and evidence rather than speculative scaffold support.

## Editable and protected inventory

- Extend editable `Sources/AppModel/ApplicationModel.swift`, `ApplicationState.swift`, `Persistence.swift`, `Sources/AppViews/ApplicationRoot.swift` and `Tests/AppModelTests/` rather than replacing the package.
- [BaseAppTemplate](../Sources/Application/BaseAppTemplate.swift) defines v9 and the package/model/view templates; [ScaffoldPersistenceTemplate](../Sources/Application/ScaffoldPersistenceTemplate.swift) defines the schema/state APIs.
- [PreviewTemplate](../Sources/Application/PreviewTemplate.swift) supplies protected Package.swift/Package.resolved, Scaffold.version, app-manifest.json, PreviewContract, PreviewSupport, PreviewApp, ProductionApp and DevExtension sources.
- [ProjectScaffold](../Sources/Application/ProjectScaffold.swift) creates a UUID project, copies bundled resources and commits an initial Git baseline. Validation requires the supported scaffold version, exact protected bytes and expected protected-directory inventories through bounded nonlinked source collection.
- Protected ProductionApp constructs ApplicationModel.production(appID:) with the stable UUID; preserve default initialization, production factory, title/detail/apply/reset and reduced-motion APIs used by protected infrastructure.
- Unsupported versions are preserved and rejected, not silently upgraded. The rollout provides no automatic legacy source/store conversion or dual-engine support.

## App naming and window titles

- The project's `Info.plist` owns app branding.
- `set_app_name` and rename update both `CFBundleDisplayName` and `CFBundleName` through the same validated path.
- Production packaging reads the canonical display name before building.
- Names retain the existing 1–64-character policy without silent truncation.
- Packaging preserves its own executable, identifier and version fields.
- Development naming validation belongs to [DevTools Run](../../apps/built-in/dev-tools/docs/tools.md#run).
- The protected v9 production scene uses the packaged `CFBundleDisplayName`, then `CFBundleName`, as literal title text.
- Missing or blank bundle names fall back to `Generated App`.
- Editable window content may use SwiftUI `navigationTitle` to override that default.
- The earlier `Application` title was a default, not a ban on supported overrides.
- Existing v8 sources are preserved and rejected by current scaffold validation rather than rewritten.
- Naming does not change app UUIDs or persistence paths.
- Naming relies on correct bundle metadata and SwiftUI API wiring.
- [Source-wiring tests](../Tests/AgentApplicationTests/ScaffoldNamingTests.swift) retain checks for protected title composition and supported overrides.
- [AppName tests](../Tests/AgentApplicationTests/AppNameTests.swift) and [name/rename extension tests](../Tests/AgentApplicationTests/NameAndRenameExtensionTests.swift) retain project-owned naming logic coverage.
- [DevTools branding tests](../../apps/built-in/dev-tools/Tests/DevToolsXPCServiceTests/RunControllerTests.swift) retain shared validation and staging coverage.
- Scene compiler probes, synthetic Bundle execution and CoreGraphics window observation are retired naming checks.
- App-name rendering and actual native-window titles are not independently verified.
- Correct API wiring does not guarantee all generated app behavior.

## Tool integration and previews

- Use scoped DevTools Build/Test/Preview/Run and inspect typed statuses independently of XPC/Pi success. Test passes only with status passed and exitCode 0; repairs require a new pass after edits.
- The current DevTools Preview compiles a guarded public @MainActor zero-argument synchronous nonthrowing apperPreview_NAME() -> some View factory under MAC_APPER_PREVIEW in an isolated executable; seed representative in-memory model states.
- Its owned NSHostingView native renderer is separate from the protected PreviewApp template. Do not rewrite protected preview infrastructure to imitate the current DevTools renderer.
- Preview returns text-only validated PNG paths/dimensions/metadata, not automatic image delivery. Optional inspection uses production read, preferably absolute artifact.reviewPath retained after project cleanup; relativePath works while the project exists. No read or cross-tool order is mandatory.
- Preview capture is initial-state evidence, not button interaction, async readiness or universal visual fidelity. Build/Run do not create production bundles. Detailed canvas, factory, capture, archive and failure contracts belong to [DevTools](../../apps/built-in/dev-tools/README.md).

## Verification scope and remaining limits

- The always-run typed-entity scaffold check covers independent memory/disk stores, CRUD rollback, real validation-save failure/retry, value projections, empty schema, close/ownership, unavailable storage and synthetic same-ID legacy collision refusal. Fresh processes verify SQLite insert/update/retry, reopen and deletion under standalone Swift 6.4 strict concurrency/warnings-as-errors, CLT SDK and Testing 6.2.3.
- [No-model scaffold integration](verification.md#no-model-scaffold-integration) separately exercises fresh service preparation plus packaged Test/Preview/Build/Run and explicit fixture-home persistence.
- Recorded protected-production default-home relaunch checks use fixture model actions and normal termination/close, not physical UI clicks, crash durability or generated-counter relaunch persistence; see [v8 evidence](evidence.md#final-v8-artifact-and-production-path-smoke).
- Relationships, schema migration, corrupt-store preservation, arbitrary projection-fetch recovery, path-hardening guarantees, immediate framework-context deallocation, optional API sync and background/multiwriter architecture are not established by these checks.
- Historical v7 SwiftDataMacros failures do not make Xcode a current requirement; current new projects use programmatic Core Data.
