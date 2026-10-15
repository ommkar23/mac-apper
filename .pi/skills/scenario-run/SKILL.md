---
name: scenario-run
description: Run and monitor Mac Apper package-local Swift XPC scenario cases, collections, or sequential combinations through swift test with supplied Swift helpers.
---

# Run and monitor scenarios

## Scope and prerequisites

- Read project-root `AGENTS.md`, `README.md`, `.pi/CONVENTIONS.yaml`, `.pi/GUIDANCE.yaml`, and relevant `.pi/LEARNINGS.yaml` entries; then read [Scenario](../../../Scenario/README.md) and the selected case owner's [Agent](../../../Agent/README.md) or [DevTools](../../../apps/built-in/dev-tools/README.md) guide.
- Use `../scenario-write/SKILL.md` for writing or changing tests; this skill covers execution and evidence only.
- Package-local `swift test` is the scenario entry point; the scripts here only launch/monitor that command, never implement cases, XPC transport, hosting, or cleanup.
- Root Scenarios/, ScenarioRunner, ScenarioPlugin and scenario bundles remain retired.
- Explicit user authorization is required before Pi startup/MCP connection, remote probes, auth refresh, model or Gemini calls; a command-line flag or credentials alone do not grant it.
- Record the authorized cases/collections and attempt counts before startup; a paid retry needs renewed authorization.
- Use standalone Swift 6.4 explicitly with default Swift Build and pinned Testing; xcrun discovers the installed CLT SDK, not the production compiler.
- No full Mac Apper.app is needed to run scenarios; the tests stage signed minimal hosts through Scenario/.

## Supported selections

- Agent Chat: `Agent`, filter `agentChatScenarios`, optional `AGENT_SCENARIO_CASE` for one of its eight cases; omission runs the collection sequentially.
- Agent Create: `Agent`, filters `agentCreateCounterScenario`, `agentCreatePlanScenario`, or `agentCreateHTViewScenario`.
  - Each filter selects a separate one-case test.
  - Counter and plan use Pi and Gemini.
  - HTView uses Pi without a Gemini review.
  - Use direct `swift test` with `AGENT_CREATE_KEEP_PROJECT=1` when retaining Create output for user review.
  - The launch helper clears that retention override.
- Agent no-model resource: `Agent`, filter `agentBundledResourceScenario`, gate `AGENT_RESOURCE_SCENARIO=1`.
- Agent no-model scaffold/DevTools: `Agent`, filter `agentScaffoldDevToolsScenario`, gate `AGENT_SCAFFOLD_DEVTOOLS_SCENARIO=1`; build DevTools products first as documented in Agent/README.md.
- DevTools: `apps/built-in/dev-tools`, filters `devToolsPlanScenarios`, `devToolsTestScenarios`, `devToolsPreviewScenarios`, `devToolsSetAppNameScenarios`; optional `DEV_TOOLS_SCENARIO_CASE` selects one case, omission runs that collection.
  - Naming cases are `set-app-name-canonical` and `set-app-name-rejections`; they verify scoped metadata through signed generated-client XPC without Pi, build, packaging or app launch.
- DevTools standalone Build/Run: filter `devToolsToolchainBuildRunScenario`, no case selector.
- Arbitrary supported combinations use separate sequential selections in a plan, not a broad Swift test regex that may run cases concurrently.
- Current names, prerequisites and environment overrides belong to Agent/README.md, apps/built-in/dev-tools/README.md and the owning Swift test sources; recorded historical evidence is indexed in docs/verification-archive.md. Update the helper allowlist when entry points change.

## Supplied Swift launch/status helper

Resolve `scripts/scenario-run.swift` against this skill directory; commands below assume project-root cwd.

```sh
swift64="$HOME/Library/Developer/Toolchains/swift-6.4.0-RELEASE.xctoolchain/usr/bin/swift"
helper="$PWD/.pi/skills/scenario-run/scripts/scenario-run.swift"
"$swift64" "$helper" check /absolute/private/plan.json
"$swift64" "$helper" start /absolute/private/plan.json
"$swift64" "$helper" status "$PWD/.tmp/scenario-run-EXACT-RETURNED-ID"
```

