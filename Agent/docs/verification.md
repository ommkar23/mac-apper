# Agent verification commands

[Agent introduction](../README.md) · [Scenario contracts](scenarios.md) · [Scaffold](scaffold.md) · [Recorded evidence](evidence.md)

Commands below are entry points for separately authorized verification, not checks executed during this rewrite. Run from the repository root unless stated otherwise.

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
- [NameAndRenameExtensionTests](../Tests/AgentApplicationTests/NameAndRenameExtensionTests.swift) retains authored naming and packaging logic checks.
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
  - Private HOME/CFFIXED_USER_HOME scopes projects/SQLite, only the installed compiler is linked into the owned home, and AGENT_SCENARIO_PRODUCTS/DEV_TOOLS_SCENARIO_PRODUCTS support existing custom product directories.
- **Assertions and cleanup**
  - Editable fixture sources register typed entities/model actions while protected composition remains byte-identical, with Test requiring passed/exitCode 0 and the named save/validation-rollback/reopen passing diagnostic.
  - Preview validates PNG dimensions and injected memory-record pixels, while Build/Run use protected ProductionApp and Run checks executable PID/path/start and SIGTERM reaping rather than readiness or saved data.
  - Four helper processes prove explicit fixture-home SQLite write/check/delete/absence at the stable UUID path, without treating that as production-home relaunch.
  - Tools preserve source/manifest/lockfile, remove request Test/Preview scratch and create no project `.build`.
  - Exact service identity is revalidated before bounded TERM/KILL after requests/development-child completion and before host removal, with successful roots removed, failed homes/hosts retained and new PNG/helper logs preserved externally.
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
