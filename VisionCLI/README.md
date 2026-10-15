# VisionCLI

VisionCLI is an optional standalone macOS screenshot reviewer. Its `vision-cli` executable asks Gemini to assess visible appearance against explicit criteria; it does not use Apple Vision/OCR or prove application behavior.

- It is not a Pi tool, XPC service, Mac Apper runtime dependency, or part of the product bundle.
- Agent's opt-in Create counter and plan scenarios stage the executable separately. [Agent](../Agent/README.md) owns their prompts, orchestration and assertions; [Scenario](../Scenario/README.md) owns reusable hosting support.
- Return to the [root overview](../README.md) for product setup and repository-wide verification policy.

## Build and offline checks

Requires macOS 14+, Command Line Tools with a macOS SDK, and the repository's standalone Swift 6.4.0 toolchain; Xcode is not required. Runtime dependencies are Apple frameworks (Foundation, ImageIO and CryptoKit). [Package.swift](Package.swift) pins swift-testing 6.2.3 for tests only; SwiftPM resolves it automatically.

From the repository root, when local build/test execution is authorized:

```sh
swift64="$HOME/Library/Developer/Toolchains/swift-6.4.0-RELEASE.xctoolchain/usr/bin/swift"
"$swift64" build --package-path VisionCLI -c release
VisionCLI/.build/release/vision-cli --help
VisionCLI/.build/release/vision-cli models
"$swift64" test --package-path VisionCLI
```

