# Isolated ImageRenderer investigation

- Scope: spike-only SwiftUI/AppKit code, resources, fixtures, tests, scripts and evidence; no production changes.
- Reference: `../apps/built-in/dev-tools/Sources/Application/Resources/PreviewRenderer.swift`.
- Motivation: read-only report `/private/tmp/mac-apper-counter-lifecycle-live.xE4QZx/report.md`, which reports missing Increment/Decrement labels in a validated preview. This spike does **not** rerun that workflow, modify its retained fixtures, or establish its exact internal cause.

## Broad native-view review (2026-10-11)

- Primary review folder: **`/Users/ommkar/dev/mac-sde/mac-apper/spike/evidence/native-review.eZlLLf`** ([open](evidence/native-review.eZlLLf/)).
  - Exactly **24 descriptive primary PNGs directly in this folder**, plus `manifest.json`; no logs, builds, contact sheets or repeat images there.
  - Manifest maps every image to its fixture, dimensions, byte count, SHA-256, shared capture configuration, fresh-repeat identity and local visual observation.
  - Auxiliary evidence: [`evidence/review-work.kpb5li/`](evidence/review-work.kpb5li/); focused failing/green tests: [`evidence/review-work.Bvr111/`](evidence/review-work.Bvr111/). All are retained.
- Separate `ReviewFixture` matrix preserves all 16 historical `Fixture` cases and their evidence. Native coverage:
  - `native-button-styles`, `button-toolbar`: automatic/plain/bordered/borderless/prominent/disabled buttons, labels and closed Menu.
  - `text-inputs`, `text-editor`: seeded rounded/plain text fields, masked local test password and multiline editor.
  - `toggles`, `segmented-picker`, `menu-picker`: switches, checkboxes, segmented/menu/radio choices and stepper.
  - `sliders`, `progress-indicators`: continuous/discrete/disabled sliders and determinate linear/circular progress.
  - `sidebar-list`, `project-table`: sections, seeded selection, four-row three-column table.
  - `profile-form`, `group-boxes`: grouped profile/preferences form, labeled content and nested group-box content.
  - `scrolling-cards`, `lazy-grid`, `alignment-grid`: fixed viewport, twelve seeded tiles and aligned metrics.
  - `navigation-split`, `tab-view`: sidebar/detail composition and selected Library tab with three authored tab labels.
  - `typography`, `shapes-gradients`, `symbol-gallery`, `local-images`: font hierarchy/wrapping, vector shapes/linear/radial gradients, nine SF Symbols, bundled and file-based checker PNGs.
  - `dashboard`, `settings`: combined metrics/progress/project rows and account/notification/display controls.
- Configuration: **720×540 points/pixels, scale 1, Aqua/light**, `en_US_POSIX`, disabled animations, source-defined deterministic local state; no clock/random/network data. NSApplication is `.prohibited`; the owned buffered borderless window is off desktop, never activated/key. Native `NSHostingView.cacheDisplay` captures only its owned view after at most 0.25 seconds of monotonic layout settling. Window is ordered out, detached and closed on return/error; successful executable output confirms closure before PNG publication. No desktop screenshot API is used.
- Verification on arm64 macOS 26.6.2 (25G83), explicit standalone Swift 6.4.0/default Swift Build, installed CLT SDK 26.2:
  - Focused red failed for absent review/capture APIs; focused green passed two tests. Final affected spike suite passed **5 Swift Testing tests**, including all original fixture tests, review identities/configuration, malformed/oversize/truncated/wrong-size PNG rejection and real owned-window PNG/closure.
  - Each primary PNG passed ImageIO properties/full decode, complete PNG signature/end marker, exact nonzero dimensions and 2 MiB bound: actual **18,434–116,626 bytes**.
  - **48 fresh capture processes** (24 primary + 24 repeats) exited 0, were waited/reaped and checked ESRCH. All 24 repeats match primary SHA-256. Two subsequent 24-fixture fresh-process rechecks also match; the last checks final source. `lifecycle.json`, `post-format-lifecycle.json`, `verified-final-lifecycle.json` retain exact kernel executable/PID/start identities and results; final listing also uses identity-checked supervision.
  - Timeout supervision revalidates the exact direct child's kernel path and start time before TERM/KILL; it does not use name-wide or PID-only signals. No timeout or signal occurred. Identity lookup failure blocks completion/signaling and retains files. Offline supervisor tests passed **2 tests** (changed/missing identity never signals; exact identity targets only direct child); real timeout escalation itself was not exercised.
  - Scoped swift-format, GuardFormatTool and strict SwiftLint passed on four changed Swift files. Initial SwiftLint crashed locating SourceKit; documented `TOOLCHAIN_DIR=/Library/Developer/CommandLineTools` selection recovered with zero violations. Both logs remain. Final Swift source compilation has only pre-existing toolchain/CLT linker search-path warnings, not the earlier unnecessary Codable warnings.
