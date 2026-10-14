# Mac Apper

Mac Apper is a native macOS app for building SwiftUI apps. It uses the local Pi CLI. Development tools run through native XPC services. It does not require containers, an HTTP application backend, or Xcode.

Mac Apper ships with two agents: **Chat** and **Create**. Chat is a general-purpose agent with web search. Create extends Chat with the DevTools app. It uses DevTools to build macOS apps.

## Requirements

- macOS 14+, Apple Command Line Tools with an installed macOS SDK and Git, and standalone **Swift 6.4.0**.
  - Xcode itself is not required.
  - Invoke the standalone driver explicitly: `xcrun swift` or an inherited PATH can still select CLT Swift 6.2.3. Use default Swift Build, not `--build-system native`; swift-testing remains pinned to 6.2.3.
- A local authenticated Pi CLI for Chat/Create; the deployed Agent selects `openai-codex/gpt-6.1-sol` with medium thinking. Parallel access is needed for web tools.
  - Pi discovery checks PATH, `~/.local/bin`, Homebrew and installed NVM Node versions. Finder does not inherit the full shell environment.
- Zed for **Open in Zed**. Optional screenshot review uses the separate [VisionCLI](VisionCLI/README.md), not a product dependency.

## Temporary work

- Use the gitignored repository-root `.tmp/` for disposable scratch, test fixtures, scenario homes, logs and reports.
- It is not durable storage. Retained review apps and scenario evidence there are temporary too.
- Keep authored source, reusable `dist/` outputs, production projects and persistent user data outside `.tmp/`.
- Scenario and test helpers create private UUID-scoped paths there. They never fall back to system temp when the root is unsafe.
- Export `TMPDIR` before starting developer commands or a new Pi session. This also directs inherited tool temporary work there.

```sh
# From the physical repository root. Do not use a linked .tmp directory.
mkdir -p .tmp && chmod 700 .tmp
export TMPDIR="$(pwd -P)/.tmp/"
# Start pi here if it should inherit this setting.
```

- You may clear its contents periodically when quitting Pi. First finish builds, tests, scenario cleanup and any review apps using those files.
- Credential staging still requires prompt scrubbing and confirmed process cleanup. Session-quit deletion is not a substitute.
- No automatic directory-wide purge runs on exit. Existing system-temp artifacts and historical report locations are not migrated or deleted.

## Build and run

From the project root, when authorized:

```sh
swift64="$HOME/Library/Developer/Toolchains/swift-6.4.0-RELEASE.xctoolchain/usr/bin/swift"
"$swift64" package --disable-sandbox bundle app
```

- Output: `dist/com.ommkar.mac-apper/Mac Apper.app`, including Agent XPC and the built-in DevTools app/service/client/extensions.
- Bundle builds, assembles, signs and verifies the app. `MAC_APPER_SIGNING_IDENTITY` selects an identity; otherwise signing is ad hoc. Quit older instances before rebuilding; in-use owned output is rejected.
- To open the app in an authorized normal-use environment:

  ```sh
  open 'dist/com.ommkar.mac-apper/Mac Apper.app'
  ```

  - GUI verification must first satisfy the service-home isolation boundary below; a client HOME override alone is insufficient. This quick start does not authorize a launch or paid workflow.
- Packaging, signing/resource layout, unbundle and code-quality commands belong to [Plugins](Plugins/README.md).

## Usage and storage

- **Create:** select New App, describe it and submit with Command-Return. Projects/sessions are created after the first message. Further messages steer work; Plan expands task progress and Activity shows tool details/diagnostics.
- **Chat:** use the separate chat-only workspace; it creates no app scaffold and disables Launch App/Open in Zed.
- **Navigate:** the sidebar opens apps and saved conversations, attaching to active sessions without restarting Pi. Navigation/closing detaches; use Stop when work should end. The pencil beside a built app renames/repackages it; the pencil-in-square starts another conversation in the selected workspace.
- **Host actions:** Open in Zed opens the project directory; Launch App opens a valid production bundle. Development Build/Run does not itself create a production bundle. Preview images are not displayed in the workspace.
- **Local storage:**
  - Projects: `~/.mac-apper/<project-uuid>/`; Pi conversations: project `.pi/sessions/`; separate Agent events: `.pi/agent-events/<session-id>.jsonl`.
  - Chat: `~/.mac-apper/.chat/`, with the same conversation/event subdirectories.
  - Production bundles: `~/.mac-apper/output/<project-uuid>/<app-name>.app`.
  - Preview artifacts: project `.mac-apper/Artifacts/<request-uuid>/render.png`; retained previews: `~/.mac-apper/previews/<project-id>/<session-id>/preview-<Unix-microseconds>.png`, without automatic pruning.
  - Generated-app Core Data: `~/Library/Application Support/MacApperGenerated/<lowercase-app-uuid>/CoreData/data.sqlite`, independent of project/display name. Project removal does not authorize deleting stored data.
- Conversation loading is bounded (16 MiB files, 4 MiB combined message text). Older sessions have no retroactive Agent tool journal; active history snapshot reconciliation and service-restart replay coverage remain limited. See [Agent](Agent/README.md).

