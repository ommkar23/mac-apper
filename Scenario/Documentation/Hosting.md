# Lifecycle and signed hosting

[Scenario introduction](../README.md) · [Isolation and cleanup](Isolation-and-cleanup.md) · [Compiler and SDK](Compiler-and-sdk.md)

## Lifecycle and selection

- [Scenario.swift](../Sources/Scenario/Scenario.swift) provides main-actor `Step`, `ScenarioCase`, `ScenarioCollection` and `ScenarioRegistry`.
  - Project-owned reference types conform to `CollectionContext` and `CaseContext`. A shared collection context is passed to case-context factories; each case has its own local context.
  - Registry names match `^[a-z][a-z0-9-]{0,63}$`. There must be 1–64 collections, at most 100 cases per collection, unique collection names and globally unique case names.
  - `collectionNames` and `caseNames` list registrations without constructing contexts or executing hooks. `runCollection` runs all its cases; `runCase` runs one case with the surrounding collection hooks. Unknown names throw.
- Steps run in order. A failed setup/step skips the remaining steps of that case, but applicable case/collection teardown still runs and failures are combined.
  - A failed case does not prevent later collection cases. The library is not a stop-on-first-case-failure runner.
  - If context construction itself throws, no context exists for its teardown. Hooks must account for partially completed setup.
  - Abrupt external termination can prevent teardown; lifecycle hooks are not a guarantee of cleanup.
- CLI parsing and product-specific selection remain outside the library. The developer [scenario-run helper](../../.pi/skills/scenario-run/SKILL.md) has separate stop-on-failure/no-retry orchestration and does not own fixture cleanup.

## Choose a host

- [PackagedTestHost](../Sources/Scenario/PackagedTestHost.swift) stages an existing Swift test Mach-O bundle with its matching SwiftPM loader.
  - Use it when a package-local test should directly drive production client models and real services.
  - Declare `TestHostService`, optional nested `TestHostApplication` providers and `TestHostResource` inputs. Services go in `Contents/XPCServices`, providers in `Contents/Applications`, and declared resources in their owner's `Contents/Resources`.
- [PackagedXPCHost](../Sources/Scenario/PackagedXPCHost.swift) stages a generated headless terminal client plus one real XPC service from an `XPCHostDefinition`.
  - Supply app/service executable and plist inputs plus explicit app/service resources.
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
- `TestHostService.environment` merges overrides into `XPCService.EnvironmentVariables` **before signing**. Client process environment alone does not establish a launchd service home. See [isolation](Isolation-and-cleanup.md#home-isolation).

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