- **PNG creation is not visual fidelity.** Offline local inspection of all primary images/contact sheets found recognizable seeded content, with no yellow/red whole-control placeholders observed; this is not an automated visual pass or model review.
  - `tab-view.png`: Library body/selected label render, but **Activity and Settings labels are missing against a black tab-strip area**. Retained fidelity failure; no replacement tabs or permission bypass.
  - `shapes-gradients.png`: gradients/shapes render, but the capsule stroke has **extra rectangular side marks**. Retained visual artifact, not an asserted correct capsule.
  - `scrolling-cards.png`: cards 1–5 and part of 6 appear; the rest are intentionally below the viewport. Scroll interaction is untested, not missing-data coverage.
  - Inactive sidebar/control labels are subdued and prominent buttons do not establish active accent-color fidelity. Menu/picker popups, alternate tabs, actions/typing/focus, accessibility, active key windows, dark appearance, Retina scale, async content and other platforms remain unverified. Asset-catalog lookup remains unavailable as documented below; no tooling installation was attempted.
- Reproduce from project root: `bash spike/scripts/review.sh`.
  - Creates a new unique `native-review.*` primary folder and separate `review-work.*` for scratch/logs/repeat PNGs; does not regenerate or overwrite old resources/evidence.
  - Explicit `swift64="$HOME/Library/Developer/Toolchains/swift-6.4.0-RELEASE.xctoolchain/usr/bin/swift"`; `sdk=$(xcrun --sdk macosx --show-sdk-path)`; `env -u SDKROOT "$swift64" test/build --package-path spike --scratch-path "$work/build" -j 2 -Xswiftc -sdk -Xswiftc "$sdk"`. Supervisor: `python3 spike/scripts/review-capture.py "$bin/render-spike" "$work" "$review" "$PWD/spike/fixtures/local-checker.png"`.
  - Selected native-only CLI: `render-spike --review /new/path/typography.png spike/fixtures/local-checker.png typography`; destination must not exist. `--review-list` lists this matrix; original CLI/`--list` remain unchanged.
  - Actual commands/results: `test.log`, `final-test-2.log`, `final-build-2.log`, `final-format.log`, `lint-clt.log`, `final-supervisor-tests.log`, `verified-final-result.txt` and `verified-source-sha256.json` under the auxiliary folder.
- Cleanup/preservation: all successful owned capture windows closed and direct children reaped; **no files/directories deleted**, no historical or unresolved-run cleanup attempted. Scratch/repeats/failed evidence remain outside the primary folder. Only spike-owned source/tests/scripts/docs/evidence changed. No production source/resource, full app bundling, Pi scenario/session, MCP/Web, credential access, Gemini/model evaluation, permission change or installation occurred. Git status remains unavailable because this directory is not a Git repository.

## Results and boundaries

- Final isolated evidence: [`evidence/run.IDMajI/`](evidence/run.IDMajI/).
  - 16 fixtures, each in a fresh process, repeated in another fresh process.
  - Per fixture: ImageRenderer before any owned window, window-backed NSHostingView capture, then ImageRenderer again after hosting the **same content value**.
  - 48 primary PNGs per pass, all **460×430**, each at most 2 MiB, with fixture/method/file/SHA-256 manifests.
  - Both passes match byte-for-byte; all 16 before/after-host ImageRenderer hashes also match. This rules out earlier fixtures' windows as a necessary condition for these results, not every possible lifecycle effect.
  - 32 capture processes returned 0, were waited/reaped and checked ESRCH; each executable checked that its owned window was closed. See `lifecycle.json` and [`final-isolated-process-check.json`](evidence/final-isolated-process-check.json).
  - Three spike-local Swift Testing tests passed. They check fixture identities/resources and all fixtures' image dimensions, **not** visual support or button actions.
- Tested installation: arm64 macOS **26.6.2 (25G83)**, explicit standalone **Swift 6.4.0**, Swift language mode 6, default Swift Build, system-selected CLT macOS **26.2** SDK.
- Observed with the matrix's view composition:
  - Text, shapes, standalone SF Symbols, bundled PNG, local-file PNG and plain buttons rendered recognizable content through both methods.
  - Automatic, bordered, borderless and borderedProminent buttons produced yellow/red **whole-control placeholders** through ImageRenderer. Both `Label` and **text-only** buttons failed this way; it is not merely a missing SF Symbol inside an otherwise rendered button.
  - NSHostingView/window capture rendered Increment/Decrement text and plus/minus symbols for those same fixtures. No label replacement, state change, custom button style or layout workaround was introduced between methods.
  - The AppKit NSButton representable was a whole-view placeholder through ImageRenderer and legible in the native capture.
  - The counter fixture simultaneously rendered `number.square.fill`, zero and plain Reset while its large bordered Label buttons were placeholders.
