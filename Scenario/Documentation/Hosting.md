# Lifecycle and signed hosting

[Scenario introduction](../README.md) · [Isolation and cleanup](Isolation-and-cleanup.md) · [Compiler and SDK](Compiler-and-sdk.md)

## Lifecycle and selection

- [Scenario.swift](../Sources/Scenario/Scenario.swift) provides main-actor `Step`, `ScenarioCase`, `ScenarioCollection` and `ScenarioRegistry`.
  - Project-owned reference types conform to `CollectionContext` and `CaseContext`. A shared collection context is passed to case-context factories; each case has its own local context.
  - Registry names match `^[a-z][a-z0-9-]{0,63}$`. There must be 1–64 collections, at most 100 cases per collection, unique collection names and globally unique case names.
  - `collectionNames` and `caseNames` list registrations without constructing contexts or executing hooks. `runCollection` runs all its cases; `runCase` runs one case with the surrounding collection hooks. Unknown names throw.
- New cases declare `setup: [Step]`, `behaviour: [Step]` and `cleanup: [CleanupChain]`. Each phase has a distinct purpose.
  - Setup prepares owned fixtures. Behaviour exercises operations and asserts their outcomes. Cleanup releases resources.
  - Collections also accept named `setup` steps and `cleanup` chains: `ScenarioCollection(name, context: factory, setup: steps, cases: cases, cleanup: chains)`.
  - All factories stay lightweight. Acquire resources in setup and record ownership before a later operation can fail.
- Execution order is collection context, collection setup, each selected case's context/setup/behaviour/cleanup, then collection cleanup.
  - Setup failure skips remaining setup and all behaviour in that scope. Behaviour failure skips remaining behaviour.
  - Ordinary case failure does not prevent later cases. Collection setup failure skips all selected cases.
  - A throwing context factory records a context problem. No unavailable context can be cleaned up.
  - Partial setup still receives cleanup. Eligibility inspects actual ownership, not setup success.
- Each `CleanupChain(name, eligibility: check, steps: steps)` is ordered and fail-fast.
  - Eligibility defaults to `.run`. Return `.notAcquired` only for demonstrably absent resources. Throw for uncertain ownership.
  - Failed eligibility or a failed cleanup step skips the remaining chain. Explicitly independent chains continue in declaration order.
  - Keep dependent release and deletion in the same chain or existing gated helper. Cross-chain dependency graphs are not supported.
  - `CleanupState.report` snapshots completed operations, earlier chains and inner cases. A synchronized relay includes caller cancellation received during earlier cleanup chains without cancelling cleanup. Snapshots are point-in-time evidence, not deletion authorization.
- Cancellation stops starting normal work and subsequent cases. Each available scope's cleanup runs in a fresh main-actor unstructured task and is awaited.
  - Cleanup inherits task locals, including Testing context, but not caller cancellation. Caller cancellation is still reported.
  - Cancellation errors and failed cleanup remain failures. Independent cleanup chains still receive an opportunity.
  - Cleanup can wait indefinitely if downstream code does. Bodies must cooperate with cancellation and own their deadlines.
  - Blocked actors, forced process termination and escaped work can defeat cleanup. No automatic timeout abandons it.
- Legacy setup/steps/teardown initializers adapt hooks to synthetic named operations. `runCase` and `runCollection` still throw after applicable cleanup.
  - Legacy unnamed steps retain execution-time failure. New blank declaration names fail registration before acquisition.
  - No deprecation or automatic consumer migration is imposed.
- CLI parsing and product-specific selection remain outside the library. The developer [scenario-run helper](../../.pi/skills/scenario-run/SKILL.md) has separate stop-on-failure/no-retry orchestration and does not own fixture cleanup.

## Reports and assertion observation