- `check` validates the complete plan and prints selected `swift test` commands without executing tests.
- Use repository-root `.tmp/` for all disposable plans/logs/fixtures and export its `TMPDIR` before direct developer commands. Follow README.md#temporary-work; keep durable outputs elsewhere and do not purge active fixtures.
- `start` creates one private evidence directory beneath the plan root `.tmp/` and returns its exact `RUN_DIRECTORY` promptly; the child Swift supervisor invokes `swift test` sequentially, with no shell evaluation.
- Live plans require `--authorize-live` on check/start, supplied only after explicit user approval.
- The worker has an exclusive start marker; an existing run cannot be restarted through it.
- The first nonzero command exit stops the plan; there are no retries or subsequent selections after failure.
- Inherited scenario gates, selectors, product/home overrides and SDKROOT are cleared; only gates/selectors derived from each selection are applied.
- Ordinary credentials remain inherited but are not serialized or printed; optional credential/product/read-module overrides need deliberate documented direct `swift test` invocation rather than silently borrowing ambient overrides.
- This is a developer-session helper, not a new Scenario package executable/plugin or product runner.
- The helper does not build missing prerequisite products, run auth probes, claim unified collection preflight, scan temporary directories, signal service/Pi processes, or delete scenario fixtures.

A plan contains exactly `root` and `entries`; entries contain `package`, `filter`, and optional `caseName`.

```json
{
  "root": "/Users/ommkar/dev/mac-sde/mac-apper",
  "entries": [
    {"package": "apps/built-in/dev-tools", "filter": "devToolsPreviewScenarios", "caseName": "preview-path-content"},
    {"package": "apps/built-in/dev-tools", "filter": "devToolsPlanScenarios"}
  ]
}
```

- One entry selects a single case or collection; several entries select any supported sequential combination.
- One live counter uses `{"package":"Agent","filter":"agentCreateCounterScenario"}` and `--authorize-live`.
- Multiple selections can contain both no-model and authorized live entries, but whole-collection authorization covers every contained case.
- Custom shell commands, arbitrary environment dictionaries, unrelated test filters and duplicate selections are rejected.

## Monitoring and evidence

- Poll `status` with short tool calls every 15–30 seconds and provide user-visible phase/elapsed-time updates at meaningful transitions or roughly once a minute.
- `status --tail` reads at most 4096 log bytes from this exact run; review sensitive logs locally and report metadata/failure summaries rather than dumping generated content.
- Never invent Python process-scanning scripts or choose ownership by timestamp, PID alone, process name, wildcard home directory or mutable argv.
- The recorded state is not a liveness guarantee; an old state without a final result needs read-only inspection of this exact supervisor/test and supervisor.log, not another launch.
- Process IDs in helper state are diagnostic only, not authority for signaling; immutable kernel path/PID/start identities belong to Scenario/test cleanup.
- Compiler startup and hosted output buffering can delay visible progress; absence of log output alone does not prove a stall.
- Respect existing bounded case/host deadlines and cleanup outside canceled bodies; a short monitor timeout must never kill the scenario or trigger a retry.
- Avoid one opaque 1800-second tool wait; external interruption can prevent cleanup and must be reported rather than hidden by deleting fixtures.
- Read per-selection `.result.json`, selected-test started/passed/failed markers and cleanup confirmation; exit 0/zero tests/skipped tests do not establish a case pass.
- A collection log must identify each requested case outcome; one aggregate command result cannot invent individual passes.
- Package tests own exact service/Pi/development reaping and retention; successful inner cleanup precedes outer host/home removal, and staged credentials are scrubbed.
- Preview returns PNG paths/metadata, not automatic images; reviewPath is descriptor-derived canonical and read is optional, while Create's independent VisionCLI review remains a separate check.
- Create's built-in SDK compile/transitive-import gate runs before submission; current shared preflight is not a unified once-per-collection design.
- Report PASS/FAIL/BLOCKED/NOT RUN separately, exact command/duration/checks reached, cleanup, private evidence paths and unverified paths; update project documents with actual verified outcomes without rewriting history.

## Helper verification (no scenarios)

```sh
node --test .pi/tests/scenario-run.test.mjs
```

These local tests exercise validation/dry-run/start refusal only; they do not start Pi or scenario cases.
