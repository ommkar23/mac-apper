# DevTools verification

[DevTools](../README.md) · [Tools](tools.md) · [Preview](preview.md)

Commands below run from the repository root and require authorization for their actual effects. This documentation rewrite inspected files and links only: no package test/build, bundle, GUI, Pi session, credential operation, model/MCP/Gemini call or historical cleanup was executed.

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

## Provider scenarios

- [Scenario](../../../../Scenario/README.md) owns reusable signed-host preparation, compiler helpers and lifecycle APIs. DevTools tests own prompts/assertions, fixtures and provider selections; no full Mac Apper.app build/copy or retired Scenario runner/plugin is required.
- Load [scenario-run](../../../../.pi/skills/scenario-run/SKILL.md) for authorized execution/monitoring and [scenario-write](../../../../.pi/skills/scenario-write/SKILL.md) for authoring.
- Each selected collection stages the generated terminal client and real DevTools service in a disposable signed `DevToolsScenario.app`, with only test-owned UUID fixtures under `~/.mac-apper`. No Pi session or model/MCP/Gemini calls are required. No-model does not mean air-gapped dependency resolution, and Build/Run still executes generated native code.
- `DEV_TOOLS_SCENARIO_CASE` selects one case within the chosen Plan/Test/Preview entry point; omit it for that entry point's collection. Unset it before selecting the entire `DevToolsScenarioTests` target, since a name from one collection is not valid in another.

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

### Plan and Test coverage

- `plan-initial-tasks`: seeded creation/retrieval, duplicate-plan rejection, invalid initial tasks/IDs without consuming the creation slot, empty-plan isolation.
- `plan-lifecycle`: repeated additions, updates and multi-delete ending in a retrievable empty plan.
- `plan-rejections`: malformed/missing updates and second-in-progress rejection without mutation.
- `plan-project-isolation`: separate plans per project, independent of session identity.
- `test-package`: two real Swift Testing targets, successful execution, assertion failure, compilation failure, repaired pass, foreign-scope rejection and source/request-scratch preservation. Fixtures use pinned Testing and an explicit macOS 14 deployment target rather than XCTest.
- `devToolsToolchainBuildRunScenario`: requires compiler 6.4, validates generated-client Build/Run metadata, executable staging, source preservation and absence of project `.build`; waits for the self-exiting fixture child to reach ESRCH. This is development launch evidence, not UI readiness or production packaging.

### Preview prerequisites, selections and coverage

- Preview stages the renderer resource and generated extension without a source-tree fallback. A test-only registration harness executes the unmodified extension against the real generated client/service; it does not start a Pi session.
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

- Preview's current teardown derives the existing service's real kernel path, captures/revalidates `OwnedProcessIdentity`, requires exact PID/path/start reaping before host removal, and fails closed if the service cannot be identified. Its archived PNGs remain retained.
- Do not extend that Preview guarantee to every provider entry point: current Plan/Test collection teardown calls `host.remove()` directly, and the toolchain fixture uses best-effort project/host removal after waiting for its development child. These entry points do not contain Preview's explicit XPC service-reaping gate. This is a source-inspected limit, not an observed new process leak or a newly failed test; review it before authorizing execution under a strict exact-service-cleanup requirement.
- Reusable host removal is not itself proof of owned-service reaping. Do not bypass failed cleanup, signal unrelated processes, inspect credentials or clean historical fixtures to obtain a pass.

## Integration navigation

- [Agent](../../../../Agent/README.md) owns the no-model fresh scaffold/DevTools integration and paid counter/plan cases. Those use production Agent client-model/native/generated XPC, not a provider-specific scenario transport.
- The scaffold case separately checks typed Core Data fixtures, Test/Preview/Build/Run and fixture-home persistence; it does not by itself prove generated-counter production relaunch or physical button interactions.
- Paid Create cases correlate actual Test/Preview/Build/Run and plan evidence through Agent journals/Pi results. Nested script text or parent success cannot establish child execution. Their PNG/source/canvas/scratch/archive audits are additional consumer checks, not transport-success inference.
- [VisionCLI](../../../../VisionCLI/README.md) owns optional probabilistic screenshot review. A successful PNG render or read is not a Gemini verdict or proof that the model saw it.

## Recorded evidence, not checks performed here

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
