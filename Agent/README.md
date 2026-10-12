# Agent

Agent is Mac Apper's service-owned workspace/Pi runtime and native macOS client. Chat provides conversation and Parallel MCP search/fetch; Create prepares a trusted Swift package and uses DevTools to implement, test, preview and launch it.

## Start here

- Read the [root overview](../README.md) for product requirements and repository setup.
- Use macOS 14+, Apple Command Line Tools/SDK and Git, standalone Swift 6.4.0, and a local authenticated Pi CLI. Xcode is not required; Zed supports the native Open in Zed action.
- Pi discovery checks PATH, `~/.local/bin`, Homebrew and installed NVM Node versions. Finder does not inherit the full shell environment.
- Both agents are configured for `openai-codex/gpt-6.1-sol` with `medium` thinking. Starting Pi/MCP or making model, Parallel or Gemini calls requires explicit live authorization; credential availability is not authorization.
- This is the sole human-facing module README. Detailed specifications belong in the topic documents below, not a parallel YAML README.

## Ownership

- **Service — AgentApplication**
  - Owns project/session preparation, workspace reads, Pi RPC children, journals and subscriptions. Its `@main @MainActor` entry point is [AgentApplicationMain.swift](Sources/Application/AgentApplicationMain.swift).
  - [OpenXPC.yaml](OpenXPC.yaml) defines typed operations/records/subscriptions; [OpenXPCGen.yaml](OpenXPCGen.yaml) generates the listener and client-only model output.
- **Client model — AgentMacosClientModel**
  - Owns domain values, WorkspaceSession, AppModel, workspace/session adapters and presentation/actions. It does not import the service core or run Pi.
  - Generated task records are status-checked and presented directly, without a duplicate client task-plan type.
- **Native executable — AgentMacosClient**
  - [AgentMacosClientMain.swift](Sources/MacOSClient/AgentMacosClientMain.swift) injects the single production [AgentServiceXPCAdapter](Sources/MacOSClient/AgentServiceXPCAdapter.swift) and native host actions; views render client state.
  - Host actions launch production apps, open Zed, copy diagnostics and reveal logs. No separate scenario transport or legacy authored XPC wrapper is introduced.
- **Authored resources**
  - [Extensions/](Extensions/) owns MCP/codemode and Create hooks; [Resources/](Resources/) owns bundle plists. [Package.swift](Package.swift) owns targets, dependencies and tests.
  - Generated code stays in SwiftPM plugin output; release catalogs/extensions stay in the owning dist build directory. Service-local runtime resources are required in addition to the retained host copy.

## Topic navigation

- [Runtime and session delivery](docs/runtime.md): service/client boundary, Pi/MCP tools, preparation, replay, completion, storage and limits.
- [Scaffold and persistence](docs/scaffold.md): version 8, editable/protected files, model-view ownership, Core Data and preview integration.
- [Verification commands](docs/verification.md): standalone compiler setup, package test targets, no-model resource/scaffold entry points and authorization boundaries.
- [Chat and Create scenarios](docs/scenarios.md): signed production-path hosting, selectors, evidence, isolation, cleanup and deadlines.
- [Recorded evidence and unresolved limits](docs/evidence.md): dated checkpoints and historical failures, explicitly separate from rewrite checks.
- Related modules: [Scenario](../Scenario/README.md), [DevTools](../apps/built-in/dev-tools/README.md), [Plugins](../Plugins/README.md), [VisionCLI](../VisionCLI/README.md).

## Verification boundaries

- Normal Agent tests skip live cases unless opted in; root tests do not replace the Agent package suite.
- Commands are documented for separately authorized use. This documentation rewrite performs only filesystem/source/link/command inspection, not tests, builds, bundling, GUI, credential operations or live calls.
- Pi, generated apps and generated tests execute with user permissions. Project scoping and tool restrictions are not a sandbox.
- The removed YAML README is still named by `Tests/AgentApplicationTests/AgentArchitectureTests.swift:37`; changing that source test is outside this documentation-only scope and requires coordinator follow-up.
