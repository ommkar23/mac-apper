# Chat and Create scenarios

[Agent introduction](../README.md) · [Verification commands](verification.md) · [Runtime](runtime.md) · [Recorded evidence](evidence.md)

## Entry points and authorization

- Package-local Swift tests are the supported path. Root Scenarios, standalone runner/clients and Scenario command plugin are retired; historical dist artifacts remain preserved.
- [Scenario](../../Scenario/README.md) owns reusable packaging and temporary hosting; tests own prompts, assertions, process/session audits and fixture cleanup. There is no scenario-specific Agent client, transport bridge or full product bundle prerequisite.
- Follow [scenario-run](../../.pi/skills/scenario-run/SKILL.md) for authorized selection/monitoring and [scenario-write](../../.pi/skills/scenario-write/SKILL.md) for authoring. Supplied Swift helpers launch selected commands only and do not take cleanup ownership.
- Explicit live authorization is required before enabling these cases: Chat starts Pi/Parallel; both Create variants use paid Pi and Gemini. The offline app request rejects Parallel MCP calls. Do not inspect/refresh credentials or invoke check-config merely to read this document.
- Initialize swift64 as described in [verification](verification.md#compiler-setup), then run from the repository root only when authorized:

```sh
# One Chat case; omit AGENT_SCENARIO_CASE for all eight sequentially.
AGENT_SCENARIO_LIVE=1 AGENT_SCENARIO_CASE=chat-model-greeting \
  "$swift64" test --package-path Agent --filter agentChatScenarios
# Counter and plan are separately selectable/authorized.
AGENT_SCENARIO_LIVE=1 "$swift64" test --package-path Agent --filter agentCreateCounterScenario
AGENT_SCENARIO_LIVE=1 "$swift64" test --package-path Agent --filter agentCreatePlanScenario
```

- AGENT_SCENARIO_PRODUCTS and DEV_TOOLS_SCENARIO_PRODUCTS select existing debug product directories for custom scratch builds. AGENT_CREATE_KEEP_PROJECT=1 retains the owned Create project.
- Filters use scenario names without end anchors/parentheses. Require actual selected-test started/passed markers and exit 0; zero-test selection is not a pass. Helper status is last recorded state, not process liveness or proof of completion.
- Scenario-only commands do not run offline units; underlying runtime/library changes separately require focused and affected package tests. This rewrite executes none of these paths.

## Production path and Chat collection

- **Production path and packaging**
  - Agent separates service-only, client-model-only, native-client-only and cross-target AgentTests, with native-client tests depending only on the client and importing its model transitively.
  - AgentScenarioTests drives WorkspaceSession, AgentXPCRuntime and AppModel through production AgentServiceXPCAdapter/generated client in AgentMacosClientModel without a new client target, generation configuration, transport bridge or production assertions.
  - PackagedTestHost stages the existing test Mach-O bundle with the matching SwiftPM loader, real Agent service/catalog/extensions/resources and isolated signed identities, then runs only the filtered test and removes owned packaging after confirmed cleanup.
  - AGENT_SCENARIO_PRODUCTS overrides Agent debug products for custom scratch builds.
- **Chat collection**
  - `AGENT_SCENARIO_CASE` selects one of the following eight cases, otherwise all run sequentially in one host with prompts/assertions/deadlines/fixtures owned by tests.
  - Every case audits Pi and assistant metadata for `openai-codex/gpt-6.1-sol/medium` and completed Chat model presentation.
  - `chat-model-greeting` verifies greeting through the production model.
  - `country-news-japan` requires exactly five bounded JSON items with recent UTC dates, distinct HTTP(S) sources and matched actual codemode/MCP search-fetch successes, without proving factual correctness or objective ranking.
  - `chat-follow-up` checks the same third story and expanded summary.
  - `chat-disconnect-replay` detaches during tool work without stopping Pi, checks journal advance/original PID-start continuity, replays into AppModel and requires model replay-plus-push to equal contiguous native journal history before reopening/submitting.
  - `chat-resume` stops Pi, opens the saved conversation through WorkspaceSession and recalls an opaque marker with a new PID.
  - `chat-session-isolation` runs two model sessions concurrently, excludes foreign markers from presentation/Pi histories/journals and uses the existing scoped adapter to verify foreign-session rejection.
  - `chat-abort-reuse` aborts through the model runtime and reuses the same session/Pi process.
  - `chat-capabilities` checks actual codemode-only launch argv, successful nested tools and no scaffold/UUID project creation, with the clarified prompt requiring search followed by fetch and a fetched-page-derived summary rather than snippets/memory.
  - Startup captures argv before Pi can rewrite it, while later process checks use captured PID/start identity.
- **Chat bounds and teardown**
  - Each case has a 220-second deadline with cleanup outside the canceled body, and the hosted collection has a 2100-second bound.
  - Teardown stops owned Pi, closes subscriptions, confirms exact kernel-path/PID/start reaping and archives only owned histories before fixture session/journal deletion.
  - Outer service/host cleanup requires inner confirmation, failed hosts retain evidence and unrelated conversations/dist artifacts are preserved, while abrupt external termination can prevent cleanup.
  - Live coverage includes current-session subscription/disconnect/replay and persisted resume rather than service-restart journal replay or retroactive histories.

## Create counter and plan contracts

- **Shared workflow**
  - `agentCreateCounterScenario` and `agentCreatePlanScenario` stage the existing tests plus production Agent/DevTools/authored extensions/VisionCLI in a minimal signed host and drive the production client model/native adapter.
  - The feature-only counter prompt requests behavior and launch without Preview mechanics, which come from system/tool instructions rather than scenario-supplied implementation guidance.
  - Both cases audit runtime/scope/Preview availability and independently require actual successful Test, Preview, Build and Run without prescribing cross-tool order, source filename, count or canvas.
  - Preview checks independently decoded PNG/dimensions, chosen/default canvas, complete envelope, source/scratch scope and artifact/archive identity without OCR, read or image-forwarding requirements.
  - Generated source review, generated-plus-independent tests, development liveness and removed Preview workspaces are separate checks, with Parallel MCP calls rejected for this offline app request.
  - Production output is reported separately because development Build/Run does not create `~/.mac-apper/output/<project-id>/` bundles, and the app name remains service-owned scaffold metadata.
- **Authored Test evidence**
  - Before harness assertions are injected, CreateCounterTestEvidence requires saved matched successful Test status passed/exitCode 0 following successful scoped agent write/edit revisions under `Tests/AppModelTests/*.swift` with no later edit invalidating that pass.
  - Passing untouched starter tests before authoring new tests is insufficient, while bounded nonlinked compiler `-dump-parse` output must show import Testing, annotated @Test functions with #expect and count/increment/decrement/reset references inside those functions rather than comments/string decoys.
  - Supporting helper files need not import Testing, and no particular filename/function name, failure-retry cycle or cross-tool ordering is imposed.
  - Launch argv must expose Test and client activity must show completion, while structural authorship evidence does not prove exhaustive coverage and independent assertions remain required.
  - Parsing is bounded to 15 seconds/file, 64 KiB/source and 1 MiB/output with private temporaries and no macro/model execution, using a non-stable textual AST adapter with historical Apple 6.2.3 and standalone 6.4 evidence.
- **Independent behavior**
  - The harness builds actual AppModel privately and compiler-typechecks signed-integer `model.count` and `model.state.count`, requiring exactly one supported API and rejecting ambiguous/unsupported layouts or comment/string decoys.
  - Actual injected Swift Testing assertions must compile/run/pass alongside generated tests for the unchanged 0 → 2 → 1 → 0 → -1 → 0 action sequence rather than adapting source to the harness.
  - Offline mutants cover wrong steps, clamped negatives and broken reset as behavioral failures rather than compilation evidence, with direct/state and retained Core Data source exercised.
  - Bounded compiler commands retain private `/private/tmp` logs, and in-memory behavior plus process liveness does not independently prove generated-counter relaunch persistence.
- **Plan-specific evidence**
  - The plan variant adds an implementation-plan request to the same workflow and requires successful saved add_plan, task addition through initial tasks or add_tasks, and update_tasks.
  - A task must be in_progress during a successful Swift source write/edit and later completed by an update, with a final nonempty fully completed plan matching client tasks.
  - IDs, titles, task count and overall tool order remain agent-selected, verifying implementation-time plan use rather than a final checklist or self-report.
- **Vision review and deadlines**
  - Local VisionCLI build/check-config precedes Create and only its executable is staged, never `.env`, with GEMINI_API_KEY overriding private `VisionCLI/.env` and AGENT_VISION_ENV_FILE selecting an alternate absolute private file.
  - One integrated pinned `gemini-3.8-flash` review of the last validated preview checks readable integer count, legible Increment/Decrement/Reset labels and no clipping/overlap, with uncertainty inconclusive and operational errors distinct from visual failures.
  - Assertions check request UUID/model/exact criteria, dimensions/SHA-256, aggregate verdict and exit code, without prescribing particular preview state or dimensions.
  - The reviewer uses a 120-second child deadline, bounded private temporary I/O/cancellation cleanup and CREATE_VISION logging, inside 1020-second case and 1320-second hosted bounds.
  - Only the reviewer contacts Google while the generated app remains offline, and accuracy calibration/negative-uncertain live coverage remain unverified.
- **Project retention**
  - Teardown stops Pi/development and removes only the UUID fixture project unless AGENT_CREATE_KEEP_PROJECT=1 retains it, leaving existing projects untouched.
  - Successful previews remain separately archived after project removal with CREATE_PREVIEW_RETAINED reporting their path.

## Create isolation and cleanup

- **Home and credentials**
  - IsolatedScenarioHome and pre-signing TestHostService.environment overrides scope client, Agent/DevTools launchd services and inherited development children to private HOME/CFFIXED_USER_HOME, linking only the installed compiler rather than user configuration trees.
  - Agent-specific preparation stages a bounded owner-only Codex access/account/expiry snapshot in private Pi config with an empty refresh field and at least 1500 seconds remaining before the 1320-second hosted invocation.
  - Lifetime is checked again before invocation and insufficient lifetime blocks startup rather than refreshing original authentication, without copying/linking original refresh credentials or other user configuration.
  - Development SQLite must reside in the owned home, with only owned histories/previews privately archived outside it.
- **Cleanup gate**
  - Runtime stop precedes exact Pi kernel-path/PID/start reaping and ESRCH, then stop/detach confirmation, development cleanup and archive/project handling.
  - Inner cleanup confirmation gates outer exact Agent/DevTools reaping, credential scrubbing and host/home removal, with failed assertions retaining scoped fixtures after safe cleanup and cleanup failures retaining fixtures without bypass.
  - Production runtimes and feature prompts/behavioral assertions are not replaced by the isolation harness.

## Scenario scope identity

- **Directory identity contract**
  - ScenarioSessionAudit compares validated existing recorded/expected directory identities using descriptor-derived canonical paths and device/inode equality rather than literal alias strings, prefix replacement or suffix matching.
  - Descriptor-relative traversal rejects missing/non-directory or relative paths, dot/traversal/empty components, NUL/backslash and untrusted ancestor/leaf links even for identical input strings.
  - Only root-owned OS links beneath wholly root-owned non-group/world-writable ancestors without extended ACLs are eligible aliases, with targets traversed under the same bounded expansion rules so `/tmp` and `/var` work while user/project links fail.
  - Unsupported ACL/path lookup or unusual alias targets fail closed, and these private scenario-support point-in-time checks do not alter production validators or prevent subsequent filesystem mutation.

## SDK startup gate

- **SDK and startup gate**
  - Scenario.SDKCompiler discovers the system-installed SDK with bounded `xcrun --sdk macosx --show-sdk-path`, validates directory/settings/header and passes explicit -sdk to standalone Swift 6.4 without hardcoding SDK version or requiring Xcode.
  - The system SDK alias is resolved and inherited SDKROOT removed only for these child commands, preserving production runtime/compiler selection.
  - Both counter variants compile a Foundation/Darwin/os/CoreData/Observation module and typecheck its transitive import before creating the Pi submission task, sharing actual probe compiler/SDK/frontend/environment/runner configuration through independent verification.
  - Direct frontend probes need neither driver/link jobs nor external macro expansion, with 10-second discovery, 30-second compiler commands, 1 MiB output and UUID-private scratch removed after owned reaping.
  - Timing/actionable diagnostics plus a separate actual AppModel import guard distinguish setup/framework failure from genuinely unsupported count APIs, preserving ambiguous-layout and action-assertion rejection.

## Exact-owned process teardown

- **Exact-owned teardown**
  - OwnedProcessIdentity.reap rejects invalid PIDs before probing and revalidates exact kernel executable path and microsecond start identity before each TERM/KILL.
  - Failed validation/signaling is already-reaped success only after a fresh kill(pid, 0) returns ESRCH, while live mismatch, unavailable identity, permissions or observed PID reuse fail closed without further signals.
  - Existing 2-second TERM and 10-second final waits remain bounded, with kernel inspection/signaling separate point-in-time operations rather than atomic PID-reuse protection.
  - Demonstrated offline races do not establish the component or cause of the historical mismatch, and inner/outer retention gates remain unchanged.

## Shared tool evidence

- **Evidence correlation**
  - ScenarioToolEvidence matches ordered actual journal starts/completions by IDs to direct Pi results and complete nestedCalls ancestry, rejecting missing/colliding/mismatched evidence rather than inferring child success from scripts or parents.
  - Nested metadata holds pre-hook arguments/statuses rather than results/images, and typed child results come from actual journal text with every intermediate ancestor required to succeed.
  - Preview audits require one complete bounded PNG with declared dimensions before decoding, a bounded nonlinked selected source up to 1 MiB, correctly typed canvas metadata, absent/empty nonlinked render scratch and archive scope/filename/byte identity with retained SHA-256.
  - Typed render errors may precede recovery but cannot satisfy success, later unrelated results cannot repair earlier evidence, and matching Build/Run plus independent Test/plan/runtime/model/Gemini checks remain separate.
  - Integer evidence rejects CFBoolean rather than coercing false to exitCode 0, and negative fixture issues are intentional rejections rather than production known failures.
## Cross-module specifications and limits

- [DevTools](../../apps/built-in/dev-tools/README.md) owns provider-only plan/test/preview/toolchain signed-XPC cases; they do not require Agent or live models.
- [VisionCLI](../../VisionCLI/README.md) owns bounded image requests, credential precedence, structured criteria/verdicts and review exit codes. A review uploads the selected image/criteria and remains probabilistic evidence, not calibrated accuracy.
- Service-restart replay, retroactive pre-journal histories, physical button clicks, live retry/exhaustion recovery, production packaging/relaunch persistence and general app/capture coverage remain outside these scenario assertions.
- Historical live capabilities failure and the unresolved historical lifecycle cleanup failure remain in [recorded evidence](evidence.md); later passing fixtures do not resolve or authorize cleanup of them.
