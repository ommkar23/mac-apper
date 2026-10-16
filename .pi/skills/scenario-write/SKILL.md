---
name: scenario-write
description: Write and update Mac Apper package-local Swift Testing XPC scenario cases and collections using Scenario hosting and production generated clients.
---

# Write Swift scenario tests

## Documents and boundaries

- Read project-root `AGENTS.md`, `README.md`, `.pi/GUIDANCE.yaml`, `.pi/CONVENTIONS.yaml`, and relevant `.pi/LEARNINGS.yaml` entries; then read [Scenario](../../../Scenario/README.md) and the case owner's [Agent](../../../Agent/README.md) or [DevTools](../../../apps/built-in/dev-tools/README.md) guide.
- Use `../scenario-run/SKILL.md` for authorization, selection, launch, monitoring and result reporting; writing a test does not authorize live execution.
- Add cases to the owning package's Swift Testing target and invoke through `swift test`; do not recreate root Scenarios/, ScenarioRunner, ScenarioPlugin or scenario bundles.
- Scenario/ owns generic contexts, packaging, signing, temporary hosting and reusable safety primitives; package-local tests own fixtures, prompts, assertions, deadlines and domain-specific cleanup wiring.
- XPC operations travel through OpenXPC-generated clients to real signed services, not direct controller/service calls or a scenario-specific transport.
- Agent Chat/Create drive WorkspaceSession, AgentXPCRuntime and AppModel from AgentMacosClientModel through production AgentServiceXPCAdapter/OpenXPCGeneratedClient.
- DevTools cases use PackagedXPCHost and the production generated DevToolsTerminalClient; generated Pi extension harnesses may exercise that same transport locally without starting Pi sessions.
- PackagedTestHost stages the existing Swift test bundle, matching standalone SwiftPM loader, declared services/resources and isolated identities; no full product app copy or dedicated Agent scenario client is needed.

## Collections, cases and Swift Testing

- Use Scenario for CollectionContext, CaseContext, ScenarioCollection, ScenarioCase and named Step closures. New declarative cases separate `setup: [Step]`, `behaviour: [Step]` and `cleanup: [CleanupChain]` for human review.
- Name each CleanupChain and its ordered `steps: [Step]`. Keep dependency-sensitive release in one chain. Ordering does not confirm request completion or authorize filesystem removal; downstream lifecycle gates still own safety.
- Import the test-only ScenarioTesting product and use `ScenarioTestingObserver()` with report-based execution to observe unexpected nonthrowing Swift Testing issues within awaited steps. Known issues handled inside a step are not unexpected failures. Call `requireSuccess()` on the report. Do not infer completion of detached work or external processes from observation.
- ScenarioTesting depends on pinned Testing 6.2.3 Experimental `Issue.isFailure` SPI. It is not a public-only adapter. Core Scenario stays independent of Testing. Testing system issues bypass issue handlers; Swift Testing remains authoritative for overall test success.
- Keep success markers in separate final behaviour steps so an observed assertion failure skips them. Cleanup must still handle partial preparation and observed failure.
- Legacy closure `setup`, `steps:` and `teardown` declarations remain compatible. Migrate only the authorized cases; mixed collections need not be rewritten wholesale.
- Collection setup runs shared work once for the selected collection invocation; case setup creates each owned fixture and performs per-case checks. Named collection phases use `ScenarioCollection(name, context: factory, setup: [Step], cases: cases, cleanup: [CleanupChain])`.
- Context factories stay lightweight. Record acquisition during setup before later operations can fail. Optional cleanup `eligibility:` returns `.notAcquired` only for proven absence and throws for uncertainty. Failed chain steps skip dependent steps; independent chains still run in order.
- `ScenarioRegistry.executeCollection(_:observer:)` runs a collection and `executeCase(_:observer:)` selects one case while retaining collection hooks. Both return reports. Legacy `runCollection(_:)` and `runCase(_:)` remain available; they are not a replacement for Swift Testing observation.
- Inspect collectionNames/caseNames without running hooks; selectors belong in test entry points, not library CLI parsing.
- Name cases uniquely and make test selectors reject unknown names before paid work.
- Related cases may share a collection; current Create counter/plan entry points each construct a one-case collection, so separate Swift tests do not share collection setup.
- Shared preflight belongs before cases where implemented; per-case scope/ownership and stale credential-lifetime checks remain necessary.

Follow the actual generic initializer signatures in Scenario.swift and neighboring package tests; a typical entry point is:

```swift
import Scenario
import ScenarioTesting
import Testing

@Test @MainActor func providerScenarios() async throws {
    let collection = makeProviderCollection()
    let registry = try ScenarioRegistry([collection])
    let observer = ScenarioTestingObserver()
    if let selected = ProcessInfo.processInfo.environment["PROVIDER_SCENARIO_CASE"] {
        let report = try await registry.executeCase(selected, observer: observer)
        try report.requireSuccess()
    } else {
        let report = try await registry.executeCollection("provider", observer: observer)
        try report.requireSuccess()
    }
}
```

- Agent paid entry points include `.enabled(if: environment["AGENT_SCENARIO_LIVE"] == "1")`; an unset gate skips, never passes, and still requires user authorization to enable.
- Steps describe observable behavior and assert actual typed responses, not model self-reports or unconditional success markers.
- Teardown handles partial setup, assertion failure, cancellation and timeout; cleanup runs outside the canceled case body.

