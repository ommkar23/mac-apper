# Runtime and session delivery

[Agent introduction](../README.md) · [Scaffold](scaffold.md) · [Scenarios](scenarios.md) · [Recorded evidence](evidence.md)

This document owns Agent runtime contracts. Provider-specific tool/rendering specifications belong to [DevTools](../../apps/built-in/dev-tools/README.md).

## Pi installation and authentication

Pi is a local runtime dependency for Chat/Create, not a prerequisite for compiling or packaging Mac Apper. Setup commands below are for the Mac owner to run with installation and authentication authorization. They are not offline documentation checks.

1. Install Pi using the [official quickstart](https://pi.dev/docs/latest/quickstart):

   ```sh
   curl -fsSL https://pi.dev/install.sh | sh
   ```

   Review the official installer before running it. It pins dependencies and can install Node.js when needed. Pi requires **Node.js 22.19 or newer**. Alternatively, with a supported Node.js and npm already installed, use:

   ```sh
   node --version
   npm --version
   npm install -g --ignore-scripts @earendil-works/pi-coding-agent
   ```

   Choose one installation method. The npm alternative does not pin transitive dependencies. No separate Codex CLI, MCP adapter package or `parallel-cli` is required. The product's authored MCP/codemode integration was verified against Pi 1.1.0; installing the current Pi release is not proof of product compatibility.

2. Open a new terminal if the installer changed your shell setup. Check local executable discovery without starting a session:

   ```sh
   command -v pi
   pi --version
   ```

   Agent checks its own PATH, `~/.local/bin/pi`, `/opt/homebrew/bin/pi`, `/usr/local/bin/pi`, then `~/.nvm/versions/node/*/bin/pi`. A successful shell lookup alone does not prove Finder/XPC discovery. Finder does not inherit your full shell environment. Keep Pi and its Node runtime installed in a location available to the service; do not change launchd's global environment to work around discovery.

3. For authenticated use, initialize [repository temporary storage](../../README.md#temporary-work) before starting Pi from this checkout. Review project resources before granting trust. Start Pi, run `/login`, and choose the provider for **`openai-codex`**. Complete its offered authentication flow. Do not submit a model prompt just to configure sign-in.

   ```sh
   # Disables configured MCP connections for this sign-in session.
   pi --no-mcp
   ```

   [Pi authentication guidance](https://pi.dev/docs/latest/providers) explains the interactive flow. Credentials normally live in `~/.pi/agent/auth.json`; keep them private and untracked. Sign in as the same macOS user that runs Mac Apper. Shell-only API-key exports are not reliable Finder configuration. An OpenAI API key for another provider is not evidence of access to `openai-codex`.

   Mac Apper explicitly selects `openai-codex/gpt-6.1-sol` with `medium` thinking. Changing Pi's interactive default does not change that selection. The `/model` picker can show authenticated availability without sending a task. If this model is unavailable to your account or Pi installation, stop and report the prerequisite; do not silently switch models. Installation/version checks do not verify account entitlement or a successful model request.

4. No additional Parallel installation or account is required for the default web configuration. The [authored extension](../Extensions/parallel-codemode.ts) supplies `https://search.parallel.ai/mcp` and exposes only `web_search` and `web_fetch` through codemode. Do not add a duplicate user/project MCP entry for normal product setup.

   [Parallel's current guidance](https://docs.parallel.ai/integrations/mcp/getting-started) documents anonymous access at this endpoint. It accepts optional Bearer credentials for higher limits but does not advertise OAuth. The distinct `/mcp-oauth` endpoint requires authentication; the product does not select it. Merely exporting `PARALLEL_API_KEY` does not attach a header to the authored configuration. Authenticated/higher-limit setup needs a separately reviewed configuration change, not an invented login step.

   [Pi MCP shell commands](https://pi.dev/docs/latest/mcp) do not load extension-defined servers. Therefore `pi mcp list` or `pi mcp login parallel` is not a product setup/verification shortcut. Endpoint discovery, auth refresh and actual search/fetch require separate live authorization, even for anonymous access. Anonymous availability and current rate limits have not been exercised by this documentation check.

## Service and client boundary

- AgentApplication owns storage and Pi; neither client target depends on that server core. Authored controllers route generated typed requests to service-owned managers.
- AgentMacosClientModel generates client records/calls separately and owns presentation/domain values. Domain events, journal batches and workspace operation enums remain target-local.
- WorkspaceSession holds in-memory presentation and forwards XPC operations; it persists no second conversation. WorkspacePresentation owns navigation/action validation, expansion state, rename drafts/errors and refresh lifecycle. Views retain layout, styling and native scrolling, not workflow state.
- WorkspaceHostActions is injected at the composition root; native AgentMacosHostActions implements app launching, optional external-editor opening, clipboard and log reveal. The editor is looked up only when its action is invoked. Test convenience initializers omit host integration.
- Generated workspace timestamps are seconds since Apple's 2001 reference date, not Unix seconds.
- The OpenXPC envelope uses UUID project/session IDs (zero for Chat or unnamed sessions); the service checks follow-up IDs against request and stored binding. Scope/identity checks are not peer authentication.
- The retired AgentXPC product/target, request/reply envelope, dynamic agent registry and pollSession are not current interfaces.

## Manifests and XPC services

- **Configuration and generation**
  - Custom `AppManifest.yaml` files declare package, bundle, service, Pi extensions, tools and availability to the two fixed agents, with integration generation rejecting other agent IDs.
  - Built-in DevTools has no AppManifest and derives products/tools from `OpenXPC.yaml`, `OpenXPCGen.yaml` and conventional bundle files, assigned to Create by integration generation.
  - AgentApplication selects the Pi configuration directly, while the client selects only Chat/Create without querying a dynamic preset catalog.
  - Chat selects no provider apps and only codemode, while Create selects DevTools/codemode plus scoped filesystem tools and authored hooks.
  - OpenXPCBuildPlugin generates controllers for AgentApplication/DevTools and client-only output for AgentMacosClientModel, declaring Swift/TypeScript outputs without executing the generator during planning.
  - Generated terminal implementations remain in SwiftPM plugin output and generated extensions are located with Bundle resource APIs rather than assumed flat paths.
  - AgentIntegrationCatalog resolves authored hooks from source Agent/Extensions or bundled Resources/AgentExtensions, including later/resumed requests except first-request-only naming guidance.
- **Agent boundary**
  - Agent's contract generates bounded presets, session requests, events/history and workspace snapshots, routed by authored controllers to service-owned sessions/workspaces without the retired AgentXPC target or envelope.
  - Separate `prepareChatSession`, `prepareCreateProject`, `prepareCreateSession` and `resumeSession` operations replace generic preparation, with lifecycle owned by the service.
  - The native client uses generated typed operations/subscriptions through AgentXPCService rather than a separate scenario or legacy transport.
- **DevTools boundary and packaging**
  - DevTools uses a generated controller-dispatching listener and sole Pi client, with an extension-injected project root validated on every call.
  - Preview compiles an authored SwiftUI factory in isolation and Run reports process launch without the former readiness handshake.
  - Provider apps are bundled under `Contents/Applications/DevTools.app` with their owned XPC service, generated client and Pi extensions.
  - Agent runtime resource bundles must be staged in the owning XPC service's `Contents/Resources` for `Bundle.module`, with the retained host copy insufficient on its own.
  - Parallel is reached through Pi's MCP extension rather than an app-owned Web service, and standalone Web source/packaging/live tests plus `parallel-cli` are retired without deleting historical artifacts.

## Tools and Parallel MCP

- **Tool exposure**
  - Extension tools are `codemode`, `set_app_name`, `plan`, `build`, `test`, `preview` and `run`. DevTools' generated terminal extension solely registers `set_app_name`, `build`, `test`, `run`, `preview` and `plan`.
  - Generated `set_app_name` accepts `name` plus an injected `projectRoot` and returns a summary and canonical name. It changes project naming metadata only. It does not build, package, sign, register or launch an app.
  - The provider naming tool remains available on first, later and resumed Create requests. Chat never selects it.
  - Create allows only `read`, `edit`, `write`, `grep`, `find`, `ls`, `codemode`, `set_app_name`, `build`, `test`, `preview`, `run` and `plan`, with shell tools disabled.
  - Chat exposes only codemode with Parallel MCP `web_search`/`web_fetch` and disables shell tools, skills, prompt templates and project context files.
- **MCP ownership**
  - `Agent/Extensions/parallel-codemode.ts` composes Pi 1.1.0 public codemode/MCP factories with fixed `https://search.parallel.ai/mcp`, hidden default exposure, exact search/fetch overrides and disabled model helpers.
  - Pi remains a Swift PiRPCProcess-owned CLI `--mode rpc` child rather than an SDK-hosted or replacement runtime.
  - Pi owns MCP discovery/authentication/calls and failure handling under inherited host configuration without a readiness, isolation, transport or retry redesign.
  - Session startup, endpoint discovery, authentication refresh and tool calls are not offline verification and require the [authorization boundary](verification.md#authorization).
  - Actual matched MCP child execution rather than normalized harness names or advertised schemas is necessary endpoint evidence, and no separate raw endpoint inventory/auth-mechanism probe is claimed.
- **Plan**
  - DevTools routes `add_plan`, `add_tasks`, `update_tasks`, `delete_tasks` and `get_tasks` through generated client/XPC to a project-scoped in-memory plan.
  - `add_plan` permits omitted initial tasks for an empty plan, but supplied tasks must be nonempty with unique valid IDs/statuses, at most 100 entries and at most one `in_progress` task.
  - Invalid creation is atomic and `add_plan` cannot replace an existing plan, with client task presentation updated from successful result snapshots rather than rejected start arguments.

## Create guidance

- [create-instructions.ts](../Extensions/create-instructions.ts) appends multiline system guidance through before_agent_start on every Create request, including later/resumed requests. Chat does not load it.
- Guidance requires offline-first Core Data, model-owned business/presentation/persistence, dumb views, preserved scaffold APIs and meaningful DevTools Test verification. Fix failures and rerun after changes; inspect passed/exitCode 0 rather than activity completion or transport success.
- Views must not use @Query, managed objects or NSManagedObjectContext or mutate records; bindings forward actions to models.
- [create-app.ts](../Extensions/create-app.ts) supplies first-request guidance to call `set_app_name` exactly once before implementation. The tool is generated by DevTools, not registered by Agent.
- [name-and-rename.ts](../Extensions/name-and-rename.ts) retains the `mac-apper-tools` and `mac-apper-rename` commands without registering tools. Native rename still validates branding, rebuilds, repackages, signs, verifies and registers the production app. It sends the existing `MAC_APPER_RENAMED` notification after success.
- Tool mechanics/examples belong in provider OpenXPC tool descriptions, not scenario feature prompts or hardcoded generator text.

## Workspace preparation

- Distinct prepareChatSession, prepareCreateProject and prepareCreateSession operations issue a bounded expiring service binding of agent/project/session/title/first-request intent. resumeSession validates existing Pi JSONL before issuing the binding.
- Successful starts consume bindings; failed starts can retry within their lifetime. Active sessions reattach without restarting Pi. SessionPreparationRegistry holds at most 256 pending entries with a 15-minute lifetime.
- Chat starts only in the real service-owned .chat directory; Create starts only in an existing nonlinked UUID project under the service root. Unknown agents/project-kind mismatches are rejected.
- Disconnected rename prepares a Create session through the service, never a client-chosen session pathname.
- Read requests reject missing/extraneous fields and create no workspace. isChatOnly describes a discovered workspace; it is not a creation mode. Listing/opening histories and validating resume create nothing.

## Agent session delivery and completion

- **Journals and handoff**
  - Pi persists conversation context separately from bounded strictly validated sequenced Agent presentation events under each project's `.pi/agent-events/`.
  - Journal recovery repairs only incomplete final writes and retains earlier events across disconnects and service restarts.
  - Clients subscribe, page history to the subscription cursor and consume pushed events in sequence without gaps or duplicates, without persisting another transcript or rewriting Pi history. History responses stay within the 64 KiB XPC payload bound.
  - LF-delimited Pi RPC records are bounded at 4 MiB, allowing one 2 MiB base64 PNG from other tools; Agent presentation events carry text/metadata only, and DevTools Preview itself returns no image content.
  - Closing or navigating away detaches without stopping Pi, explicit Stop may stop it, and `pollSession` is not exposed.
- **Pi RPC session completion**
  - PiRPCParser publishes `.settled` only for session-level `agent_settled`, never low-level `agent_end` regardless of willRetry.
  - Pi emits agent_end before retry/compaction/queued continuation and agent_settled from its finalizer including abort/exhausted retries, so client busy state survives intermediate endings while text/tool activity continues.
  - Pi owns recovery without an Agent legacy completion fallback, provider-specific WebSocket fix, retry/backoff policy or settings change.
  - Settlement means lifecycle completion rather than tool/workflow success, with existing abort/error presentation unchanged and live retry/abort/exhaustion recovery still unverified.
- **History limits and remaining coverage**
  - OpenXPC bounds each record/nested array to at most 128 entries, requiring mapping to page or reject larger workspace snapshots rather than truncate them.
  - Pi conversation loading rejects files over 16 MiB or combined message text over 4 MiB, with paged UI loading still needed.
  - Sessions predating the Agent journal have no retroactive tool/event replay, while current-session disconnect/replay and persisted resume do not establish service-restart replay coverage.
  - Active-session UI opening reads Pi history before subscribing, leaving snapshot/journal reconciliation for intervening deltas as a recorded limit.
- **Headless Chat**
  - AgentMacosClient `--chat` accepts one bounded JSONL stdin request with message and drives WorkspaceSession through normal AgentXPCRuntime/AgentXPCWorkspaceStore to completion before stopping the owned runtime.
  - Output includes reply, presentation status, scope paths and cleanup confirmation while preserving the conversation and leaving fixture cleanup to callers.
  - The native adapter discovers the bundled Agent identifier, including isolated disposable-host identities.

## Storage and user actions

- Projects: `~/.mac-apper/<project-uuid>/`; Pi conversations: project `.pi/sessions/`; Agent presentation journals: project `.pi/agent-events/<session-id>.jsonl`.
- Chat conversations/events use the corresponding directories under `~/.mac-apper/.chat/`. Pi filenames may include timestamps; do not assume a bare session UUID filename.
- Preview delivery: project `.mac-apper/Artifacts/<request-uuid>/render.png`. Retained review images: `~/.mac-apper/previews/<project-id>/<session-id>/preview-<Unix-microseconds>.png`, with no automatic pruning.
- Production bundles: `~/.mac-apper/output/<project-uuid>/<app-name>.app`. Valid bundles enable Launch App; Chat disables app launching and external-editor opening and creates no app scaffold.
- New App prepares only after the first message. Saved conversation opening/reattachment preserves files and Pi continuity; new conversation does not replace project files. Further messages steer Pi; Plan shows progress, Activity shows tools/diagnostics, and Stop is explicit cancellation.
- Preview images are not displayed in the workspace. Build/Run are development operations, not production packaging.