- Important reduction limit:
  - The standalone reduced counter in `minimal/CounterRepro.swift` **rendered its bordered buttons successfully**, with rounded gray button backgrounds, despite the matrix counter's placeholders.
  - [`evidence/minimal.r9VSLV/counter.png-white.png`](evidence/minimal.r9VSLV/counter.png-white.png) records that result with Swift 6 mode/debug flags; `InlineCounterControl.swift` preserves the original direct-inline reduction.
  - The conditional reduced composition and helper extraction did not reproduce the matrix failure. The exact composition/build-context distinction is **not established**. No claim about undocumented SwiftUI/Core Animation internals follows from this difference.
  - Therefore, this is evidence for these exact fixtures/configurations, **not** a blanket assertion that ImageRenderer cannot render bordered buttons or SF Symbols.

## Fixture matrix and visual artifacts

- Comparison files are **left: ImageRenderer, right: NSHostingView/window**, flattened on white solely for viewing; raw transparent PNGs are retained separately.
- All links below use the final fresh-process, pre-host capture; each folder also contains an `after-host-comparison.png`, three raw PNGs and an identity manifest.
- Text/shapes: [`text-shapes`](evidence/run.IDMajI/first/text-shapes/text-shapes-cold-comparison.png).
- Standalone `number.square.fill`, `plus`, `minus`: [`symbols`](evidence/run.IDMajI/first/symbols/symbols-cold-comparison.png).
- Identical deterministic checker pixels, loaded by distinct paths:
  - [`bundled-png`](evidence/run.IDMajI/first/bundled-png/bundled-png-cold-comparison.png): SwiftPM `.copy` resource, located with `Bundle.module`, loaded using `NSImage(contentsOf:)`.
  - [`local-png`](evidence/run.IDMajI/first/local-png/local-png-cold-comparison.png): file under `fixtures/`, loaded using `NSImage(contentsOf:)`.
  - These are **not** named asset-catalog images.
- Large labeled and text-only Increment/Decrement buttons, five available macOS styles:
  - Automatic: [`Label`](evidence/run.IDMajI/first/automatic-label/automatic-label-cold-comparison.png), [`Text`](evidence/run.IDMajI/first/automatic-text/automatic-text-cold-comparison.png).
  - Plain: [`Label`](evidence/run.IDMajI/first/plain-label/plain-label-cold-comparison.png), [`Text`](evidence/run.IDMajI/first/plain-text/plain-text-cold-comparison.png).
  - Bordered: [`Label`](evidence/run.IDMajI/first/bordered-label/bordered-label-cold-comparison.png), [`Text`](evidence/run.IDMajI/first/bordered-text/bordered-text-cold-comparison.png).
  - Borderless: [`Label`](evidence/run.IDMajI/first/borderless-label/borderless-label-cold-comparison.png), [`Text`](evidence/run.IDMajI/first/borderless-text/borderless-text-cold-comparison.png).
  - Bordered prominent: [`Label`](evidence/run.IDMajI/first/prominent-label/prominent-label-cold-comparison.png), [`Text`](evidence/run.IDMajI/first/prominent-text/prominent-text-cold-comparison.png).
- Counter combination: [`counter`](evidence/run.IDMajI/first/counter/counter-cold-comparison.png).
- AppKit-backed NSButton representable: [`appkit-representable`](evidence/run.IDMajI/first/appkit-representable/appkit-representable-cold-comparison.png).
- Actual asset-catalog coverage: **unavailable**, not passed.
  - `fixtures/SpikeAssets.xcassets/` contains a source catalog/imageset, kept separate from the PNG resource route.
  - `xcrun --find actool` fails on this CLT-only installation; no compiled `Assets.car`, named `Image` asset lookup, or asset-catalog support verdict exists. No tooling was installed.

## Rendering configuration and limitations

