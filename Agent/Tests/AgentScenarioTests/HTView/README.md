# HTView standalone HTML scenario

HTView is a human-usable native macOS viewer for one self-contained UTF-8 HTML file.
Inline CSS and JavaScript must work offline.
External assets, local servers, functional app-specific XPC and speculative features are outside the case.
The app chooses its visual design.

## Selectors

- Live case: `agentCreateHTViewScenario`.
- Review retention: `AGENT_CREATE_KEEP_PROJECT=1`.
- One attempt means one normal Create request. Tool-level repair is allowed within that request.
- It does not guarantee model success or authorize external retries.
- Live execution and credential staging need separate authorization. See [scenario runbook](../../../docs/scenarios.md).

From the repository root, with live gates unset:

```sh
swift64="$HOME/Library/Developer/Toolchains/swift-6.4.0-RELEASE.xctoolchain/usr/bin/swift"
"$swift64" test --package-path Agent --filter 'htViewHTMLFixture|htViewScenarioEvidence|htViewWebKitMalformedEvidenceOffline|htViewResource|htViewPromptAndObserver'
"$swift64" test --package-path Agent --filter htViewEmbeddedWebKitOfflineRegression
```

Check executable `swift` and `swiftc` versions first. Use standalone Swift 6.4 and default Swift Build.
The native regression needs local Aqua and WebKit. It owns sequential private host builds.
It makes no Pi, MCP or Gemini calls.

## Verification contract

- The existing WorkspaceSession, native adapter, generated XPC and minimal signed Agent/DevTools hosting remain unchanged.
- The prompt requires public main-actor `ApplicationModel.openDocument(_ url: URL)`.
  - `documentURL: URL?` identifies the source document.
  - `errorMessage: String?` is nonempty on failure and nil on success.
  - `isLoading: Bool` reflects WebKit completion or failure, not just file reading.
  - The user picker must call the same action.
- The independent host creates the generated model and `ApplicationRoot(model:)` once.
  - It opens a real missing file and requires observable error state.
  - It then opens an owned valid fixture through the same model action.
  - It observes the embedded browser without replacing its delegate, rules, preferences or loading action.
  - Generated preprocessing and navigation/load/error lifecycle stay active.
  - It checks title and DOM, exact computed inline color, load-script marker and scripted button update.
  - Successful rendering requires cleared error state and finished loading.
- SwiftPM stages declared `.process` and `.copy` resources in standard AppModel/AppViews directories.
  - Real generated `Bundle.module` accessors and resource processing are preserved.
  - Source staging accepts physical paths beneath the private repository-root `.tmp/` only.
  - It rejects original ancestor and leaf links before using descriptor-derived paths.
  - Module-relative paths require a complete component prefix in the same path representation.
  - The validated file descriptor supplies bounded resource reads without rewriting bytes.
  - Offline staging controls cover root-file and directory `.process`/`.copy` declarations in both modules.
  - Historical alias spellings are synthetic strings only. No system-temp fixture or alias probe is needed.
  - The native regression executes AppModel `.process("Resources")` lookup of `example.html` and AppViews `.copy("Resources")` lookup.
  - Bounds are 32 declarations per module, 1024 UTF-8 bytes per resource path, 256 tree entries per module, 256 KiB per file and 2 MiB per module.
  - The manifest is bounded to 64 KiB. Traversal rejects links, escapes and nonregular files.
  - Localized declarations, custom source paths/selections, exclusions, module settings and plugins fail explicitly rather than being silently dropped.
- Authored Test evidence requires real scoped edits and a matched `passed`/numeric exitCode zero result after final scoped model/view/test/manifest edits.
  - Parsed Testing bodies must exercise opening and errors. Starter tests, comments and self-reports do not qualify.
  - This structural audit is not exhaustive behavioral test analysis.
- Scoped successful Build/Run evidence identifies the retained development executable.
  - Exact executable identity and development liveness are required after independent verification.
  - Development Build/Run is not production delivery.

## App naming

- The prompt still requests an app name and main window title of exactly `HTView`.
  - It requests a stable title when documents change.
  - Internal `ProductionApp` executable and target names are allowed. They are not user-visible branding.
  - The fixture's HTML document title is independent of the native window title.
- Acceptance excludes independent app-name and native-window-title verification.
  - Run bundle naming assertions and CoreGraphics window observation are retired.
  - Naming-observation permissions are not an acceptance requirement.
  - Embedded-browser document-title checks remain HTML behavior checks, not native-title checks.
- Naming relies on correct bundle metadata and SwiftUI API wiring.
  - Shared tooling uses the project plist for Run branding.
  - Scaffold v9 derives its default title from packaged bundle metadata.
  - Editable SwiftUI content may override the default through `navigationTitle`.
  - Scene compiler probes and synthetic Bundle execution are retired naming checks.
  - The scenario does not edit protected files to satisfy naming.
  - Project-owned source-wiring, AppName and shared branding logic tests remain documented in the [verification runbook](../../../docs/verification.md#naming-verification-boundary).
  - These checks do not independently establish rendered naming or guarantee all generated app behavior.
- The accepted one-attempt report at `/private/tmp/mac-apper-htview-live.ugFtAO/report.md` predates these assertions.
  - It remains historical evidence. It is not a naming pass or authorization for another paid attempt.

- The failed retained attempt at `/private/tmp/mac-apper-htview-live.KpZIeR/report.md` remains failed.
  - Its resource-staging rejection prevented independent HTML/CSS/JavaScript verification.
  - The latest retained copy-resource failure is recorded at `/private/tmp/mac-apper-htview-naming-live.blfNDD/report.md`.
  - The unchecked path-length slice was consistent with its malformed `ppModel/example.html` suffix.
  - The original runtime path spellings were not captured. Historical alias causation remains unproven.
  - The staging correction does not turn either retained attempt into a pass or authorize a live retry.
  - Full Agent acceptance remains unverified.
  - See the [separate retirement archive note](../../../../docs/verification-archive.md#naming-verification-retirement--2026-10-14).

## Controls, cleanup and limitations

The native regression rejects missing browser views, disabled JavaScript, wrong CSS, ineffective load scripts and ineffective clicks.
Its unsupported `^(https?|wss?|ftp|file):` control requires an actual WebKit rule-compilation failure receipt.
Receipts establish that mutations executed. Compilation/setup failures do not count as behavioral rejections.
Private command logs, negative-control hosts and receipt archives are retained as evidence.
Successful hosts and temporary source fixtures are removed after exact-owned child reaping.
Windows remain off-desktop, non-key and nonactivating.

The actual user picker is unverified. Checks do not prove visible error presentation, physical mouse clicks, Safari parity, general navigation security or production packaging.
Generated code runs with user permissions. Point-in-time path checks are not a filesystem sandbox or a lease against later changes.
Existing retained source, bundles, histories, storage and user-review apps are outside rewrite cleanup.
