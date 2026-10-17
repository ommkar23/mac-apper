# Agent verification commands

[Agent introduction](../README.md) · [Scenario contracts](scenarios.md) · [Scaffold](scaffold.md) · [Recorded evidence](evidence.md)

Commands below require separate verification authorization. Listing a command does not mean it has been run. Run from the repository root unless stated otherwise.

## Compiler setup

- Complete [New Mac setup](../../README.md#new-mac-setup) first. Check that both explicit standalone `swift` and `swiftc` paths are executable and report 6.4.0 as shown there.
- Use the explicit standalone Swift 6.4.0 driver and default Swift Build, not --build-system native. Testing remains pinned to 6.2.3; do not match its version to the compiler.
- Recorded CLT SDK is macOS 26.2; xcrun compiler selection remains 6.2.3. Scenario SDK probes discover the installed selected SDK explicitly rather than hardcoding its version or trusting SDKROOT.
- Production/preparation preflight requires executable swift and swiftc with no CLT fallback. Scenario uses the matching swiftpm-testing-helper; non-Swift preparation preserves inherited environments.

```sh
swift64="$HOME/Library/Developer/Toolchains/swift-6.4.0-RELEASE.xctoolchain/usr/bin/swift"
"$swift64" --version
xcrun --show-sdk-version
```

## Package tests

- Root tests do not test Agent. [Package.swift](../Package.swift) defines these ownership boundaries:
  - AgentApplicationTests: service contracts, Pi, scaffold/persistence, architecture and integrations.
  - AgentMacosClientModelTests: client-owned domain/presentation values only.
  - AgentMacosClientTests: native adapter/runtime/store behavior, without importing the service core.
  - AgentTests: cross-target integration behavior only.
  - AgentScenarioTests: signed scenarios plus independent offline support/audit/news/process checks; live and explicit resource/scaffold gates are opt-in.
- For normal package verification, keep live/resource/scaffold opt-in environment gates unset. A broad AgentScenarioTests filter may execute offline tests; a selected scenario-name filter runs only that path.

```sh
"$swift64" test --package-path Agent
# Selected target or focused test examples:
"$swift64" test --package-path Agent --filter AgentMacosClientModelTests
"$swift64" test --package-path Agent --filter AgentScenarioTests
"$swift64" test --package-path Agent --filter generatedScaffoldSupportsOfflineFirstPersistenceAndPresentation
```

- The architecture test still names the removed YAML README at Tests/AgentApplicationTests/AgentArchitectureTests.swift:37. It needs a separately owned source change before claiming that test passes after migration. No test was run here.
- Optional fresh/stale-cache verification uses the root [Plugins guide](../../Plugins/README.md), through `"$swift64" package --disable-sandbox plugin clean-test Agent [--filter PATTERN]`.
- Manual scratch must be newly created, nonempty and validated before passing it to SwiftPM; remove only the exact owned directory after work exits, never unrelated retained artifacts.

```sh
# Initialize private .tmp and TMPDIR using the root temporary-work contract.
scratch=$(mktemp -d "$TMPDIR/mac-apper-test.XXXXXX")
test -n "$scratch" && test -d "$scratch" || exit 1
"$swift64" test --package-path Agent --scratch-path "$scratch"
# Remove only this exact validated owned scratch after its work exits.
```

### Chat declaration and lifecycle regressions

Keep live/resource/scaffold gates unset. Use exact owning-package filters rather than a broad scenario-target sweep:

```sh
"$swift64" test --package-path Agent --scratch-path "$scratch" \
  --filter 'AgentScenarioTests[./](ChatContractTests|ChatLifecycleTests|ChatCaseContractTests)'
"$swift64" test --package-path Agent --scratch-path "$scratch" \
  --filter 'AgentScenarioTests[./](chatCapabilitiesPromptRequiresFetchedContentOffline|chatCleanup|countryNews|piProcessSnapshot|sessionAudit|toolEvidence)'
```

- The second selection includes the exact-owned local child cleanup test. It launches owned offline child processes, not Pi or a signed host.
- Require positive selected-test counts and passed markers. Skipped live cases and zero-test results are not passes.
- Chat contract checks inspect the actual eight-case collection, lightweight discovery and selector rejection.
- Lifecycle fixtures exercise observed assertion gating, one shared deadline, timeout/cancellation, awaited uncancelled cleanup, partial acquisition, reverse-order aggregate release and collection confirmation suppression.
- These checks do not authorize or establish signed hosting, Pi/MCP calls, real session lifecycle behaviour or live cleanup after the declaration change. See [Chat limits](scenarios.md#production-path-and-chat-collection).

### Create declaration and lifecycle regressions

Use a private validated scratch and repository-root `TMPDIR` from the root temporary-work contract.
Keep `AGENT_SCENARIO_LIVE`, `AGENT_RESOURCE_SCENARIO` and `AGENT_SCAFFOLD_DEVTOOLS_SCENARIO` unset.
Also unset host-recursion gates `AGENT_SCENARIO_TEST_HOST`, `AGENT_RESOURCE_TEST_HOST` and `AGENT_SCAFFOLD_DEVTOOLS_HOST`.
These exact offline selections do not prepare signed hosts, inspect credentials, launch Pi/WebKit or call models/MCP/Gemini:

```sh
"$swift64" test --package-path Agent --scratch-path "$scratch" \
  --filter 'AgentScenarioTests[./](CreateContractTests|CreateLifecycleTests|CreateHostLifecycleTests|CreatePlanContractTests|CreateCounterContractTests|CreateHTViewContractTests|createPlanInterfacePolicyOffline|createPlanInterfaceScopeOffline|createPlanInterfaceCleanupOffline)'
"$swift64" test --package-path Agent --scratch-path "$scratch" \
  --filter 'AgentScenarioTests[./](createPlanToolAuditOffline|createPreviewToolAuditOffline|createNamingTypedResultOffline|createNamingEvidenceOffline|createNamingFinalMetadataOffline|createPreviewDefaultCanvasTextOnlyOffline|createPreviewRejectsInvalidPathEvidenceOffline|createPreviewCanonicalArchiveWithAliasClientOffline)'
"$swift64" test --package-path Agent --scratch-path "$scratch" \
  --filter 'AgentScenarioTests[./](htViewHTMLFixture|htViewScenarioEvidence|htViewWebKitMalformedEvidenceOffline|htViewResource|htViewPromptAndObserver)'
"$swift64" test --package-path Agent --scratch-path "$scratch" \
  --filter 'AgentScenarioTests[./]counterEvidenceParsesSwift64WithoutModelOrToolCalls'
```

- Require positive started/passed counts for each requested group. Zero tests and skipped tests are not passes.
  Explicit passed-with-known-issues outcomes are positive negative-control results, even when Swift Testing prints a cross marker.
  Count them separately. Reject failed outcomes and nonzero command statuses.
  Aggregate runner summaries are not individual test passes.
  Count each parameterized test once. Its case-start lines and passing-summary suffix do not add tests.
- Contracts inspect all three real declarations without invoking their context factories or setup.
- Synthetic lifecycle fixtures check one shared budget, awaited cancellation, uncancelled cleanup, partial setup/submission uncertainty, assertion gating and aggregate confirmation suppression.
  Retention checks clear an optimistic pass flag after observed failure, thrown failure or cancellation.
- Injected host fixtures check partial preparation, thrown/missing invocation results, selected-test markers, missing inner confirmation, service failure and retention policy.
  They replace real preparation, credential, Vision and runtime operations.
- Plan contracts and the three extracted `createPlanInterfacePolicyOffline`, `createPlanInterfaceScopeOffline` and `createPlanInterfaceCleanupOffline` guards preserve its permanently unconfirmed interface-only cleanup.
  Acknowledgements cannot authorize Pi inspection/reaping or project deletion.
- Do not broaden these filters to `AgentScenarioTests` for offline-only authorization.
  `createIsolatedHostOffline` and `agentMcpHostPreparationOffline` execute real signed hosting despite their names.
  No-model resource/scaffold entry points and `htViewEmbeddedWebKitOfflineRegression` need separate authorization.
- These checks are not paid Create, signed-host acceptance or live cleanup recovery.
  Cooperative timeout limits and HTView's existing child-capture gap remain documented in the [Create lifecycle contract](scenarios.md#create-declaration-lifecycle).
  Historical failures remain in the [recorded learnings](../../.pi/LEARNINGS.yaml).

### Counter offline checkout override

- `counterBehaviorOfflineRegression` defaults to `Agent/.build/checkouts/swift-testing`.
- For custom SwiftPM scratch, set `AGENT_COUNTER_OFFLINE_TESTING_CHECKOUT` to that scratch's existing `checkouts/swift-testing` directory.
- The override must be an absolute, nonlinked directory path with a readable regular `Package.swift`.
- Empty, relative, traversal, linked, missing and manifest-unsafe paths fail before fixture manifest use. Invalid explicit input never falls back to the default.
- Use the current package-resolved checkout. Testing remains pinned to 6.2.3. The override changes dependency location only. Independent compiler probes and counter behavior assertions remain required.

```sh
AGENT_COUNTER_OFFLINE_TESTING_CHECKOUT="$scratch/checkouts/swift-testing" \
  "$swift64" test --package-path Agent --scratch-path "$scratch" \
  --filter counterBehaviorOfflineRegression
```

- Offline host preparation also needs current custom product directories through the existing `AGENT_SCENARIO_PRODUCTS` and `DEV_TOOLS_SCENARIO_PRODUCTS` overrides.
- Validate those products before a non-live package run. Keep live/resource/scaffold gates unset. No root `.build` symlinks or user configuration changes are needed.

### Vision preparation offline regression

```sh
# Keep live/resource/scaffold gates unset; this filter never prepares a host or reads credentials.
"$swift64" test --package-path Agent --scratch-path "$scratch" --filter agentVisionPreparation
node --test .pi/tests/scenario-run.test.mjs
```

- Injected runners and env-file providers check explicit product selection, suppressed builds, exact check-config arguments and staged destination.
- Negative controls cover invalid directory/executable overrides, legacy behavior, disabled Vision and propagated preparation errors.
- Strict private Counter/Plan runs supply `AGENT_VISION_PRODUCTS` from the [private Vision build recipe](../../VisionCLI/README.md#private-scenario-products), in addition to Agent/DevTools product overrides.
- Offline preparation tests do not establish a signed-host or live Gemini pass. Configuration and credential checks still require separate authorization.

## Naming verification boundary

- Naming relies on correct bundle metadata and SwiftUI API wiring, not independent platform naming checks.
- [ScaffoldNamingTests](../Tests/AgentApplicationTests/ScaffoldNamingTests.swift) retains protected source-wiring checks.
- [AppNameTests](../Tests/AgentApplicationTests/AppNameTests.swift) retains validation and rename-command logic checks.
- [NameAndRenameExtensionTests](../Tests/AgentApplicationTests/NameAndRenameExtensionTests.swift) checks command-only registration, rename branding, packaging, validation and `MAC_APPER_RENAMED` notification with offline process/filesystem doubles.
- [PiExtensionTests](../Tests/AgentApplicationTests/PiExtensionTests.swift) checks sole provider naming-tool ownership and first/later/resume Create availability, with Chat excluded. Removing provider naming metadata must remove the tool; Agent must not supply a fallback.
- [CreateInstructionTests](../Tests/AgentApplicationTests/CreateInstructionTests.swift) checks first-request naming guidance and the metadata-only versus native rename/repackage distinction.
- Root [BundleCommandsTests](../../Tests/IntegrationTests/BundleCommandsTests.swift) checks generated catalog naming ownership and retained command-extension packaging. It does not build a bundle or host XPC.

```sh
# Unit targets only: no AgentScenarioTests, signed hosts or opt-in resource/scaffold cases.
"$swift64" test --package-path Agent --filter '^(AgentApplicationTests|AgentMacosClientModelTests|AgentMacosClientTests|AgentTests)[./]'
"$swift64" test --filter '^(IntegrationTests|SwiftLinesPluginTests)[./]'
```

- Inspect selected suites before execution. Keep live/resource/scaffold gates unset. Unit targets use local doubles and may compile fresh disposable scaffold fixtures; this is not packaged XPC, rendered-window naming evidence or live model verification.
- [DevTools RunControllerTests](../../apps/built-in/dev-tools/Tests/DevToolsXPCServiceTests/RunControllerTests.swift) retains shared branding validation and staging checks.
- Scene compiler probes, synthetic Bundle execution and CoreGraphics window observation are retired naming checks.
- HTView still requests its app name and main window title.
- Acceptance excludes rendered naming checks and naming-observation permission requirements.
- No tests or runtime checks were run for this retirement documentation.
- Full Agent acceptance remains unverified. Removing its historical failing check is not a passing suite.
- The retained HTView resource-staging failure is not repaired by naming-check retirement.
- Historical results remain in the [archive](../../docs/verification-archive.md#naming-verification-retirement--2026-10-14).

## No-model startup and bundled resources

- **Commands and scope**
  - Local --service-presets prints fixed presets only and does not call XPC or load Agent resources, while the resource case exercises production model/native/generated XPC without Pi startup.

  ```sh
  'dist/com.ommkar.mac-apper/Mac Apper.app/Contents/MacOS/AgentMacosClient' --service-presets
  AGENT_RESOURCE_SCENARIO=1 "$swift64" test --package-path Agent --filter agentBundledResourceScenario
  AGENT_RESOURCE_SCENARIO=1 AGENT_RESOURCE_APP="$PWD/dist/com.ommkar.mac-apper/Mac Apper.app" \
    "$swift64" test --package-path Agent --filter agentBundledResourceScenario
  ```

  - The case reads the workspace library, prepares/opens a test-owned project through WorkspaceSession and compares AnimationIntent, PreviewProtocol and the development-service template with bundled bytes.
  - Test-only HOME/CFFIXED_USER_HOME and identities are isolated, exact PID/kernel-path/start evidence identifies/reaps the service before host/home removal, and current scaffold checks require an empty programmatic schema plus CoreData SQLite path.
  - Deployed verification stages only the real release Agent executable/resources in a re-signed minimal host rather than claiming the original product identity or GUI was exercised.
  - AGENT_RESOURCE_EXPORT_DIRECTORY optionally retains fresh sources in a precreated task-owned `.tmp/mac-apper-coredata-task6-<ID>` directory beneath the repository root.

## No-model scaffold integration

- **Always-run scaffold behavior check**
  - This focused test builds a fresh typed-entity scaffold under Swift 6 strict concurrency/warnings-as-errors, selected CLT SDK 26.2 and pinned Testing 6.2.3 to exercise the persistence/presentation contracts rather than relying on an empty-schema build.

  ```sh
  "$swift64" test --package-path Agent --filter generatedScaffoldSupportsOfflineFirstPersistenceAndPresentation
  ```

- **Preparation and selection**
  - Build DevTools products first and run the single package-local Agent case rather than bundling the full product.

  ```sh
  "$swift64" build --package-path apps/built-in/dev-tools -j 2
  AGENT_SCAFFOLD_DEVTOOLS_SCENARIO=1 "$swift64" test --package-path Agent -j 2 --filter agentScaffoldDevToolsScenario
  ```

  - The case prepares a real v9 project through Agent's production model/native client and separately drives generated DevTools client/service in signed hosts without Web, Pi, VisionCLI or Mac Apper.app.
  - Private HOME/CFFIXED_USER_HOME scopes clients, services, development children and SQLite. Only the installed compiler is linked into the owned home. AGENT_SCENARIO_PRODUCTS/DEV_TOOLS_SCENARIO_PRODUCTS support existing custom product directories.
  - Signed-host execution needs matching Agent test-loader/service/resources and freshly generated DevTools client/service/resources with `set_app_name`. It also needs local ad-hoc signing and authorization for compiler work and the development launch. It needs no credentials, Pi, MCP or full product bundle.
  - The naming additions are compile/offline verification work until the coordinator authorizes the exact scaffold selector above. They do not establish a new signed-host pass.
- **Assertions and cleanup**
  - Before Test, Build or Run, the signed production generated DevTools client calls `set_app_name` with `  Pebble / Counter: .app.APP  `. Its typed string result must be exactly `Pebble Counter` with the expected summary.
  - Both project branding keys must equal that result. All other plist values and the complete fixture source/manifest/lockfile snapshot stay unchanged. Naming creates no Build/Test/Preview/DevBuild scratch, project `.build`, dist output or production package.
  - A production `WorkspaceSession.refreshLibrary()` through the native Agent adapter must expose exactly the matching project's canonical title without a built-app entry.
  - The existing matched Run response selects the exact staged development plist. Bounded descriptor-relative no-follow reads require both branding keys to equal the canonical result. ProductionApp executable, UUID-derived development identifier and request-derived version remain service-owned.
  - These are metadata and model-presentation assertions. They do not observe rendered windows or application menus. The scaffold has no status-item surface.
  - `scaffoldNamingLocalReadsOffline` checks binary plist/unrelated metadata reads and rejection of linked ancestors, traversal and oversized files. `scaffoldNamingFIFOOffline` requires nonblocking leaf-open flags and rejects a writerless FIFO before reading. `scaffoldServiceGenerationOffline` rejects changed PID/path/start, uncertain capture and replacement after cached ESRCH. It also accepts unchanged generations and checks that rejection blocks cleanup continuation.
  - The offline selector is `"$swift64" test --package-path Agent --filter 'scaffoldNamingLocalReadsOffline|scaffoldNamingFIFOOffline|scaffoldServiceGenerationOffline'`. These tests do not prepare hosts or launch apps.
  - Editable fixture sources register typed entities/model actions while protected composition remains byte-identical, with Test requiring passed/exitCode 0 and the named save/validation-rollback/reopen passing diagnostic.
  - Preview validates PNG dimensions and injected memory-record pixels, while Build/Run use protected ProductionApp and Run checks executable PID/path/start and SIGTERM reaping rather than readiness or saved data.
  - Four helper processes prove explicit fixture-home SQLite write/check/delete/absence at the stable UUID path, without treating that as production-home relaunch.
  - Tools preserve source/manifest/lockfile, remove request Test/Preview scratch and create no project `.build`.
  - Only matched successful request envelopes confirm completion. A thrown request leaves cleanup uncertain. Run sets the child gate before invocation and clears it only after exact PID/path/start reaping.
  - DevTools service identity is captured immediately after naming. Every subsequent request attributes the unique exact-host live service before dispatch and after its matched response. PID, kernel path and start identity must equal the cached generation before request confirmation. Attribution also precedes development-child termination and the first service cleanup.
  - First service cleanup requires current exact-host attribution before bounded TERM/KILL, even if the cached PID has reached ESRCH. Replacement or uncertain attribution throws before host removal or the inner cleanup marker. Confirmed requests and child reaping gate service/host removal. The resulting inner cleanup marker gates outer Agent service/host cleanup. Cleanup is attempted once. Uncertain cleanup retains owned fixtures.
  - New staged-plist assertions run after the development child is reaped. Successful roots are removed only after DevTools service cleanup. Failed homes/projects remain retained, while confirmed cleanup may remove their hosts. New PNG/helper logs remain preserved externally.
  - No-model/API integration is not an air-gapped dependency-resolution guarantee, final product smoke or visual review.

## Authorization

- Package tests/builds, bundle recreation, GUI launches, Pi sessions, endpoint discovery, credential operations and live calls are distinct execution paths. None is implied by a documentation-only change.
- Starting Pi with remote MCP, auth refresh/discovery or real Parallel/model/Gemini calls requires explicit authorization even when credentials exist. Create's isolated snapshot contract does not authorize independent credential probes.
- Original-product GUI smoke requires approved service-home isolation before automatic workspace reads; client HOME alone does not scope launchd services. Do not hand-edit signed artifacts or global settings to obtain a pass.
- Generated code and tests run with user permissions, not in a sandbox. Historical process/snapshot cleanup needs separate exact-owned authorization.
- App build/bundle/format/lint commands are owned by the [root overview](../../README.md) and [Plugins](../../Plugins/README.md). A documentation-only rewrite does not recreate the product bundle.

## Troubleshooting

- Missing Pi: inspect executable discovery, distinguishing local configuration from network/auth-refresh probes.
- Missing sessions: inspect only the scoped project's .pi/sessions; invalid histories are skipped and unsent drafts are not saved.
- Stale extensions/interfaces: rebuilding/reopening is a separate authorized action, not a documentation check.
- Build/protocol failure: inspect Activity and use the relevant selected DevTools case rather than initiating unauthorized MCP calls.
- Missing service resources: host-only Bundle.module placement is insufficient. Stage runtime bundles in the XPC service's Contents/Resources as well as the host copy; local --service-presets does not verify this lookup.
