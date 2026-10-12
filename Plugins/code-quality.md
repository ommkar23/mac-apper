# Formatting and lint tooling

Return to the [tooling introduction](README.md). This guide documents tool invocation and coverage, not a second formatting policy.

- [Conventions](../.pi/CONVENTIONS.yaml) owns changed-file and guard/layout rules.
- [.swift-format](../.swift-format) owns swift-format settings (tabs, tab width 2 and naming-check configuration).
- [.swiftlint.yml](../.swiftlint.yml) owns quality-rule selection, include/exclude roots and the [baseline](../.swiftlint-baseline.json).
- [Guidance](../.pi/GUIDANCE.yaml) owns verification expectations and authorization.

## Repository checks

Initialize `swift64` from the [setup](README.md#setup-and-quick-commands), then run from the repository root:

```sh
"$swift64" package plugin --allow-writing-to-package-directory format --check
"$swift64" package plugin lint

# Applies to all configured format roots; use only for authorized broad formatting.
"$swift64" package plugin --allow-writing-to-package-directory format
```

- Format accepts only no arguments (apply) or `--check`.
  - It runs `/usr/bin/xcrun swift-format` first, then syntax-aware GuardFormatTool. A failing first pass prevents the second.
  - The manifest declares package-write permission even for check mode.
  - Roots are `Package.swift`, `Agent`, `Scenario`, `VisionCLI` and `apps`, including package-local scenario sources/tests.
  - Root `Tests`, `Plugins`, `Scripts` and `OpenXPCGenerator` are outside that invocation. GuardFormatTool's recursive traversal skips build/generated/linked directories.
- Lint accepts no arguments and runs pinned SwiftLint with `lint --strict --no-cache --config .swiftlint.yml` against the repository root.
  - It sets `TOOLCHAIN_DIR=/Library/Developer/CommandLineTools` for SourceKit discovery, reports warnings as failures and applies no fixes.
  - Configured includes cover the manifest, Agent, Scenario, VisionCLI, root Tests, apps, agents, Plugins and Scripts, with build/dist/HostBuilds/Projects excluded.
  - OpenXPCGenerator is outside configured include roots; a configured-root pass does not cover it.
  - The checked-in baseline is empty at this rewrite's inspection; that is not a claim that a new lint execution passed.

## Changed-file workflow

- Follow the conventions' scoped-apply rule. Replace the placeholders below with explicit authored Swift paths; do not type the angle-bracket placeholders literally.
- GuardFormatTool is a root executable target, not an assumed PATH command. Build it only when authorized; its path below assumes normal root debug products. For custom scratch, use that scratch's matching products directory.

```sh
# Tool preparation, when needed and authorized.
"$swift64" build --product GuardFormatTool

# Apply only to the selected changed files.
xcrun swift-format format --in-place --configuration .swift-format <changed-files>
.build/debug/GuardFormatTool --apply <changed-files>

# Separate layout and guard checks for explicit selected files.
xcrun swift-format lint --strict --configuration .swift-format <files>
.build/debug/GuardFormatTool --check <files>

# Use the resolved SwiftLintBinary supplied by the pinned dependency,
# not an arbitrary globally installed SwiftLint.
<pinned-swiftlint> lint --strict --no-cache --config .swiftlint.yml <files>
```

- GuardFormatTool accepts one mode and one or more file/directory paths; its core preserves comments and complex condition interiors.
- Explicitly check changed scenario files and changed plugin/script/generator/root-test files outside broad formatting coverage.
- Use the pinned-binary invocation for changed generator sources; do not infer their lint status from `package plugin lint`.
- For tool locations with nonstandard products, inspect the active build output rather than assuming a flat dependency binary path.

## Verification and recorded limits

- Guard-format idempotence/comment/condition tests and format/chart wiring tests belong to the root package under [SwiftLinesPluginTests](SwiftLinesPluginTests/).
- Learnings records generated-directory traversal and stale SwiftSyntax/Testing linker failures; the current guard traversal skips generated directories and optional [clean-test](testing.md) provides isolated scratch. Those historical recoveries do not establish a new pass.
- The original root evidence records an untouched generator `empty_count` violation outside configured lint roots. This rewrite did not rerun lint or establish whether that violation remains; a scoped-root clean claim must not silently include it.
- No formatter, lint tool, build or test ran during this documentation rewrite.
