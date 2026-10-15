# DevTools verification

[DevTools](../README.md) · [Tools](tools.md) · [Preview](preview.md)

Commands below run from the repository root and require authorization for their actual effects. Earlier documentation-rewrite notes describe static checks only. Selected isolation verification is recorded separately below.

## Package entry points

- Select standalone Swift 6.4 explicitly and use default Swift Build:

  ```sh
  swift64="$HOME/Library/Developer/Toolchains/swift-6.4.0-RELEASE.xctoolchain/usr/bin/swift"
  # Unit/contract/service checks only; excludes signed-host scenario entry points.
  "$swift64" test --package-path apps/built-in/dev-tools \
    --filter 'DevTools(ContractTests|Tests|XPCServiceTests)'
  # Whole package, including provider scenarios and development launch fixture.
  "$swift64" test --package-path apps/built-in/dev-tools
  ```

- `DevToolsContractTests` owns schemas/architecture; `DevToolsTests` owns project resolution/boundary checks; `DevToolsXPCServiceTests` owns controller/process/toolchain/real-rendering tests; `DevToolsScenarioTests` owns signed generated-client/XPC fixtures.
- Root `swift test` is not a substitute for this package. Underlying runtime/library changes require focused tests and the affected package suite; scenario-only changes use selected cases rather than unrelated units.
- The [Plugins guide](../../../../Plugins/README.md) owns optional clean-test/private-scratch mechanics. A custom build-product directory must be passed via `DEV_TOOLS_SCENARIO_PRODUCTS`; retained default caches are not proof of a fresh build. Never pass an empty scratch path or delete unrelated retained artifacts.

## Naming unit verification

- The focused pre-implementation routing regression compiled against the old contract and failed because `set_app_name` had no successful route.
- `SetAppNameControllerTests` exercises the generated in-process service router and factory. It does not start a signed host or Pi.
- Coverage includes canonical names, Unicode code points, both branding keys, unrelated values, binary/XML format, private permissions, missing/malformed/linked/nonregular/oversized metadata, bounded replacement output, invalid scope and busy-gate rejection without mutation.
- `OpenXPCSpecTests` checks the six-operation contract, generated controller routing and sole generated declaration. It checks 4096-byte injected scope, 256-byte name records, 1024-byte summary and the Pi 1–64-character schema.
- Authorized unit-only commands exclude `DevToolsScenarioTests` execution:

  ```sh
  "$swift64" test --package-path apps/built-in/dev-tools \
    --filter 'setAppName|devToolsOpenXPCSpecDefinesBoundedPreviewPathTool'
  "$swift64" test --package-path apps/built-in/dev-tools \
    --filter 'DevTools(ContractTests|Tests|XPCServiceTests)'
  ```

- SwiftPM may compile scenario targets even with these execution filters. Compilation is not signed-host or scenario execution.
- Source and unit verification do not establish deployed registration or native rename/repackaging behavior. Signed-host scenarios and final app bundle recreation require separate authorization.

## Preview phase diagnostics checks

- Run focused offline checks with scenario gates unset, validated private scratch and repository-local `TMPDIR`:

  ```sh
  "$swift64" test --package-path apps/built-in/dev-tools --scratch-path "$scratch" \
    --filter 'preview(CompletedChildFailures|CleanupFailures|CancellationRemains|Diagnostic|ProductionDiagnostic|DiscoveryDiagnostics|RealOutputOverflow)'
  ```

