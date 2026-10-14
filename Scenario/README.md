# Scenario

Scenario is a reusable macOS support library for package-local Swift tests. It provides named lifecycle execution, minimal signed test/XPC hosts, private homes, exact-owned process teardown and bounded compiler checks. It is not part of the product runtime.

## Start here

- [Hosting](Documentation/Hosting.md): lifecycle, declared inputs, signed hosts and filtered test execution.
- [Isolation and cleanup](Documentation/Isolation-and-cleanup.md): service homes, directory identity, process ownership and retention gates.
- [Compiler and SDK](Documentation/Compiler-and-sdk.md): standalone Swift selection, matching loader and explicit-SDK startup checks.
- [Verification](Documentation/Verification.md): package commands, test map and recorded evidence limits.
- [Repository overview](../README.md), [Agent](../Agent/README.md) and [DevTools](../apps/built-in/dev-tools/README.md): product behavior and consuming-package scenarios.

## Boundaries

- Scenario owns reusable lifecycle and temporary hosting; consuming tests own prompts, assertions, fixtures, deadlines, authorization and cleanup confirmation.
  - Agent cases use the production native adapter/generated client through `AgentMacosClientModel`, not a Scenario-specific transport.
  - Provider cases use their real generated client/service in a minimal signed host, not a full Mac Apper bundle.
- The root `Scenarios/`, standalone runner and Scenario command plugin are retired. Package-local filtered Swift tests are the supported entry points.
- Host `remove()` deletes owned packaging **without independently reaping XPC services**. Confirm exact-owned cleanup first; retain fixtures if confirmation fails.
- Isolation/path checks are not a sandbox. Tests, generated code and child processes run with the user's permissions.
- Repository policy remains in [conventions](../.pi/CONVENTIONS.yaml) and [guidance](../.pi/GUIDANCE.yaml); [learnings](../.pi/LEARNINGS.yaml) record history, not current commands.

## Setup

- Use macOS 14+, Command Line Tools with an installed SDK, standalone Swift 6.4.0 and default Swift Build; Xcode itself is not required.
- [Package.swift](Package.swift) exports only the `Scenario` library and `ScenarioTests`.
  - The library has no external target dependencies and imports Foundation/Darwin.
  - Tests use exact `swift-testing` 6.2.3. SwiftPM resolves dependencies automatically; no separate Testing installation or manual SwiftSyntax dependency is needed.
- Callers supply executables, plists and resources. Signing uses installed `codesign`; Scenario does not install tools, discover product fixtures or authorize credential/live operations.

## Temporary storage

- [ProjectTemporaryDirectory](Sources/Scenario/ProjectTemporaryDirectory.swift) allocates disposable work beneath the repository-root `.tmp/`.
- The default repository root comes from the compiled support source location, not the hosted process working directory or isolated HOME.
- A missing root is created with mode 0700. Links, non-directory entries, foreign ownership and public permissions fail closed.
- Isolated homes, host staging, SDK probes and command logs use this root. Child commands and staged XPC services receive its `TMPDIR` before startup.
- Production storage is unchanged. Temporary retention does not make review apps or reports durable.
- Follow the [temporary-work and manual-cleanup contract](../README.md#temporary-work). The library removes only its exact owned fixtures after existing cleanup gates permit it.

## Practical usage

- Add a local SwiftPM dependency pointing to this directory and `.product(name: "Scenario", package: "Scenario")` to the consuming test target, then `import Scenario`.
- A small in-process lifecycle example, based on the [library tests](Tests/ScenarioTests/ScenarioTests.swift):

```swift
import Scenario
import Testing

@MainActor final class Shared: CollectionContext {
    var events: [String] = []
}
@MainActor final class Local: CaseContext {
    let shared: Shared
    init(_ shared: Shared) { self.shared = shared }
}

@Test @MainActor func exampleScenario() async throws {
    let shared = Shared()
    let registry = try ScenarioRegistry([
        ScenarioCollection(
            "example", context: { shared },
            teardown: { $0.events.append("collection cleanup") },
            cases: [
                ScenarioCase(
                    "example-case", context: Local.init,
                    steps: [Step("record") { $0.shared.events.append("step") }],
                    teardown: { $0.shared.events.append("case cleanup") })
            ])
    ])
    try await registry.runCase("example-case")
    #expect(shared.events == ["step", "case cleanup", "collection cleanup"])
}
```

- For XPC integration, choose a [host](Documentation/Hosting.md#choose-a-host), declare only required inputs, scope homes before signing/startup, run the selected entry point and gate removal on [confirmed cleanup](Documentation/Isolation-and-cleanup.md#cleanup-order).
- Use [scenario-write](../.pi/skills/scenario-write/SKILL.md) for test authoring and [scenario-run](../.pi/skills/scenario-run/SKILL.md) for authorized selection/monitoring. Live opt-ins, Agent prompts and provider assertions belong in their module guides rather than here.

## Build and verify

From the repository root, when execution is authorized:

```sh
swift64="$HOME/Library/Developer/Toolchains/swift-6.4.0-RELEASE.xctoolchain/usr/bin/swift"
"$swift64" build --package-path Scenario
"$swift64" test --package-path Scenario
```

- These commands build the library or run its own tests, not consuming live collections. Library tests can stage signed hosts and execute child/compiler processes.
- See [verification scope and evidence](Documentation/Verification.md). This documentation rewrite performed static inspection only; it ran no builds, package tests, hosts, credentials or live calls.