- `executeCase(name, observer:)` and `executeCollection(name, observer:)` return `ScenarioReport` after cleanup.
  - Invalid selection or unavailable observer context throws before acquisition.
  - Runtime problems are returned. Call `report.requireSuccess()` to throw `ScenarioExecutionFailure`, which retains the report.
  - Thrown diagnostics retain each problem's collection, optional case, phase, optional cleanup chain and step identity. Legacy synthetic setup/teardown labels remain visible.
  - `steps` preserve order, collection/case identity, phase, optional chain, status, elapsed duration and problems.
  - `bodyProblems` and `cleanupProblems` remain separate. `cancelled` also includes caller cancellation even when a closure returns normally.
  - Unselected cases are absent. A disabled outer Swift test produces no Scenario report.
- Status is `completed` for normally returning unobserved operations. It is not an assertion pass.
  - `passed` means the installed observer covered the operation and saw no unexpected issue. It does not prove that assertions were present.
  - `failed` preserves thrown errors or observed assertion problems. `skipped` carries a structured `ScenarioSkipReason`.
  - Reasons include prior setup/behaviour failure, collection setup failure, unavailable context, cancellation, failed cleanup prerequisite and unacquired resource.
- Optional `ScenarioTestingObserver()` observes nonthrowing issues inside active Swift Testing tests. It returns issues unchanged.
  - Unexpected `#expect` failures stop subsequent body steps. `#require` throws and is also observed. Known issues and warnings do not become failures.
  - The adapter depends on pinned Testing 6.2.3 and Experimental `Issue.isFailure` SPI. Core Scenario does not import Testing.
  - Testing system issues bypass issue-handling scopes. Swift Testing remains authoritative for overall test success.
  - Detached work can lose test context. Background work that outlives its step escapes attribution. Await assertion-producing work before returning.
  - A missing active test is rejected before factories run. Concurrent observations use independent task-local scopes and synchronized counters.
- Reports are in-memory records, not a stable persistence schema. Assertion summaries omit assertion payloads. Thrown diagnostics are bounded but can still contain caller data; keep reports private.

## Choose a host

- [PackagedTestHost](../Sources/Scenario/PackagedTestHost.swift) stages an existing Swift test Mach-O bundle with its matching SwiftPM loader.
  - Use it when a package-local test should directly drive production client models and real services.
  - Declare `TestHostService`, optional nested `TestHostApplication` providers and `TestHostResource` inputs. Services go in `Contents/XPCServices`, providers in `Contents/Applications`, and declared resources in their owner's `Contents/Resources`.
- [PackagedXPCHost](../Sources/Scenario/PackagedXPCHost.swift) stages a generated headless terminal client plus one real XPC service from an `XPCHostDefinition`.
  - Supply app/service executable and plist inputs plus explicit app/service resources.
  - `XPCHostDefinition.serviceEnvironment` and `clientEnvironment` default to empty dictionaries. Existing callers need no changes.
  - Service overrides merge into the supplied unsigned plist before signing. Explicit values win over its `XPCService.EnvironmentVariables`. Repository `TMPDIR` wins last. Other service plist keys are preserved.
  - Client overrides flow through the existing `XPCClientAdapter`. Host-generated `OPENXPC_PROJECT_ID` and `OPENXPC_SESSION_ID` win over caller values. The adapter applies repository `TMPDIR` last.
  - Neither dictionary changes the parent process environment. Supply both when client and launchd service homes must agree.
  - `request` validates exit 0, version/request/project identity, success and a bounded base64 JSON-object payload. `expectRejected` requires exit 1 and an identified failure envelope with the expected error, allowing absent or null payload.
  - Keep UUID wire spelling (`UUID.uuidString`) distinct from lowercase filesystem naming.
- [PackagedApplicationHost](../Sources/Scenario/PackagedApplicationHost.swift) verifies and copies an explicitly supplied deployed app, assigns new nested app/service identities and re-signs it.
  - It retains the real client unless a replacement executable is explicitly supplied. `run` uses the bounded JSONL adapter.
  - This optional deployed-app inspection path is not a prerequisite for ordinary package-local scenarios and does not prove the original signed identity or GUI was exercised.