- ImageRenderer copies the production template's fixed frame, proposed size, light color-scheme environment, animation-disabled transaction, scale 1, `cgImage` extraction, PNG encoding and image/byte bounds. It does not add a SwiftUI background or set `isOpaque`.
- Spike setup additionally makes NSApplication nonactivating (`.prohibited`) and selects Aqua appearance for native baseline consistency. This is not proof of the production service's complete process environment.
- Native baseline: borderless buffered owned NSWindow, positioned off desktop, never made key or activated; NSHostingView layout/display, at most 0.25 seconds of bounded run-loop settling, `cacheDisplay` into a scale-1 460×430 NSBitmapImageRep.
  - It captures the owned view, **not** the display. No ScreenCaptureKit, CGWindow screen image, accessibility automation, screen-recording permission, or unrelated-app interaction is used.
  - The inactive prominent-style capture is not a blue/accent-emphasized button. It establishes readable labels in this native capture, not active-window prominent-style fidelity.
  - Font antialiasing, appearance, inactive state and platform sizing can differ. Cross-method PNG hash differences are not failure verdicts; inspect the comparison images.
- No clicks, async data loading, animation, dark appearance, non-1 scale, Intel, other SDK/compiler/OS releases, active key windows, media/web containers or exhaustive image-loading APIs were tested.
- No production Preview fix, fallback recommendation or future-OS support guarantee is made.

## Reproduction and verification commands

From the project root:

```sh
# Entire isolated fixture matrix, tests, identity validation and repeat check.
bash spike/scripts/run.sh

# Independent reduced counter control; currently does NOT reproduce placeholders.
bash spike/scripts/minimal.sh
```

- `run.sh` explicitly selects `~/Library/Developer/Toolchains/swift-6.4.0-RELEASE.xctoolchain/usr/bin/swift`, removes inherited SDKROOT and passes the system SDK to Swift. No `--build-system native`, package dependencies or paid calls are used.
- Each run creates a nonempty scratch path under `spike/evidence/run.*`, sets its child TMPDIR there, retains logs/builds/PNGs, and only signals its direct owned capture child on timeout (30 seconds, then wait). No historical path is removed.
- The tests use the **installed toolchain's Testing 6.4** without adding a package dependency; this spike does not change the product's pinned Testing convention.
- Smallest **verified failing** selection uses the package's counter fixture, not the successful independent reduction:

```sh
swift64="$HOME/Library/Developer/Toolchains/swift-6.4.0-RELEASE.xctoolchain/usr/bin/swift"
run="$PWD/spike/evidence/run.IDMajI"
bin=$(env -u SDKROOT "$swift64" build --package-path spike \
  --scratch-path "$run/build" --show-bin-path)
out=$(mktemp -d "$PWD/spike/evidence/counter-only.XXXXXX")
python3 - "$bin/render-spike" "$out" "$PWD/spike/fixtures/local-checker.png" <<'PY'
import subprocess, sys
subprocess.run([*sys.argv[1:], 'counter'], check=True, timeout=30)
PY
```

- The fixture's relevant combination is `Label("Increment", systemImage: "plus")` / `Label("Decrement", systemImage: "minus")` inside `.buttonStyle(.bordered).controlSize(.large)`, together with the successfully rendered standalone `Image(systemName: "number.square.fill")`. `Sources/SpikeFixtures/Fixtures.swift` retains the exact failing composition.
- Format verification: `xcrun swift-format lint --strict --configuration .swift-format` and existing `GuardFormatTool --check` passed for all six spike Swift files (`evidence/format.log`).
- Setup failures remain explicit: initial missing source targets (`evidence/red.log`), then unavailable XCTest (`evidence/run.xkoM8W/test.log`); switching this dependency-free spike to installed Swift Testing passed. These are setup/compile failures, not visual test failures.
- Earlier single-process exploratory runs remain under `evidence/`; final claims use `run.IDMajI`. `isolated-vs-initial.json` records shared-artifact byte differences rather than pretending the earlier process layout was identical.

## Apple context

- [Apple ImageRenderer documentation](https://developer.apple.com/documentation/swiftui/imagerenderer), fetched as public documentation without MCP or a model; raw response and extracted context are retained in `evidence/apple-imagerenderer.json` and `evidence/apple-context.txt`.
- Apple states that output includes views directly rasterized by SwiftUI primitives, while some complex controls/containers and most UIKit/AppKit views can be represented by placeholders. Apple also warns that a particular view's drawing/compositing implementation can change between releases.
- That documented context is consistent with the observed **whole-control** placeholders. It does not identify the private implementation of any tested button or explain the successful reduced counter versus failing matrix composition. This spike makes no blanket promise about future releases.

## Preservation

- Product packages, original GUI, Agent/DevTools scenarios, Pi/model/Gemini/MCP calls, credentials, global configuration and historical cleanup were excluded.
- Only public Apple documentation was fetched. No package dependency was added or installed.
- Owned capture windows were closed; exact direct children were reaped and checked absent. Build scratch and artifacts are intentionally retained **under spike/**.
- No product bundle rebuild was needed or performed: no app-affecting product source/resource changed. Git status is unavailable because the project directory is not a Git repository.
