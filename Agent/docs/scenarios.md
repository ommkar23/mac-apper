# Chat and Create scenarios

[Agent introduction](../README.md) · [Verification commands](verification.md) · [Runtime](runtime.md) · [Recorded evidence](evidence.md)

## Entry points and authorization

- Package-local Swift tests are the supported path. Root Scenarios, standalone runner/clients and Scenario command plugin are retired; historical dist artifacts remain preserved.
- [Scenario](../../Scenario/README.md) owns reusable packaging and temporary hosting; tests own prompts, assertions, process/session audits and fixture cleanup. There is no scenario-specific Agent client, transport bridge or full product bundle prerequisite.
- Follow [scenario-run](../../.pi/skills/scenario-run/SKILL.md) for authorized selection/monitoring and [scenario-write](../../.pi/skills/scenario-write/SKILL.md) for authoring. Supplied Swift helpers launch selected commands only and do not take cleanup ownership.
- Explicit live authorization is required before enabling these cases. Chat starts Pi/Parallel. Create counter and plan use paid Pi and Gemini. HTView uses paid Pi without a Gemini review. Create app requests reject Parallel MCP calls. Credential operations need separate authorization.
- Initialize swift64 as described in [verification](verification.md#compiler-setup), then run from the repository root only when authorized:

```sh
# One Chat case; omit AGENT_SCENARIO_CASE for all eight sequentially.
AGENT_SCENARIO_LIVE=1 AGENT_SCENARIO_CASE=chat-model-greeting \
  "$swift64" test --package-path Agent --filter agentChatScenarios
# Counter and plan are separately selectable/authorized.
AGENT_SCENARIO_LIVE=1 "$swift64" test --package-path Agent --filter agentCreateCounterScenario
AGENT_SCENARIO_LIVE=1 "$swift64" test --package-path Agent --filter agentCreatePlanScenario
# HTView uses Pi and DevTools without VisionCLI/Gemini.
AGENT_SCENARIO_LIVE=1 "$swift64" test --package-path Agent --filter agentCreateHTViewScenario
```

- AGENT_SCENARIO_PRODUCTS and DEV_TOOLS_SCENARIO_PRODUCTS select existing debug product directories for custom scratch builds. AGENT_CREATE_KEEP_PROJECT=1 retains the owned Create project.
- `AGENT_VISION_PRODUCTS` selects an existing absolute products directory containing `vision-cli`. Explicit input requires nonlinked directory ancestors and a nonlinked regular executable leaf. Empty, relative, traversal, missing, linked, nonregular and nonexecutable input fails without fallback or a default Vision build.
- Without this override, Vision preparation retains the legacy release build and `VisionCLI/.build/release/vision-cli` selection. Strict private runs must supply the override using the [private build recipe](../../VisionCLI/README.md#private-scenario-products).
- Preparation still runs the selected executable with `check-config --env-file` and stages only `VisionCLI/vision-cli`. It does not reuse hosted `AGENT_SCENARIO_VISION_CLI`. Cases without Vision ignore unused Vision overrides.
- The scenario-run helper clears inherited `AGENT_` variables, including `AGENT_VISION_PRODUCTS`. It exposes no arbitrary plan environment overrides. Private product selection requires a deliberate direct `swift test` invocation.
- Filters use scenario names without end anchors/parentheses. Require actual selected-test started/passed markers and exit 0; zero-test selection is not a pass. Helper status is last recorded state, not process liveness or proof of completion.
- Scenario-only commands do not run offline units; underlying runtime/library changes separately require focused and affected package tests. This rewrite executes none of these paths.

## Production path and Chat collection

- **Production path and packaging**
  - Agent separates service-only, client-model-only, native-client-only and cross-target AgentTests, with native-client tests depending only on the client and importing its model transitively.
  - AgentScenarioTests drives WorkspaceSession, AgentXPCRuntime and AppModel through production AgentServiceXPCAdapter/generated client in AgentMacosClientModel without a new client target, generation configuration, transport bridge or production assertions.
  - PackagedTestHost stages the existing test Mach-O bundle with the matching SwiftPM loader, real Agent service/catalog/extensions/resources and isolated signed identities, then runs only the filtered test and removes owned packaging after confirmed cleanup.
  - AGENT_SCENARIO_PRODUCTS overrides Agent debug products for custom scratch builds.
- **Chat collection**
  - [ChatTests.swift](../Tests/AgentScenarioTests/ChatTests.swift) owns `agentChatScenarios` and the `agent-chat` collection.
  - Conversation, session, capabilities and replay test files declare named setup and behaviour phases.
  - Lightweight discovery does not acquire sessions. Unknown selectors fail before host preparation.
  - Hosted and outer host phases use `ScenarioTestingObserver` and require successful reports. Observed nonthrowing assertions block later behaviour.
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
  - Each case starts one absolute 220-second deadline before acquisition. Every awaited setup/behaviour phase uses only the remaining budget and awaits cancellation of losing work.
  - Cleanup runs uncancelled outside that budget. The hosted collection retains its 2100-second bound.
  - Case ownership is registered before acquisition. Auxiliary replay releases run in reverse order before owned-session cleanup. All applicable attempts run and errors aggregate.
  - Teardown stops owned Pi, closes subscriptions, confirms exact kernel-path/PID/start reaping and archives only owned histories before fixture session/journal deletion.
  - Individual cases do not emit the cleanup marker. Collection cleanup emits it only after every constructed context confirms release and no cleanup issue was observed. Earlier case success cannot authorize removal after a later failure.
  - Outer service/host cleanup requires inner confirmation, failed hosts retain evidence and unrelated conversations/dist artifacts are preserved, while abrupt external termination can prevent cleanup.
  - Historical live coverage includes current-session subscription/disconnect/replay and persisted resume rather than service-restart journal replay or retroactive histories. This declaration-only migration has no new live verification.
  - Chat still does not pass a private service home to `prepareHost()`. Unique signed identities do not establish service-home isolation. This limit is not repaired here.
  - The historical capabilities missing-fetch failure remains unresolved live. Offline prompt/declaration checks do not prove model compliance.

## Create counter and plan contracts

- **Shared workflow**
  - `agentCreateCounterScenario` and `agentCreatePlanScenario` stage the existing tests plus production Agent/DevTools/authored extensions/VisionCLI in a minimal signed host and drive the production client model/native adapter.
  - The shared counter prompt requests the exact user-visible name `Pebble Counter`, behavior and launch. It supplies no naming or Preview tool recipe. Both Counter and Plan use this changed context.
  - First-request naming requires exactly one matched `set_app_name` invocation with a successful canonical typed result. Its completion must precede every attempted implementation write/edit and Build/Run start, including failed attempts. Successful implementation work must leave a nonempty regular file. Reads and plan work may precede naming.
  - Root `Info.plist`, the exact successful Run result's development plist and the refreshed production-path library title must equal `Pebble Counter`. Direct root plist edits cannot substitute for naming. Provider argv exposure and completed activity are secondary checks.
  - Metadata naming must emit no native `MAC_APPER_RENAMED` notification and create no production output. The normal development Run remains required. These checks do not observe native window or application-menu titles.
  - `CreateNamingEvidenceTests` covers direct/nested positives and missing, duplicate, failed, wrong-result, ancestry, premature edit/build/run, script-only and mismatched final metadata controls offline. `ToolEvidenceTests` checks complete multi-level ancestry for naming as well as Test.
  - Focused offline selection: `"$swift64" test --package-path Agent --filter 'AgentScenarioTests\.(createNaming|toolEvidence)'`. Live selectors remain `agentCreateCounterScenario` and `agentCreatePlanScenario`. The naming changes require fresh authorized live verification; offline fixtures are not runtime evidence.
  - Both cases audit runtime/scope/Preview availability and independently require actual successful Test, Preview, Build and Run without prescribing cross-tool order, source filename, count or canvas.
  - Preview checks independently decoded PNG/dimensions, chosen/default canvas, complete envelope, source/scratch scope and artifact/archive identity without OCR, read or image-forwarding requirements.
  - Generated source review, generated-plus-independent tests, development liveness and removed Preview workspaces are separate checks, with Parallel MCP calls rejected for this offline app request.
  - Production output absence is asserted separately because development Build/Run does not create `~/.mac-apper/output/<project-id>/` bundles. Naming metadata remains service-owned.
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
  - Bounded compiler commands retain private repository-root `.tmp/` logs, and in-memory behavior plus process liveness does not independently prove generated-counter relaunch persistence.
- **Plan-specific evidence**
  - The plan variant adds an implementation-plan request to the same workflow and requires successful saved add_plan, task addition through initial tasks or add_tasks, and update_tasks.
  - A task must be in_progress during a successful Swift source write/edit and later completed by an update, with a final nonempty fully completed plan matching client tasks.
  - IDs, titles, task count and overall tool order remain agent-selected, verifying implementation-time plan use rather than a final checklist or self-report.
- **Vision review and deadlines**
  - Local VisionCLI preparation/check-config precedes Create and only its executable is staged, never `.env`, with GEMINI_API_KEY overriding private `VisionCLI/.env` and AGENT_VISION_ENV_FILE selecting an alternate absolute private file.
  - One integrated pinned `gemini-3.8-flash` review of the last validated preview checks readable integer count, legible Increment/Decrement/Reset labels and no clipping/overlap, with uncertainty inconclusive and operational errors distinct from visual failures.
  - Assertions check request UUID/model/exact criteria, dimensions/SHA-256, aggregate verdict and exit code, without prescribing particular preview state or dimensions.
  - The reviewer uses a 120-second child deadline, bounded private temporary I/O/cancellation cleanup and CREATE_VISION logging, inside 1020-second case and 1320-second hosted bounds.
  - Only the reviewer contacts Google while the generated app remains offline, and accuracy calibration/negative-uncertain live coverage remain unverified.
- **Project retention**
  - Teardown stops Pi/development and removes only the UUID fixture project unless AGENT_CREATE_KEEP_PROJECT=1 retains it, leaving existing projects untouched.
  - Successful previews remain separately archived after project removal with CREATE_PREVIEW_RETAINED reporting their path.

## Create HTView

- `agentCreateHTViewScenario` requests a native viewer for one self-contained UTF-8 HTML file.
  - Inline CSS and JavaScript work offline.
  - The prompt still requests user-visible app branding and a main window title of exactly `HTView`.
  - Acceptance excludes rendered app-name and native-window-title checks.
  - Internal `ProductionApp` targets and HTML document titles are distinct from the requested branding and native title.
  - External assets, local servers, functional app-specific XPC and speculative features are outside the case.
  - One attempt means one normal Create request with tool-level repair allowed. It does not guarantee success or permit external retries.
- [HTView scenario folder](../Tests/AgentScenarioTests/HTView/README.md) owns the prompt, fixture, evidence audits, browser host and offline regressions.
  - It documents selectors, the public document-action contract, resource bounds and limitations.
  - All HTView-specific Swift files live in that folder without duplicate root test files.
- The production WorkspaceSession/native adapter/generated XPC and signed minimal Agent/DevTools host remain unchanged.
  - SDK preflight, selective credential-lifetime checks and existing deadlines precede submission.
  - Authored Test evidence must match final scoped edits and successful passed/exitCode-zero results.
  - Independent verification opens an owned missing file and valid fixture through the generated model and ApplicationRoot.
  - Generated navigation delegates, content rules, preprocessing and load/error lifecycle remain active.
  - Real SwiftPM resource processing and Bundle.module lookup are preserved.
  - Independent source staging uses physical repository-root `.tmp/` paths and rejects ancestor and leaf links.
  - Descriptor-derived module/file paths require component-anchored containment before declaration matching or copying.
  - Root-file and directory `.process`/`.copy` staging controls belong to the HTView folder.
  - Build/Run evidence, exact executable identity and post-verification development liveness remain separate requirements.
  - Naming relies on correct project plist, packaged bundle metadata and SwiftUI API wiring.
  - Run derives branding from the project plist. Scaffold v9 derives its default title from packaged bundle metadata.
  - SwiftUI content may override that default through `navigationTitle`.
  - Scene compiler probes, synthetic Bundle execution and CoreGraphics window observation are retired naming checks.
  - Acceptance has no naming-observation permission requirement.
  - Project-owned source-wiring, AppName and shared branding logic tests remain separate from rendered naming checks.
  - The accepted report `/private/tmp/mac-apper-htview-live.ugFtAO/report.md` predates naming assertions and remains historical evidence.
- `AGENT_CREATE_KEEP_PROJECT=1` retains review output after confirmed cleanup. Failed fixtures remain retained.
  - VisionCLI is not staged.
  - Development launch is not production delivery.
  - The actual user picker remains unverified.

Focused offline checks, with live gates unset:

```sh
"$swift64" test --package-path Agent --filter 'htViewHTMLFixture|htViewScenarioEvidence|htViewWebKitMalformedEvidenceOffline|htViewResource|htViewPromptAndObserver'
"$swift64" test --package-path Agent --filter htViewEmbeddedWebKitOfflineRegression
```

The native regression requires local Aqua/WebKit.
It runs private off-desktop, nonactivating hosts without Pi or remote calls.
Negative controls require actual execution receipts and reject the unsupported WebKit regex `^(https?|wss?|ftp|file):`.
The rewrite does not modify retained live-attempt artifacts or the app open for user review.
The retained resource-staging attempts remain failed.
They did not reach independent HTML/CSS/JavaScript verification.
The scenario-local staging correction needs fresh authorized runtime verification before claiming live recovery.
Retiring naming checks or correcting staging does not establish full Agent acceptance.
See the [retirement archive note](../../docs/verification-archive.md#naming-verification-retirement--2026-10-14).

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
