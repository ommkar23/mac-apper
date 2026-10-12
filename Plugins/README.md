# Repository tooling

Plugins supplies the repository's SwiftPM commands for app packaging, code quality, source-line reporting and fresh-build tests. It is part of the [root package](../Package.swift), not an independent package or product runtime module.

- **Start here**
  - [Packaging](packaging.md): bundle/unbundle commands, signed output and artifact ownership.
  - [Code quality](code-quality.md): formatting/lint entry points, configured coverage and changed-file commands.
  - [Clean tests](testing.md): supported packages, private scratch and verification limits.
  - [Source-line reporting](#source-line-reporting): counts and distribution chart.
- **Document owners**
  - The [root overview](../README.md) introduces the product and module hierarchy.
  - [Conventions](../.pi/CONVENTIONS.yaml) owns dependency, source/artifact and formatting policy; [guidance](../.pi/GUIDANCE.yaml) owns safety, authorization and verification practices.
  - [Learnings](../.pi/LEARNINGS.yaml) records observed failures/recoveries. Commands here describe current entry points, not permission to run them or new verification evidence.

## Setup and quick commands

- Run from the repository root on macOS 14+ with Command Line Tools/SDK and standalone Swift 6.4.0, using default Swift Build rather than `--build-system native`.
  - Invoke the installed driver explicitly: inherited PATH and `xcrun swift` may still select CLT Swift 6.2.3.
  - SwiftPM resolves pinned build/test dependencies: SwiftSyntax 602.0.0, SwiftLintPlugins 0.65.1 and swift-testing 6.2.3. These commands can build helper tools and resolve dependencies.
  - `swift-format` is selected through `/usr/bin/xcrun`; charting uses Apple's AppKit, Charts and SwiftUI. No Xcode installation or separate chart package is required.
- Choose only the command authorized for the task; this is a menu, not a required sequence.

```sh
swift64="$HOME/Library/Developer/Toolchains/swift-6.4.0-RELEASE.xctoolchain/usr/bin/swift"

# Check code quality (format declares package-write permission even for checks).
"$swift64" package plugin --allow-writing-to-package-directory format --check
"$swift64" package plugin lint

# Export source counts and a chart.
"$swift64" package --allow-writing-to-package-directory swift-lines

# Assemble or remove the owned app/build directory, only when authorized.
"$swift64" package --disable-sandbox bundle app
"$swift64" package --disable-sandbox unbundle app

# Optional fresh-build test, not a repository-wide cleanup.
"$swift64" package --disable-sandbox plugin clean-test Scenario
```

- Formatting without `--check` applies changes; use the [changed-file workflow](code-quality.md#changed-file-workflow) instead of a repository-wide apply for scoped work.
- Bundle/unbundle support only `app`. Clean-test has a fixed package allowlist and an optional filter; see the focused guides before selecting either.
- Full-product packaging is separate from package-local scenario hosting; see [Scenario](../Scenario/README.md), [Agent](../Agent/README.md) and [DevTools](../apps/built-in/dev-tools/README.md).

## Source-line reporting

- `swift-lines` accepts no arguments and discovers authored Swift files beneath package `Sources` directories across the repository.
  - It prints file counts, total lines and sorted per-file counts, excluding tests, fixtures, Plugins, Scripts, hidden/build/generated output and linked paths.
  - It counts newline-delimited physical lines, including a final unterminated line, rather than logical statements or complexity.
- Output is `dist/swift-lines-distribution.png`, with 20-line histogram bins and a `2000+` overflow bin when needed.
  - This report is an explicit top-level `dist` output, not a reusable app bundle or test evidence directory.
  - Intermediate `swift-lines.json` stays in SwiftPM plugin work storage. The command rejects a non-directory `dist` or a nonregular existing chart destination and can replace its existing regular chart.
  - It does not remove other `dist` contents or write `dist/evidence/`.

## Code map

- SwiftPM dispatches commands to `performCommand(context:arguments:)`, builds declared helper tools and supplies tools through `context.tool`.
- [BundlePlugin](BundlePlugin/plugin.swift) and [UnbundlePlugin](UnbundlePlugin/plugin.swift) assemble/remove owned output; [CleanTestPlugin](CleanTestPlugin/plugin.swift) owns disposable test scratch.
- [FormatPlugin](FormatPlugin/plugin.swift) orchestrates swift-format and [GuardFormatTool](FormatPlugin/Tool/main.swift), with parsed rewriting in [GuardFormatter](FormatPlugin/Core/GuardFormatter.swift).
- [LintPlugin](LintPlugin/plugin.swift) locates the pinned SwiftLint binary and sets CLT `TOOLCHAIN_DIR` for SourceKit.
- [SwiftLinesPlugin](SwiftLinesPlugin/SwiftLinesPlugin.swift) collects counts; [SwiftLinesChartTool](SwiftLinesPlugin/ChartTool/main.swift) renders the bounded histogram.
- [SwiftLinesPluginTests](SwiftLinesPluginTests/) owns root-package guard-format/chart/wiring tests; [integration tests](../Tests/IntegrationTests/) cover bundle metadata and scenario retirement.

```sh
# Static navigation, without executing plugins.
rg -n 'performCommand|context.tool' Plugins
rg -n 'formatGuards|buckets\(for|\.bundle-owner|scratch' Plugins
rg -n 'verb:|SwiftLintBinary|GuardFormatCore' Package.swift
```

## Verification status

- This documentation rewrite checked Markdown links, relative paths and command contracts against the current manifest/plugin sources using filesystem inspection; Git metadata was unavailable.
- No package tests, builds, plugin executions, bundle operations, GUI launches, Pi sessions, credential operations or live calls were performed.
- Existing recorded runtime evidence and unresolved failures remain owned by the [root documentation](../README.md) and [learnings](../.pi/LEARNINGS.yaml); no historical outcome is promoted to a new pass here.