- Injection covers all seven subprocess phases with unchanged timeouts and output limits. It checks stable error codes, metadata-only summaries, no later phase, no artifact/dimensions, original-source preservation, completed-failure removal and exact cleanup-uncertainty/cancellation propagation.
- Unicode/control checks enforce the 4096 UTF-8 byte bound and output omission. A real local output-overflow child must reach ESRCH before fixture removal. These focused checks need no signed service.
- Follow focused checks with the restricted unit/contract/service selection above. Signed-provider verification and bundle recreation are separate authorized paths.
- See [Preview diagnostics](preview.md#results-and-diagnostics) for the result contract. Overflow alone does not identify a historical subprocess phase or establish a PNG-size failure. Controlled regressions do not prove historical causation.

## Provider scenarios

- [Scenario](../../../../Scenario/README.md) owns reusable signed-host preparation, compiler helpers and lifecycle APIs. DevTools tests own prompts/assertions, fixtures and provider selections; no full Mac Apper.app build/copy or retired Scenario runner/plugin is required.
- Load [scenario-run](../../../../.pi/skills/scenario-run/SKILL.md) for authorized execution/monitoring and [scenario-write](../../../../.pi/skills/scenario-write/SKILL.md) for authoring.
- Each selected collection stages the generated terminal client and real DevTools service in a disposable signed `DevToolsScenario.app`.
- Naming, Test, standalone Build/Run, Plan and Preview use explicit UUID fixture roots beneath private repository `.tmp/` homes. Both client and service receive `HOME` and `CFFIXED_USER_HOME` before startup. Only the installed compiler is linked into those homes. Each Preview case owns an independent home, host and lifecycle.
- No Pi session or model/MCP/Gemini calls are required. No-model does not mean air-gapped dependency resolution. Build/Run still executes generated native code.
- `DEV_TOOLS_SCENARIO_CASE` selects one case within the chosen naming/Plan/Test/Preview entry point; omit it for that entry point's collection. Unset it before selecting the entire `DevToolsScenarioTests` target, since a name from one collection is not valid in another.

  ```sh
  # Complete provider scenario target (includes the production read prerequisite below).
  "$swift64" test --package-path apps/built-in/dev-tools --filter DevToolsScenarioTests
  # Initial-task plan creation/rejection only.
  DEV_TOOLS_SCENARIO_CASE=plan-initial-tasks "$swift64" test \
    --package-path apps/built-in/dev-tools --filter devToolsPlanScenarios
  # All plan cases.
  "$swift64" test --package-path apps/built-in/dev-tools --filter devToolsPlanScenarios
  # Real package testing: passes, failures, repair and scope rejection.
  DEV_TOOLS_SCENARIO_CASE=test-package "$swift64" test \
    --package-path apps/built-in/dev-tools --filter devToolsTestScenarios
  # Compiler selection plus owned development launch (no case selector).
  "$swift64" test --package-path apps/built-in/dev-tools --filter devToolsToolchainBuildRunScenario
  ```

### Metadata-only naming scenarios

- `devToolsSetAppNameScenarios` owns two cases. Each uses `DevToolsScenarioLifecycle`, generic Scenario hosting and the actual signed generated `DevToolsTerminalClient`.
- `set-app-name-canonical` checks sanitation to `Pebble Counter`, both branding keys, unrelated nested plist values and unchanged manifest/package bytes. It roundtrips 64 emoji (256 UTF-8 bytes), U+0085 and decomposed Unicode scalars without assertion-side normalization.
- `set-app-name-rejections` checks invalid names and a different registered project's root with the original project ID. Every rejection requires an identified `operationFailed` envelope and byte-identical metadata in both fixtures.
- Exact project/root inventories exclude development staging, build scratch and production output. These checks do not establish library labels, model tool selection, native titles or packaging behavior. Provider Unicode acceptance does not establish consistency with Agent/development sanitation.
- Build current prerequisite `DevToolsApplication` and `DevToolsTerminalClient` products before an authorized run. No Preview resource bundle, installed Pi read module, credentials, Pi or live calls are needed. Compilation and offline helper tests do not execute these scenarios.
- After integrated acceptance and separate execution authorization, run selected cases sequentially. Stop after the first failure. Do not select the whole provider target:

  ```sh
  # First check both explicit standalone executables and their required 6.4.0 versions.
  toolchain="$HOME/Library/Developer/Toolchains/swift-6.4.0-RELEASE.xctoolchain/usr/bin"
  test -x "$toolchain/swift" && test -x "$toolchain/swiftc" || exit 1
  "$toolchain/swift" --version
  "$toolchain/swiftc" --version
  swift64="$toolchain/swift"
  export TMPDIR="$PWD/.tmp/"
  # Use a validated, private, nonempty scratch path beneath repository-root .tmp/.
  "$swift64" build --package-path apps/built-in/dev-tools --scratch-path "$scratch" \
    --product DevToolsApplication
  "$swift64" build --package-path apps/built-in/dev-tools --scratch-path "$scratch" \
    --product DevToolsTerminalClient
  products=$("$swift64" build --package-path apps/built-in/dev-tools \
    --scratch-path "$scratch" --show-bin-path) || exit 1
  DEV_TOOLS_SCENARIO_PRODUCTS="$products" DEV_TOOLS_SCENARIO_CASE=set-app-name-canonical \
    "$swift64" test --package-path apps/built-in/dev-tools --scratch-path "$scratch" \
    --filter devToolsSetAppNameScenarios
  # Only after the canonical case passes and cleanup is confirmed:
  DEV_TOOLS_SCENARIO_PRODUCTS="$products" DEV_TOOLS_SCENARIO_CASE=set-app-name-rejections \
    "$swift64" test --package-path apps/built-in/dev-tools --scratch-path "$scratch" \
    --filter devToolsSetAppNameScenarios
  ```

- Omit `DEV_TOOLS_SCENARIO_CASE` only when the entire naming collection is authorized. The generic collection does not stop after a case failure. Direct Swift test selection works independently of the developer helper allowlist.
- Requests must be confirmed before exact service reaping. No development child is started. Successful assertions and confirmed service exit gate registered-project, signed-host and private-home removal. Partial setup remains registered. Unknown transport/completion, capture/reaping failure or failed assertions retain fixtures through the shared lifecycle.
- Offline-only regression selection is `--filter 'SetAppNameScenarioHelperTests|DevToolsScenarioLifecycleTests'`. It checks allocation-free registration and fail-closed request classification plus the existing cleanup seams. Signed naming cases remain **NOT RUN** in this implementation wave.

### Plan and Test coverage

- `plan-initial-tasks`: seeded creation/retrieval, duplicate-plan rejection, invalid initial tasks/IDs without consuming the creation slot, empty-plan isolation.
- `plan-lifecycle`: repeated additions, updates and multi-delete ending in a retrievable empty plan.
- `plan-rejections`: malformed/missing updates and second-in-progress rejection without mutation.
- `plan-project-isolation`: separate plans per project, independent of session identity.
- `test-package`: two real Swift Testing targets, successful execution, assertion failure, compilation failure, repaired pass, foreign-scope rejection and source/request-scratch preservation. Fixtures use pinned Testing and an explicit macOS 14 deployment target rather than XCTest. The passing model test checks inherited private-home values and access to both standalone compiler executables.
- `devToolsToolchainBuildRunScenario`: requires compiler 6.4. It validates generated-client Build/Run metadata, complete scoped staging paths, source preservation and absence of project `.build`. The child checks private-home/compiler inheritance before writing its marker. It waits at most 60 seconds for a fixture-only release marker.
- The parent polls and validates the marker, captures immutable identity by the exact staged binary, immediately caches it, corroborates the marker PID and writes release in one synchronous MainActor window. There is no await or actor hop before release. Polling remains bounded to 10 seconds. Exact capture keeps its default bound. The child lease remains 60 seconds.
- The marker PID is only corroboration, never signaling authority. A mismatch preserves the cached exact identity for teardown. Capture failure never releases the child and still fails closed. Natural exit must reach ESRCH. This is development launch evidence, not UI readiness or production packaging.

### Build/Run acquisition scheduling regression

- Run focused offline handshake/lifecycle checks with validated private scratch and repository-local `TMPDIR`:

  ```sh
  "$swift64" test --package-path apps/built-in/dev-tools --scratch-path "$scratch" \
    --filter 'ToolchainScenarioHandshakeTests|DevToolsScenarioLifecycleTests'
  ```

- `ToolchainScenarioHandshakeTests` exercises the helper called by Build/Run. Controlled clock, readiness, waiting, discovery and release seams check the bounded acquisition window.
- Acquisition captures, immediately caches and corroborates the exact child identity before release in one synchronous MainActor window. No await or actor hop occurs before release. A controlled queued actor job checks release ordering without relying on Task.yield, priorities or scheduler luck.
- Coverage includes the missing-marker deadline, linked/oversized/malformed markers, cached identity on PID mismatch, no release on capture failure and cached identity on release failure. The marker PID is corroboration, not signaling authority.
- A copied local executable checks kernel path/start/PID agreement and ESRCH with a parent-written marker. The separately authorized `devToolsToolchainBuildRunScenario` checks the child-written marker/release protocol, private-home/compiler inheritance and child/service cleanup through signed XPC.
- These harness regressions do not establish a historical actor schedule, lease-expiry cause or child exit status. They do not change provider runtime, Preview or Scenario ownership contracts.

### Preview prerequisites, selections and coverage

- Preview supplies renderer resources before host signing. It stages the generated extension without a source-tree fallback. A test-only registration harness executes the unmodified extension against the real generated client/service. It does not start a Pi session.
- The harness observes real spawn calls without changing arguments, options or client traffic. Bounded LF-framed records must correlate executable, project/session/request IDs and actual child close. Only controlled expected scope rejection accepts an identified `operationFailed`. Unexpected failures remain uncertainty. Completed ordinary rendering errors retain failure-recovery semantics. Generic `isError` alone never confirms completion.
- Node and the installed production-read harness receive only deliberate home/tmp, scope, executable/module and PATH values. The generated extension forwards the narrow production home/tmp and authoritative ID allowlist. Signature-normalized owned copies verify real client executable bytes. Extension bytes are checked directly. The signed host and current products are never modified for this audit.
- `preview-path-content` additionally requires the installed Pi production read module. Set an actual absolute installed path, not the illustrative placeholder, before selecting it or the whole Preview/provider target:

  ```sh
  export DEV_TOOLS_SCENARIO_PI_READ_MODULE="/absolute/installed/pi/dist/core/tools/read.js"
  "$swift64" test --package-path apps/built-in/dev-tools --filter devToolsPreviewScenarios
  DEV_TOOLS_SCENARIO_CASE=preview-path-content "$swift64" test \
    --package-path apps/built-in/dev-tools --filter devToolsPreviewScenarios
  # Other single cases do not need that read-module prerequisite.
  DEV_TOOLS_SCENARIO_CASE=preview-render "$swift64" test \
    --package-path apps/built-in/dev-tools --filter devToolsPreviewScenarios
  ```

- `preview-render`: seeded file-private view pixels and original-source preservation.
- `preview-size`: default/custom canvases and invalid bounds.
- `preview-factories`: missing/comment-only, ambiguous and production-visible factories.
- `preview-failure-recovery`: compiler/worker errors followed by recovery and scratch cleanup.
- `preview-scope`: traversal, linked sources and foreign project-root rejection.
- `preview-path-content`: text-only metadata, typed rendering errors versus failed transport, installed read of both PNG paths and retained archive readability after project deletion.
- `DEV_TOOLS_PREVIEW_EXPORT_DIR` may name an existing nonlinked directory for unique validated PNG copies without disabling fixture cleanup. Archive retention is separate from delivery/project cleanup.

### Cleanup boundaries and source-inspected limit

- Selected naming, Test, standalone Build/Run, Plan and Preview own partial setup through `DevToolsScenarioLifecycle`. Typed or independently correlated request completion establishes quiescence only for these controlled fixtures. Unexpected thrown transport/operation calls leave quiescence unconfirmed. There is no invented drain API.
- All Preview retention-critical assertions throw. A final step marks success only after every assertion succeeds. Controlled expected rendering/rejection errors are functional assertions, not case failures.
- Preview strictly reads returned archive paths through no-follow descriptors. It compares existing parent directory device/inode identity rather than reconstructing a canonical pathname. It preserves byte equality after gated selective project deletion while the home and host remain alive. Successful final teardown removes those disposable archives with the private home. Failed assertions retain fixtures. These checks are point-in-time, not a filesystem lease.
- Cleanup confirms the captured development child first, while its service can reap it. It then captures/revalidates and reaps the exact service while the signed host exists. Host, registered projects and home are removed only after successful assertions and cleanup. Failed assertions retain safely stopped fixtures.
- Unknown request completion, missing development identity, unexplained service generation, failed reaping and removal errors propagate. Unconfirmed cleanup retains fixtures without stopping the service beneath unknown work. Body and teardown errors are aggregated. Teardown is synchronous and does not depend on cancellation-sensitive sleeps.
- `DEVTOOLS_REQUEST_QUIESCENT`, identity capture/reaped markers and `DEVTOOLS_FIXTURES_REMOVED` or `DEVTOOLS_FIXTURES_RETAINED` report the reached lifecycle states. They are not a sandbox guarantee or evidence for historical fixtures.
- A failed or ambiguous lifecycle stop poisons further request, stop and project-removal operations. No service is stopped beneath unknown compiler/renderer work. Earlier Test/Build/Run verification below is not new Plan/Preview acceptance evidence.
- Reusable host removal is not itself proof of owned-service reaping. Do not bypass failed cleanup, signal unrelated processes, inspect credentials or clean historical fixtures to obtain a pass.

## Restricted migration verification

- Offline Preview checks use `--filter DevToolsPreviewLifecycleTests`. They cover strict archive identity/link rejection, deleted-project archive bytes and known versus uncertain request completion without starting signed services.
- Observer and installed-read checks use the resource fixtures with Node's `--experimental-strip-types --test`. The production-read fixture requires the deliberate absolute `DEV_TOOLS_SCENARIO_PI_READ_MODULE` setting. It imports only the installed filesystem tool and tests absolute PNG reads after project deletion.
- Restricted affected checks select `DevTools(ContractTests|Tests|XPCServiceTests)`, OpenXPCGenerator's package suite and Agent's package suite with live/resource/scaffold gates unset. Skipped gates are not passes. Do not use a full DevTools command to silently consume extra scenario attempts.
- Signed migration acceptance is separate from offline checks. After explicit release, run each of the four Plan and six Preview cases sequentially once. Stop at the first failure. No retries or collection sweep are implied. Later cases are NOT RUN. Bundle recreation follows successful authorized integration; it does not authorize app launch.

### Preview migration source-check results

- The revised lifecycle plus Preview offline selection passed 34 tests. The final Preview-only selection passed three tests. Five Node checks passed, including unchanged real spawn forwarding, bounded observation and installed production-read bytes after project deletion.
- OpenXPCGenerator passed 27 tests. The restricted DevTools unit/contract/service selection passed 59 tests. Scoped swift-format and pinned strict SwiftLint passed for both changed Swift files.
- The initial Agent non-live verification failed three tests under separate scratch. One assumes `Agent/.build/checkouts/swift-testing`. Two assume `Agent/.build/debug/Agent_AgentApplication.bundle`. Live/resource/scaffold gates remained unset. That failed run remains current-task historical evidence. Separately owned Agent scratch verification then passed its full non-live package run with deliberate current products and a validated checkout override. Its groups passed 15, 63, 28, 4, 6 and 110 tests. The three originally failing tests have actual passing markers. The 63-test group retains 135 intentional known issues. Live/resource/scaffold gates remain skipped. Evidence and its test-only correction belong to `.tmp/plan-preview-agent-scratch/report.md`.
- After explicit scenario release, all four Plan and six Preview cases passed sequentially, once each. Actual selected started/passed markers and exact reached steps were recorded. All ten distinct private homes and signed hosts were removed after matching immutable service reaping. Recorded home/host paths were absent afterward.
- The six Preview cases verified real client/extension byte identity, with signature normalization limited to owned client copies. Render, size, failure-recovery and path-content validated nonlinked sources, complete PNG decoding and bounded archive byte/hash equality. Factories and scope verified controlled rejection with no artifacts/scratch. Render and path-content preserved archive assertions after gated project deletion while home/host remained alive.
- Path-content observed three real correlated child closes. Rendering and ordinary typed rendering error closed with status 0. The controlled scope rejection closed with status 1 and identified `operationFailed`. Installed production read verified relative and absolute PNG paths, then the absolute archive after project deletion. No Pi session or live call was made.
- After successful separately owned Agent verification and explicit bundle release, the documented standalone bundle command recreated `dist/com.ommkar.mac-apper/Mac Apper.app` once with status 0. Read-only strict/deep codesign checks passed for the root app, Agent service, DevTools app and DevTools service. The root signature is ad hoc. All seven assembled Info.plists passed lint; app/service metadata matches current authored plists.
- The deployed DevTools extension matches both the current release package output and staged generated copy. Every current Agent runtime-resource file matches both host and service-local copies. Every current DevTools runtime-resource file matches the service-local copy. AnimationIntent, PreviewProtocol and PreviewRenderer bytes also match current authored resources.
- No app launch, live call, credentials, extra scenario or suite retry followed bundling. Static artifact checks do not establish GUI/runtime readiness or notarization. Disposable commands, raw logs, cleanup checks, prior failures and frozen hashes are indexed at `.tmp/plan-preview-integration/report.md`, `.tmp/plan-preview-integration/acceptance/evidence.md` and `.tmp/plan-preview-integration/bundle/verification.json`.

## Integration navigation

- [Agent](../../../../Agent/README.md) owns the no-model fresh scaffold/DevTools integration and paid counter/plan cases. Those use production Agent client-model/native/generated XPC, not a provider-specific scenario transport.
- The scaffold case separately checks typed Core Data fixtures, Test/Preview/Build/Run and fixture-home persistence; it does not by itself prove generated-counter production relaunch or physical button interactions.
- Paid Create cases correlate actual Test/Preview/Build/Run and plan evidence through Agent journals/Pi results. Nested script text or parent success cannot establish child execution. Their PNG/source/canvas/scratch/archive audits are additional consumer checks, not transport-success inference.
- [VisionCLI](../../../../VisionCLI/README.md) owns optional probabilistic screenshot review. A successful PNG render or read is not a Gemini verdict or proof that the model saw it.

## Selected isolation verification

- The 2026-10-14 selected fix passed 10 offline lifecycle tests and the 57-test unit/contract/service selection with standalone Swift 6.4 and default Swift Build.
- `test-package` and standalone Build/Run each ran once, sequentially. Both produced actual started/passed markers. Test verified both targets, expected failures, recovery, foreign scope, private-home compiler access and scratch/source preservation. Build/Run verified private child inheritance and the exact-binary release handshake.
- Both services and the development child reached exact-owned reaping before fixture removal. Recorded host/home paths were absent afterward. Uncertain/error retention and cancellation ordering were exercised offline, not through additional failing signed launches.
- The cancellation unit passed in this selection. Its earlier intermittent failures remain unresolved; this scenario fix is not their repair.
- Disposable commands, timings, hashes and cleanup evidence are indexed at `.tmp/devtools-fix-harness/report.md`. This checkpoint does not cover Plan/Preview migration, arbitrary generated code, service restart recovery or request draining.

## Earlier recorded evidence

- **Native capture checkpoint:** the original root README and [learnings](../../../../.pi/LEARNINGS.yaml) record an ImageRenderer placeholder regression followed by passing owned NSHostingView capture/per-label ink checks, 55 affected DevTools tests and selected signed-XPC render/size/failure-recovery/scope/path-content cases on arm64 macOS 26.6.2, Swift 6.4 and CLT SDK 26.2. Report locator: `/private/tmp/mac-apper-native-preview.L0Wz8N/report.md`. This is fixture evidence, not universal fidelity or async readiness.
- **Path-only checkpoint:** `/private/tmp/mac-apper-preview-path.CD9vlV/report.md` records selected real-XPC/installed-read checks and recovery of three newly missed services after `/var` versus `/private/var` path mismatch. Initial teardown did not automatically succeed; the final selected Preview cases did.
- **Canonical producer checkpoint:** `/private/tmp/mac-apper-preview-canonical-1791637226/report.md` records five focused checks and a 54-test DevTools suite excluding scenarios. It establishes point-in-time strict-consumer path compatibility, not a race-proof lease or a live workflow pass. Later Agent consumer-parent equality and operational/visual failures remain failures despite subsequent repairs.
- **Preparation/preflight checkpoint:** `/private/tmp/mac-apper-task2-verification.md` records Scenario 24/DevTools 52-test evidence after environment and executable-preflight fixes. Earlier packaged Swift 6.4 checks do not verify those later fixes. Deprecated native-build planning workaround logs remain historical, not current instructions.
- **Intermittent cancellation:** DevTools `cleanupFailed` checkpoints later passed focused/full retries without related source changes or an established cause. Do not claim a runtime fix from retries.
- **Cross-module live checkpoints:** the original root snapshot records separate counter and plan passes on 2026-10-11, but explicitly excludes production relaunch persistence, physical button clicks, calibrated vision and live nested Preview. The earlier post-lifecycle counter visual/identity-cleanup failure and retained safety state remain unresolved; new fixtures did not clean it.
- Report paths above are historical locators preserved from reviewed documentation, not reports re-executed or artifact/credential contents inspected during this rewrite. Missing temporary reports do not authorize recreation or cleanup. The root overview and owning learnings retain the broader evidence index.

## Rewrite verification scope

- Static verification checked all 49 local Markdown links (including anchors): all targets exist and anchors resolve. Named selectors/commands were compared with Package.swift, OpenXPC configuration and package-local scenario declarations; schema/controller limits were read directly, not exercised.
- No authored YAML-format README existed to migrate, and no stale YAML README links remain in authored DevTools documentation. Dependency documentation under `.build` is generated/vendor-owned and is neither migrated nor modified.
- Runtime paths, compiler availability, signed-host execution, live workflows and historical cleanup are unverified by this documentation-only task.
