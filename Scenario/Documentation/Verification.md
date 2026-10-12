# Verification and evidence

[Scenario introduction](../README.md) · [Hosting](Hosting.md) · [Isolation and cleanup](Isolation-and-cleanup.md) · [Compiler and SDK](Compiler-and-sdk.md)

## Package entry points

Run from the repository root only when execution is authorized:

```sh
swift64="$HOME/Library/Developer/Toolchains/swift-6.4.0-RELEASE.xctoolchain/usr/bin/swift"
"$swift64" build --package-path Scenario
"$swift64" test --package-path Scenario

# Focused examples; these still execute fixture processes/compiler checks.
"$swift64" test --package-path Scenario --filter collectionAndSelectedCaseUseTheSameContextsAndTeardown
"$swift64" test --package-path Scenario --filter SDKCompilerTests
"$swift64" test --package-path Scenario --filter ownedExitRacesRequireFreshESRCH
```

- [Package.swift](../Package.swift) declares the library and its tests, with no Scenario executable or command plugin. Root `swift test` does not run this package's suite.
- Full Scenario tests include signing/staging, child process cleanup, real SDK compilation and a matching-loader smoke. They do not select Agent's paid scenario collections, but are not purely text checks or an air-gapped dependency-resolution guarantee.
- Underlying library behavior changes require focused red/green tests and this affected package suite, plus relevant consuming packaged paths when authorized. Scenario-only case changes use the selected consuming tests rather than unrelated units.
- For stale SwiftPM diagnostics or a fresh build, the root optional command is:

```sh
"$swift64" package --disable-sandbox plugin clean-test Scenario [--filter PATTERN]
```

- `[--filter PATTERN]` is optional syntax, not a literal shell argument. [Plugins](../../Plugins/README.md) owns the clean-test implementation and scratch-safety workflow. Any manual scratch path must be nonempty, private and validated before SwiftPM use; remove only that exact owned directory after its work exits.
- [scenario-run](../../.pi/skills/scenario-run/SKILL.md) owns authorized consuming-case launch/monitoring; [Agent](../../Agent/README.md) and [DevTools](../../apps/built-in/dev-tools/README.md) own their filters/opt-ins, dependencies, prompts and assertions. Do not use retired `swift package scenario` or ScenarioRunner commands.

## Test map

- [ScenarioTests](../Tests/ScenarioTests/ScenarioTests.swift): shared/local contexts, selection/discovery, unknown/duplicate names, partial-setup teardown, continued cases after failure and package retirement boundaries.
- [PackagedTestHostTests](../Tests/ScenarioTests/PackagedTestHostTests.swift): declared inputs, nested resources, isolated identities, pre-signing service environments and partial staging rejection.
- [PackagedXPCHostTests](../Tests/ScenarioTests/PackagedXPCHostTests.swift) and [PackagedApplicationHostTests](../Tests/ScenarioTests/PackagedApplicationHostTests.swift): resource and deployed-input boundaries, rejection and owned removal.
- [IsolatedScenarioHomeTests](../Tests/ScenarioTests/IsolatedScenarioHomeTests.swift): home/storage scope, synthetic selective credentials, unsafe paths and retention/ordering after failed confirmation.
- [OwnedProcessIdentityTests](../Tests/ScenarioTests/OwnedProcessIdentityTests.swift) and [OwnedProcessExitRaceTests](../Tests/ScenarioTests/OwnedProcessExitRaceTests.swift): real captured-child/already-exited reaping, unrelated-process preservation, deterministic exit/identity/signal races and fail-closed states.
- [SwiftToolchainTests](../Tests/ScenarioTests/SwiftToolchainTests.swift) and [SDKCompilerTests](../Tests/ScenarioTests/SDKCompilerTests.swift): preparation environments, both tool redirects, matching loader, explicit SDK/imports and pre-startup failure gates.
- Directory-identity regression tests live in Agent test support/AgentScenarioTests, not the Scenario suite. This source ownership distinction is documented in [directory identity](Isolation-and-cleanup.md#directory-identity).

## Recorded evidence, not new verification

These checkpoints are preserved from the original root documentation and [learnings](../../.pi/LEARNINGS.yaml). Report paths are historical locators, not promises that temporary files still exist. This rewrite did not open retained fixtures/reports, rerun their commands, inspect credentials or perform cleanup.

- **Preparation/toolchain repair**
  - `/private/tmp/mac-apper-task2-verification.md` records focused non-Swift environment, swiftc redirection and tool preflight failures/recoveries, followed by 24 Scenario and 52 DevTools tests.
  - Scenario log: `/private/tmp/mac-apper-task2-scenario-suite.log`.
  - Earlier packaged passes predate these fixes. Deprecated native-build/plugin workarounds are historical, not current setup instructions.
- **Directory identity repair**
  - `/private/tmp/mac-apper-scope-identity.n56PEv/report.md` records offline alias rejection/unsafe-identical-path failures followed by four focused and 179 Agent offline tests passing, with packaged/native entry points excluded.
  - This establishes the test-support audit recovery, not a paid workflow pass or filesystem lease; prior failed fixtures remained unchanged.
- **Explicit SDK startup gate**
  - `/private/tmp/mac-apper-sdk-fix-report/report.md` records four focused SDK checks and 31 Scenario offline tests passing with the hosted-loader smoke excluded, plus selected/broader Agent offline verification excluding packaged/live entry points.
  - It is offline setup/import evidence. A prior live missing-Darwin failure was not evidence of an unsupported generated presentation API, and was not retroactively made a pass.
- **Owned-process exit races**
  - `/private/tmp/mac-apper-owned-exit-1791699403/report.md` records six deterministic failures, then 23 deterministic cases and real captured-child/already-exited reaping with unrelated-child preservation passing; the affected 33-test Scenario run excluded unrelated hosted-loader smoke.
  - This does not prove the component or cause of a historical uninstrumented mismatch or authorize historical safety cleanup.
- **Remaining historical safety failure**
  - `/private/tmp/mac-apper-counter-lifecycle-live.xE4QZx/report.md` records an Agent counter visual failure plus owned-process identity mismatch that blocked outer service cleanup, snapshot scrub and host/home removal.
  - Later passing new fixtures did not inspect, signal, scrub or remove that retained historical fixture. Historical PID observations are not current liveness or immutable-identity reaping confirmation.
  - Agent owns the full live workflow/evidence chronology; it is not a normative Scenario runbook.

## This documentation rewrite

- Performed static review of repository policy, the original root/Agent snapshots, Scenario documentation/manifest/source contracts and relevant consuming-package contracts.
- Verification is limited to Markdown destinations/anchors, relative paths, package/plugin command agreement, documentation ownership and stale YAML README references within authored Scenario scope.
- No package build/test, signed host, GUI, Pi session, credential operation, live model/MCP/Gemini call, historical cleanup or commit was authorized or performed.
- Code examples are source-reviewed illustrations, not newly compiled evidence. Runtime/library paths and recorded evidence were not revalidated during this rewrite.
