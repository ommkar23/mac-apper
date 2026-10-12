# Clean tests and scratch safety

Return to the [tooling introduction](README.md). Clean-test is an optional fresh-build diagnostic command, not routine cleanup or an independent package test runner.

## Plugin entry point

- Initialize `swift64` from the [setup](README.md#setup-and-quick-commands), then run from the repository root when test execution is authorized.

```sh
# PACKAGE is one of: .  Agent  Scenario  apps/built-in/dev-tools
"$swift64" package --disable-sandbox plugin clean-test PACKAGE

# Optional single SwiftPM test filter.
"$swift64" package --disable-sandbox plugin clean-test Scenario --filter sdkCompiler
```

- Replace `PACKAGE` with a listed package. The plugin accepts exactly one package argument or that argument followed by `--filter PATTERN`; it does not forward arbitrary SwiftPM flags.
- [CleanTestPlugin](CleanTestPlugin/plugin.swift) invokes the installed standalone Swift 6.4.0 driver with `SWIFT_EXEC` pinned to its compiler, `test --package-path`, private `--scratch-path` and `-j 2`.
- It creates a new UUID-named `/private/tmp/mac-apper-test.<UUID>` directory with mode 0700 and attempts to remove that exact scratch in a deferred cleanup on normal completion or thrown failure.
  - Forced termination can prevent deferred cleanup; removal errors are ignored by the implementation. Do not claim unconditional scratch deletion.
  - It neither clears retained package `.build` directories nor deletes historical evidence, projects, sessions or unrelated scratch.
  - Nonzero/abnormal test termination fails the plugin. A filter can still select zero tests; confirm actual selected-test execution rather than treating exit 0 alone as coverage.

## Package ownership

- Root `swift test` covers only the root package. Underlying behavior changes require focused tests and each affected package's own suite per [guidance](../.pi/GUIDANCE.yaml).
- VisionCLI and OpenXPCGenerator are not accepted by clean-test. Use their direct package entry points with validated manual scratch if fresh-build verification is needed.
- Direct commands, when authorized:

```sh
"$swift64" test
"$swift64" test --package-path OpenXPCGenerator
"$swift64" test --package-path Agent
"$swift64" test --package-path Scenario
"$swift64" test --package-path apps/built-in/dev-tools
"$swift64" test --package-path VisionCLI
```

- Root plugin tests live under [SwiftLinesPluginTests](SwiftLinesPluginTests/); bundle/integration assertions live under [Tests/IntegrationTests](../Tests/IntegrationTests/).
- Agent has opt-in live cases alongside offline tests; package-local scenario selection and authorization belong to [Agent](../Agent/README.md), [DevTools](../apps/built-in/dev-tools/README.md), [Scenario](../Scenario/README.md) and the [scenario-run skill](../.pi/skills/scenario-run/SKILL.md).
  - Do not enable live gates as part of fresh-build diagnostics. Inherited opt-ins can change the work a suite performs.
  - Scenario-only changes use selected cases rather than unrelated unit suites; packaging stays in Scenario, not a restored root scenario plugin or full-product bundle.
- [VisionCLI](../VisionCLI/README.md) owns its offline/live review boundaries. These commands do not authorize model/MCP/Gemini calls or credential operations.

## Manual retained scratch

- Use manual scratch when another package, custom flags or retained build diagnostics are needed.
- Validate a nonempty private path before giving it to SwiftPM. An empty scratch path can cause artifacts to land at the repository root.

```sh
scratch=$(mktemp -d /private/tmp/mac-apper-test.XXXXXX)
test -n "$scratch" && test -d "$scratch" || exit 1
# Replace PACKAGE with the authorized package path.
"$swift64" test --package-path PACKAGE --scratch-path "$scratch"
# After owned work exits, remove only this exact validated directory,
# or retain it for the task's diagnostics. Do not sweep unrelated /tmp or dist.
```

- Artifact retention and deletion authority remain owned by [conventions](../.pi/CONVENTIONS.yaml) and [guidance](../.pi/GUIDANCE.yaml), not implied by this example.
- Keep test diagnostics external to reusable `dist/<bundle-id>/` output; do not append to `dist/evidence/`.

## Evidence limits

- Learnings records stale removed-plugin/schema plans and SwiftSyntax/Testing linker failures recovered through private scratch. Those observations explain the optional command; they do not prescribe cache deletion or promote old workaround commands to current instructions.
- Source inspection checked the allowlist, argument shape, compiler path and scratch ownership during this rewrite. No clean-test, direct tests, scenario or build was executed; scratch cleanup and runtime success were not newly verified.