- Use the explicit standalone driver and default Swift Build, not `--build-system native`; an inherited `swift` or `xcrun swift` may select the older CLT compiler.
- Invoke the built executable for JSON callers rather than mixing SwiftPM build diagnostics into stdout.
- Tests use mocked HTTP and owned image/synthetic-credential fixtures under private repository-root `.tmp/`. They do not read the real local `.env` or contact Gemini.
- Follow the [temporary-work contract](../README.md#temporary-work). Durable images and credentials stay in their existing storage.
- Tests cover request validation, image decoding/hash/link/truncation checks, request construction, conservative verdicts, invalid provider results and credential precedence/permissions.
- “Offline” means no model/API call, not guaranteed air-gapped SwiftPM dependency resolution.

## Private scenario products

For authorized local preparation, allocate unique scratch beneath repository-root `.tmp/`.
Verify both standalone Swift executables as described in the [root setup](../README.md#new-mac-setup).
Use the same driver, scratch and configuration to build and discover products:

```sh
# From the physical repository root, after initializing private TMPDIR.
private=$(mktemp -d "$PWD/.tmp/vision-products.XXXXXX")
test -n "$private" && test -d "$private" || exit 1
"$swift64" build --package-path VisionCLI --scratch-path "$private" -c release --product vision-cli
vision_products=$("$swift64" build --package-path VisionCLI --scratch-path "$private" -c release --show-bin-path)
test -x "$vision_products/vision-cli" || exit 1
# In a separately authorized direct Counter/Plan swift test invocation:
# AGENT_VISION_PRODUCTS="$vision_products" ... "$swift64" test --package-path Agent ...
```

- Do not infer the Swift Build output layout from the scratch path.
- Strict private runs must supply `AGENT_VISION_PRODUCTS`. Agent then skips the default Vision build and selects this directory's `vision-cli`.
- Explicit paths must be absolute, without traversal or linked ancestors/leaves. The selected leaf must be a regular executable. Invalid input fails without fallback.
- Absent input preserves legacy preparation. Unused Vision overrides are ignored when Vision is not requested.
- Agent retains `check-config --env-file` arguments and stages only the executable at `VisionCLI/vision-cli`, never the credential file. Hosted `AGENT_SCENARIO_VISION_CLI` is not a preparation input.
- The scenario-run helper clears inherited `AGENT_` overrides and has no arbitrary plan environment support. Use deliberate direct invocations for private products.
- Building and discovering products above does not read credentials, start a host or authorize live calls.
- Keep the exact owned scratch until its builds and scenario consumers have exited. Remove only that directory after confirmed cleanup; retain meaningful logs/evidence separately under `.tmp/`.

## Review interface

- `verify` reads one bounded version-1 JSON object from stdin, then requires EOF, and writes one JSON result line to stdout.
- Input selects an absolute PNG/JPEG path and 1–20 uniquely identified criteria, with optional context and model. The default is `gemini-3.8-flash`; pin a model for reproducible review configuration.
- Completed results include per-criterion evidence, the CLI-computed verdict, dimensions and SHA-256. Exit codes are `0` pass, `1` fail, `2` uncertain, and `3` operational/configuration error.
- See [interface reference and examples](interface.md), [request schema](Schemas/request.schema.json) and [response schema](Schemas/response.schema.json) for fields, bounds and consumer checks.

The following command uploads the selected image, context and criteria to Google and may incur charges. Run it only with explicit live-review authorization and an approved request/image:

```sh
VisionCLI/.build/release/vision-cli verify < request.json
```

## Credentials, privacy and authorization

- A nonempty exported `GEMINI_API_KEY` takes precedence over a credential file.
- A package-local binary searches its executable ancestors for `VisionCLI/.env`. A relocated binary needs an exported key or `--env-file /absolute/path/.env`.
- Credential files must be bounded, nonlinked, owned by the current user and inaccessible to group/others; they are parsed as data, never executed as shell scripts. Do not print, copy into a host, or commit secrets.
- With authorization for local credential access, configuration can be checked without an API call:

  ```sh
  VisionCLI/.build/release/vision-cli check-config
  # For a relocated binary or an alternate private file:
  VisionCLI/.build/release/vision-cli check-config --env-file /absolute/path/.env
  ```

  This checks format/source only, not validity, quota, billing or model access. Credential presence does not authorize `verify` or scenario execution.
- The client uses `store:false`, ephemeral URLSession state, redirect refusal, response/time bounds and no automatic paid retries. These do not exempt uploads from Google's service/data-use policies.
- See [security and integration boundaries](security.md) for credential parsing, canonical image paths, transport behavior and caller responsibilities.

## Code and documentation map

- [CLI entry point](Sources/VisionCLI/VisionCLIMain.swift): argument handling, stdin/stdout, credential discovery and exit codes.
- [VisionCore protocol](Sources/VisionCore/VisionProtocol.swift): request validation and result/error types.
- [Local files](Sources/VisionCore/LocalFiles.swift): descriptor-relative no-follow reads, image validation and credentials.
- [Gemini client](Sources/VisionCore/GeminiClient.swift) and [transport](Sources/VisionCore/HTTPTransport.swift): Interactions API construction, bounded responses and computed verdicts.
- [Tests](Tests/VisionCoreTests/): offline image and protocol/client fixtures.
- [Model research](models.md): dated recommendations and official sources, not a current availability or accuracy benchmark.

## Limitations and evidence

- Screenshot judgments are probabilistic; image text may influence them despite the system instruction. Calibrate criteria on known good/bad screenshots before treating reviews as a gate.
- Appearance cannot establish button behavior, hidden state, initial runtime state, offline operation, persistence, production packaging or the agent's own visual judgment. Keep independent model tests and process checks.
- Uncertainty is inconclusive; an API, credential or path failure is not a visual failure. Successful rendering alone proves neither faithful capture nor image inspection.
- Earlier documentation records positive standalone and integrated reviews; [root verification history](../README.md) and [observed learnings](../.pi/LEARNINGS.yaml) retain their scope and failures. Those checkpoints are not checks performed by this documentation rewrite and do not establish calibrated/general accuracy or comprehensive negative/uncertain live coverage.
- This rewrite performed static documentation/source review only: no builds, tests, credential checks, scenarios or live calls.
