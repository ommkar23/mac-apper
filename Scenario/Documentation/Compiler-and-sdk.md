# Compiler and SDK selection

[Scenario introduction](../README.md) · [Hosting](Hosting.md) · [Verification](Verification.md)

## Standalone toolchain

- [SwiftToolchain.executable](../Sources/Scenario/SwiftToolchain.swift) accepts only `swift` or `swiftc` and requires an executable at:

```text
~/Library/Developer/Toolchains/swift-6.4.0-RELEASE.xctoolchain/usr/bin/<tool>
```

- Use the explicit driver with default Swift Build, not deprecated `--build-system native`. Pinned test-only `swift-testing` remains 6.2.3 rather than being matched to the compiler number.
- The recorded installation uses Command Line Tools SDK macOS 26.2 without Xcode. `xcrun` still selecting CLT Swift 6.2.3 and stale inherited PATH/toolchain selectors are not evidence that standalone Swift 6.4 was invoked.
- `PackagedTestHost.swiftPMTestLoader()` selects and validates `usr/libexec/swift/pm/swiftpm-testing-helper` from that same standalone toolchain. Do not substitute an unrelated loader for the staged test bundle.
- Selection is home-relative; [isolated homes](Isolation-and-cleanup.md#home-isolation) may link only the installed toolchain so service/child selection still works without borrowing user configuration.

## Preparation routing

- [PackagedTestHost.runPreparation](../Sources/Scenario/PackagedTestHost.swift) redirects **only** `/usr/bin/xcrun` calls whose first argument is `swift` or `swiftc`.
  - It invokes the selected standalone executable, drops that first tool argument and pins `SWIFT_EXEC` to standalone `swiftc`.
  - Other executable/argument combinations preserve the inherited environment and do not resolve Swift or override `SWIFT_EXEC`.
  - Preparation is bounded to 600 seconds with 64 KiB returned combined output. Nonzero status throws with a diagnostic tail; it is not a successful prerequisite.
- Injected tools and non-Swift preparation remain their callers' responsibility. This routing does not change product compiler policy or provide generic JSONL output; ordinary compiler commands must not use `XPCClientAdapter`.

## Explicit SDK probes

- [SDKCompiler.resolve](../Sources/Scenario/SDKCompiler.swift) runs bounded system discovery:

```sh
/usr/bin/xcrun --sdk macosx --show-sdk-path
```

- Discovery is limited to ten seconds and requires one absolute path. It resolves the installed system SDK alias and verifies a directory, `SDKSettings.json` and `usr/include/sys/types.h` before selecting standalone `swiftc`.
  - The SDK version is not hardcoded. Missing/invalid discovery fails with Command Line Tools selection guidance, not a fallback compiler or an Xcode requirement.
  - `SDKROOT` is removed only from these child command environments; the discovered SDK is supplied explicitly through `-sdk`.
- `arguments(_:scratch:)` invokes one frontend with `-enable-objc-interop`, the explicit SDK and a module cache within caller-owned scratch. These compile/import probes need no driver/link jobs or external macro expansion.
- `run(_:scratch:environment:)` limits compiler commands to 30 seconds and 1 MiB output; cancellation/overflow/timeout throws. The command helper kills an active owned child if needed, waits for exit and removes its UUID-private command scratch.
  - Callers own scratch passed to `run`/`requireImport`; the API does not remove an arbitrary supplied directory.
  - `preflight` owns a separate 0700 UUID directory beneath repository-root `.tmp/` and removes it on exit. `requireImport` writes/removes an import source within supplied scratch.

## Gate startup on usable imports

- `preflight` compiles a small module importing Foundation, Darwin, os, CoreData and Observation, then typechecks its transitive import using the same configuration. It prints a bounded outcome/timing/SDK line and throws on failure.
- `beforeStartup(preflight:start:)` executes startup only after preflight succeeds. For consuming live cases, place the gate before creating the Pi submission task, not after paying for generation.
- Use `requireImport(module:searchPath:scratch:environment:)` to separately check the actual built module. A framework/setup/import failure must not be reported as unsupported generated APIs or behavioral-test evidence.
- Compiler/import success is setup evidence, not a test pass, app behavior, UI fidelity, persistence or model compliance. Product-specific count-layout probes/assertions and paid deadlines belong in the [Agent guide](../../Agent/README.md).
- [SDKCompilerTests](../Tests/ScenarioTests/SDKCompilerTests.swift) covers unavailable discovery, unset/misleading SDKROOT, actual compile/import failures, startup blocking and owned scratch removal. Recorded earlier packaged passes do not retroactively verify later preflight fixes.