## Compiler, isolation and cleanup

- Use explicit standalone Swift 6.4/default Swift Build, pinned Testing 6.2.3 and installed CLT SDK discovery; generated extensions use Bundle resource APIs.
- Standalone SDK-dependent compiler/import probes use Scenario.SDKCompiler explicit SDK configuration, never inherited SDKROOT or a fallback compiler.
- The small built-in compile/transitive-import gate precedes Create submission; setup failures must not masquerade as unsupported generated model APIs.
- Declare top-level and nested service environment overrides before signing; client HOME alone cannot isolate launchd service reads.
- Use Scenario.ProjectTemporaryDirectory for disposable paths beneath repository-root `.tmp/`, not system temp. Follow README.md#temporary-work; retained review fixtures/evidence there remain disposable.
- IsolatedScenarioHome owns private homes, selective credential staging and removal gates; only the installed compiler is linked into them.
- Credential snapshots remain selected, owner-only and non-refreshable with sufficient remaining lifetime; no entire user configuration tree, original refresh token, environment dump or auth data archive is permitted.
- Scope validation compares validated existing directory identity, permitting only trusted OS aliases while rejecting traversal and untrusted links; it is not a sandbox or future filesystem lease.
- Capture immutable OwnedProcessIdentity kernel path/PID/start during startup, revalidate before bounded TERM/KILL and confirm ESRCH before deleting in-use paths.
- Successful inner Pi/development cleanup confirmation gates outer service/host/home removal; failures retain owned fixtures/hosts and propagate, with credentials scrubbed.
- Never infer ownership from timestamp scans, a process name, PID alone, or Foundation path spelling; prior fixtures and user projects remain untouched.

## Assertions and evidence

- Typed operation status is separate from transport success; Test requires status passed and exitCode 0, not merely tool completion.
- ScenarioToolEvidence correlates actual ordered journal lifecycle IDs and Pi results, requiring complete successful nested ancestry; outer success/script text cannot prove a child result.
- Missing, colliding, mismatched, incomplete or Boolean-coerced numeric evidence fails closed.
- Preview paths/dimensions/metadata are text-only; no automatic image delivery, read call or tool order is required unless explicitly part of a case purpose.
- Successful Preview requires typed rendered status and bounded complete decoded PNG, valid chosen/default canvas, existing nonlinked selected source, scoped project artifact/archive, byte/hash identity and empty nonlinked render scratch.
- Rendering errors do not qualify as success but may recover; another call cannot supply missing lifecycle evidence for an earlier call.
- Descriptor-derived archive paths retain kernel spelling for strict no-follow consumers; preserve service decoding/archive validation and VisionCLI protections.
- Optional Pi read compatibility is not model inspection evidence; Create independently reviews its last validated image through VisionCLI/Gemini when authorized, checking request/model/criteria/hash/dimensions/verdict/exit.
- Vision uncertainty is inconclusive and operational errors are distinct from visual failure; probabilistic review never replaces behavioral tests.
- Authored Test audits require successful scoped writes/edits, unchanged revisions before a matched pass, bounded compiler-parsed Testing/@Test/#expect behavior checks and independent assertions, not comments/starter-test decoys.
- Counter probes require exactly one supported signed-integer model.count/model.state.count API and actual 0 → 2 → 1 → 0 → -1 → 0 tests; import/setup errors are not behavioral failures.
- Development launch/liveness is not production delivery, UI readiness/button interaction or persisted-counter relaunch evidence.
- Plan assertions correlate creation/addition/updates with source work and final client presentation without fixed IDs/titles/task count/global tool order.
- Chat assertions cover scoped history/replay/resume/isolation/abort and actual MCP execution; service-restart replay, endpoint accuracy and every capability are not automatically proven.
- New projects use scaffold version 9 with typed programmatic Core Data and model-owned presentation; app-specific entities extend ApplicationPersistence.makeSchema() and production UUID storage ends in CoreData/data.sqlite.
- Protected composition, isolated in-memory construction and explicit store close before cleanup remain intact.
- Architecture, bounds and current runbooks stay in the owning module README.md; global policy stays in GUIDANCE/CONVENTIONS, incident narratives in LEARNINGS and historical checkpoints in docs/verification-archive.md rather than duplicated run-history paragraphs in skills.

## Verification and completion

- For scenario-only changes, run selected cases/offline audit regressions rather than unrelated unit suites.
- Underlying library/runtime changes use focused failing tests, the smallest complete fix and affected package suites.
- Live/package-host cases remain excluded when verification authorization covers only offline tests; some host tests execute without opt-in, so gates alone are insufficient.
- Package-local signed hosting is required to verify actual XPC changes when authorized; synthetic evidence alone does not establish a deployed runtime pass.
- Scoped swift-format, GuardFormatTool and strict SwiftLint apply to changed Swift sources; source/artifact rules forbid editing plugin outputs or built apps by hand.
- App-affecting changes require the project's signed bundle rebuild, but bundling is not a scenario prerequisite or authorization for GUI/model calls.
- Update relevant contract/guidance documents and only observed learnings; report final verification separately from historical results and unexercised runtime paths.