## Architecture and modules

The native client owns presentation; Agent owns workspaces, Pi RPC and durable events. Typed generated XPC separates clients from services; provider filesystem validation and process ownership remain service behavior, not generator policy.

- [Agent](Agent/README.md): native UI/client model, Agent XPC, Pi sessions, workspace/scaffold and Agent scenario runbooks.
- [DevTools](apps/built-in/dev-tools/README.md): scoped Build, Test, Run, Preview and Plan service plus generated Pi client.
- [OpenXPCGenerator](OpenXPCGenerator/README.md): strict contracts and self-contained generated service/client/tool code.
- [Scenario](Scenario/README.md): reusable minimal signed hosts, isolated homes, process/compiler safety primitives.
- [Plugins](Plugins/README.md): root-package bundle, formatting/lint, clean-test and source-line commands.
- [VisionCLI](VisionCLI/README.md): optional bounded screenshot review, separate from app runtime.

- `Bundles/` and `Scripts/` supply root app metadata, integration generation and provider packaging; `apps/custom/` holds custom provider manifests.
- Root `Package.swift` owns integration/tooling tests, not all module suites. Package-local tests own scenario prompts/assertions; Scenario owns reusable packaging/hosting. Root `Scenarios/`, standalone runner and Scenario command plugin are retired.
- Detailed contracts, bounds and scenario selections belong to the owning module guides above, not competing root specifications.

## Security and authorization

- Pi, generated apps and compiled generated tests run with the user's permissions. Tool restrictions, scoped IDs, path checks and XPC are **not a sandbox or peer authentication**. Review generated code before trusting or distributing it.
- Keep traversal/link checks, strict decoding, size bounds, private logs and exact-owned cleanup intact; the global safety policy is [.pi/GUIDANCE.yaml](.pi/GUIDANCE.yaml).
- Starting Pi with remote MCP, discovering endpoints, refreshing authentication or making Parallel/model/Gemini calls requires explicit research/live-verification authorization; credentials or opt-in flags alone are not permission.
- VisionCLI uploads the selected screenshot/criteria to Google. Its probabilistic verdict is not behavioral, UI-interaction or process evidence.
- Original-product GUI verification needs approved **Agent XPC service-home isolation before automatic workspace reads**. Client HOME overrides do not establish launchd service isolation; do not change global configuration or hand-edit signed artifacts to bypass it.
- Scenario cleanup coverage is case-specific: DevTools Preview explicitly reaps exact service identity before host removal; current Plan/Test call `host.remove()` directly, and the toolchain fixture uses best-effort removal after development-child ESRCH. This source-inspected limit is not a new leak/test failure or authorization for repair; see [DevTools verification](apps/built-in/dev-tools/README.md).
- Historical failed-run cleanup needs separate exact-owned safety authorization. Later passing fixtures do not resolve retained processes/credential snapshots; see the [unresolved historical safety failure](docs/verification-archive.md#unresolved-historical-safety-failure).

## Package tests

Initialize `swift64` and export `TMPDIR` as above; select only authorized checks. Root tests do not run all packages:

```sh
"$swift64" test
"$swift64" test --package-path Agent
"$swift64" test --package-path Scenario
"$swift64" test --package-path apps/built-in/dev-tools
"$swift64" test --package-path OpenXPCGenerator
"$swift64" test --package-path VisionCLI
```

- Underlying behavior changes start with a focused failing test and require affected package suites. Scenario-only changes use selected cases; no unrelated unit sweep is required.
- Package suites can compile/run fixtures, stage signed hosts and launch owned subprocesses; they are not read-only documentation checks. Agent live/resource/scaffold cases have separate gates; unset gates mean skipped, not passed.
- Scenario selection, prerequisites and authorization: [Agent](Agent/README.md), [DevTools](apps/built-in/dev-tools/README.md), [Scenario](Scenario/README.md), [scenario-run](.pi/skills/scenario-run/SKILL.md) and [scenario-write](.pi/skills/scenario-write/SKILL.md).
- Optional fresh-build diagnostics use Plugins' [clean-test guidance](Plugins/README.md). Manual scratch must be nonempty, private and validated before SwiftPM use; remove only the exact owned scratch after work exits, never historical artifacts.

## Troubleshooting

- **Wrong compiler:** use the explicit standalone Swift path, not `xcrun swift`; SDK discovery still uses CLT `xcrun`. See [DevTools](apps/built-in/dev-tools/README.md) and [Scenario](Scenario/README.md) for runtime/preparation routing.
- **Missing Pi:** check local executable discovery and configured authentication. A remote/auth-refresh probe is not an offline check.
- **Stale extensions or cached SwiftPM paths:** quit/rebuild only when authorized; use package-local clean scratch rather than deleting unrelated build/evidence directories. See [Plugins](Plugins/README.md).
- **Missing conversations:** inspect the scoped project's `.pi/sessions/`; invalid histories are skipped and unsent drafts are not saved.
- **Tool failure:** inspect Activity and typed result status. Transport success, settlement or a completed activity row does not prove Test/Preview/Build/Run success; consult [DevTools](apps/built-in/dev-tools/README.md).
