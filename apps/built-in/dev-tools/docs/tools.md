# Tool execution and results

[DevTools](../README.md) · [Preview contract](preview.md) · [Verification](verification.md)

## Scope and transport

- [OpenXPC.yaml](../OpenXPC.yaml) declares a 65,536-byte maximum payload. [OpenXPCGen.yaml](../OpenXPCGen.yaml) configures a 600-second generated service timeout; individual child deadlines below are separate and shorter.
- Every request includes an extension-injected `projectRoot` (maximum 4096), with UUID project/session IDs in the XPC envelope. These IDs select scope, not authentication.
- [ProjectResolver](../Sources/Application/ProjectResolver.swift) selects an existing lowercase UUID directory under the service's `~/.mac-apper`, checks root identity, a regular bounded `Package.swift` (at most 1 MiB), and matching `app-manifest.json` (at most 16 KiB).
- The manifest has exactly `schemaVersion`, `appID`, `executableTarget`, `previewTarget` and `devServiceID`, with schema version 1, distinct valid target names and `devServiceID: com.macapper.generated.<lowercase-app-uuid>`.
- [ProjectScope](../Sources/Application/ProjectScope.swift) rejects traversal, empty/dot components, backslashes, control characters and linked project-relative components. Relative paths are bounded to 1024 UTF-8 bytes. System alias normalization does not permit a linked project directory.
- The shared operation gate excludes concurrent operations and returns busy rather than queueing a second request. Source/generated-code execution remains under user permissions, not in a sandbox.
- XPC/terminal success means a response arrived. Typed Test or Preview errors can still arrive in a successful tool call. Invalid scope/request and thrown controller failures instead produce operation/transport failure. Never infer a passing workflow from a completed Activity entry.

## Build

- Pi arguments are an empty object; arbitrary shell commands, targets and filters are not accepted. The validated manifest selects `executableTarget`.
- [BuildController](../Sources/Application/Controllers/BuildController.swift) runs standalone:

  ```text
  swift build --product <executableTarget> --configuration debug
    --scratch-path <project>/.mac-apper/Build/<request-uuid>
  ```

- Compilation has a 90-second child deadline and 65,536-byte captured-output limit. Nonzero exit, unavailable tools, overflow and owned-process failures cannot qualify as a build pass.
- `BuildResult` returns `summary` (bounded to 4096) and `target` (256). There is no typed `passed|failed` field equivalent to Test.
- Build neither stages nor signs/registers/launches an app and does not create production output. Its request build directory is not covered by Test/Preview's disposable-scratch removal promise.

## Test

- Pi arguments are an empty object. All test targets in the validated package run; there is no model-supplied command, target or filter.
- [TestController](../Sources/Application/Controllers/TestController.swift) runs standalone:

  ```text
  swift test --configuration debug
    --scratch-path <project>/.mac-apper/TestBuild/<request-uuid>
  ```

- Each request creates a previously absent private, nonlinked scratch directory. It removes only that owned request directory after success, failure or Swift-task cancellation, without modifying source or the project's `.build`.
- Execution is bounded to 180 seconds and 65,536 captured output bytes. Compiled tests execute with user permissions.
- `TestResult` contains:
  - `status: passed|failed|error` and `summary` (maximum 1024).
  - Optional `exitCode`, `diagnostics` (at most 4096 UTF-8 bytes of tail output), and `outputTruncated`.
  - Long compiler invocation lines are compacted before tail selection; compaction, overflow or tail truncation sets `outputTruncated`.
- **Passed** requires SwiftPM exit 0. **Failed** reports nonzero assertion/compilation exits. **Error** covers launch/preflight failure, deadline or output overflow; absent exit code is not zero.
- Missing standalone tools return `status: error` with an actionable version/path and no exit code, then owned scratch is removed. Cancellation remains cancellation rather than a manufactured pass.
- Write meaningful behavioral tests, fix failures and rerun after source/test edits before claiming verification. Exit 0 alone proves neither test coverage nor UI interaction; Build, Preview and Run remain separate operations.

## Run

- Pi arguments are an empty object. [RunController](../Sources/Application/Controllers/RunController.swift) uses Build's selected executable and limits, then stages `.mac-apper/DevBuild/<request-uuid>/<target>.app`, including bounded-scope executable/resource validation and bundle metadata.
- It launches the staged executable directly, checks immediate liveness and tracks it as an owned process. Replacement stops the previous live instance for that project; a monitor reaps ended instances.
- `RunResult` returns `summary` (4096), `target` (256) and project-relative `relativePath` (4096).
- Child output is bounded to 65,536 bytes. Process ownership/cancellation cleanup is implemented by [OwnedProcess](../Sources/Application/OwnedProcess.swift); Run does not report a former readiness handshake.
- A launch result proves neither UI readiness, model correctness, persisted relaunch state nor a distributable production app. Development staging is separate from `~/.mac-apper/output/<project-id>/` production packaging.

## Plan

- [PlanStore](../Sources/Application/PlanStore.swift) holds plans in service memory keyed by project, not session. Restart durability is not provided.
- Actions:
  - `add_plan`: create once; omitted `tasks` creates an empty plan. Explicit tasks must be nonempty and valid; `ids` is forbidden. Cannot replace an existing plan.
  - `add_tasks`: add nonempty unique task records with new IDs to an existing plan; `ids` is forbidden.
  - `update_tasks`: replace nonempty existing task records; unknown IDs fail and `ids` is forbidden.
  - `delete_tasks`: remove nonempty unique existing `ids`; `tasks` is forbidden.
  - `get_tasks`: retrieve an existing plan with neither `tasks` nor `ids`.
- A plan has at most 100 tasks and at most one `in_progress`. IDs are 1–64 UTF-8 bytes of lowercase ASCII letters, digits or hyphens; titles are nonblank and at most 256 UTF-8 bytes. Status is `pending`, `in_progress`, `completed` or `blocked`.
- Mutations validate before storage; rejected additions/updates do not partially mutate a plan, and rejected initial tasks do not consume the creation slot. Deleting the last task leaves a retrievable empty plan.
- `PlanResult` returns a bounded summary and the full task snapshot (at most 100 records). Agent task presentation follows successful snapshots, never rejected tool-start arguments.

## Preview and compiler routing

- [Preview](preview.md) owns rendering-specific inputs, child limits, status and artifact paths.
- [DevTools setup](../README.md#setup-and-first-checks) owns standalone Swift selection. Build/Test/Preview route production `xcrun swift`/`swiftc` requests through that selection with `SWIFT_EXEC`; SDK discovery and injected nonproduction tools retain their separate behavior.