## Declare and stage inputs

- Build prerequisites through the consuming package's entry point, then supply exact executable/resource locations. Scenario does not build the full product implicitly or fall back to undeclared source-tree resources.
- `prepare()` validates inputs, creates a disposable host, assigns isolated bundle/service identifiers, signs components and verifies the resulting app. Repeated preparation while staged is rejected; failed preparation removes its partial packaging.
- `TestHostResource.relativePath` is relative to the owning Resources directory, not an arbitrary absolute destination. Traversing/empty/dot components and linked inputs are rejected.
  - PackagedTestHost regular-file inputs are bounded to 256 MiB; resource trees reject links and exceedance of 16,384 enumerated entries. Destination paths are at most 1024 UTF-8 bytes.
  - PackagedXPCHost resource traversal additionally bounds depth to 12, entries to 1024 and bytes to 16 MiB per app/service resource-staging call; plists are bounded to 64 KiB.
  - PackagedApplicationHost rejects linked copied contents and more than 4096 enumerated entries; its plist reader is bounded to 64 KiB.
  - These APIs have different checks; do not infer a uniform filesystem-hardening guarantee across them.
- For SwiftPM `Bundle.module`, stage the resource bundle under the **owning service's** `Contents/Resources`. A host-level copy alone cannot establish service lookup. Include a host copy separately only where consumers require it.
- `TestHostService.environment` and `XPCHostDefinition.serviceEnvironment` merge overrides into `XPCService.EnvironmentVariables` **before signing**. Client process environment alone does not establish a launchd service home. See [isolation](Isolation-and-cleanup.md#home-isolation).

## Run a filtered Swift test

- A macOS SwiftPM `.xctest` is a directory containing a Mach-O bundle, not a directly executable test program. Supply the bundle's Mach-O file as `testBundleExecutable`, not the `.xctest` directory.
- Resolve `PackagedTestHost.swiftPMTestLoader()` from the same standalone toolchain. The staged invocation is:

```text
swiftpm-testing-helper --test-bundle-path <host>/Contents/Resources/TestBundle \
  --testing-library swift-testing --filter <module/test-prefix>
```

- `runTest(filter:environment:timeoutSeconds:)` returns process `status` and combined `output`.
  - Filters must be nonempty and at most 512 UTF-8 bytes; timeout is 1–3600 seconds, default 2100.
  - Returned output is limited to 64 KiB. A timeout terminates the loader, escalates to KILL after a bounded wait and throws.
  - A loader exit 0 is not proof that a selected test ran. Consuming tests must require actual selected-test started/passed markers to reject zero-test runs.
  - This command's child handling is not service/Pi/development-process cleanup confirmation.
- `withInputDirectory` owns a temporary preparation-input directory for its closure. `runPreparation` executes bounded prerequisites with the [Swift routing contract](Compiler-and-sdk.md#preparation-routing).
- After requests and inner teardown finish, confirm exact-owned service reaping before `remove()`. All three host types remove packaging only; they do not discover/reap all launched services. See [cleanup order](Isolation-and-cleanup.md#cleanup-order).

## JSONL adapter limits

- [XPCClientAdapter](../Sources/Scenario/XPCClientAdapter.swift) invokes a packaged headless client, not a service executable or generic compiler command.
- Input must be a JSON object/array accepted by JSONSerialization, at most 64 KiB and contain no LF; the adapter adds exactly one trailing LF.
- Response must have exactly one final LF and empty stderr. Response limits are configurable from 1–128 KiB (default 64 KiB), timeout from 1–360 seconds (default 75).
- `Reply` contains exit status and line bytes without the LF. Callers validate response JSON/schema and typed operation status separately; framing alone is not operation success.
- Timeout requests TERM and waits up to five seconds. This is not the exact-identity TERM/KILL/ESRCH contract; callers must not treat adapter return/timeout as proof all related processes exited.
