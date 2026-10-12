# SwiftUI Preview contract

[DevTools](../README.md) · [Other tools](tools.md) · [Verification](verification.md)

Preview compiles an authored factory in an isolated workspace and captures only its owned native view. It returns text-only PNG paths and metadata, not automatic Pi image content.

## Inputs and authored factory

- `viewPath` names an existing regular, nonlinked Swift file beneath `Sources/AppViews/`, at most 1 MiB. The Pi schema permits safe ASCII filename/directory components and bounds the string to 1024; authored service scope checks apply independently.
- Optional `screenSize: {width, height}` describes canvas points, not monitor resolution or window chrome. Default is 640×480 at scale 1; each integer dimension is 64–2048, total pixels at most 2,097,152, PNG bytes at most 2 MiB.
- The selected file must contain exactly one top-level, public, synchronous, nonthrowing, zero-argument, nongeneric `@MainActor` function named `apperPreview_NAME` returning `some View`.
- Wrap only that factory in `#if MAC_APPER_PREVIEW`; keep ordinary views outside. `#Preview` alone, comments, `#if DEBUG` and `#if os(macOS)` are not substitutes. Edit an existing factory rather than adding a second one.
- A factory can instantiate a file-private view and seed an isolated in-memory model without fixture input. For the current scaffold, adapt this example in a file importing SwiftUI and AppModel:

  ```swift
  #if MAC_APPER_PREVIEW
  @MainActor
  public func apperPreview_Example() -> some View {
      let model = ApplicationModel()
      model.apply(title: "Preview state", detail: "Transient starter presentation")
      return ApplicationRoot(model: model)
  }
  #endif
  ```

## Discovery and isolated compilation

- [PreviewRendering](../Sources/Application/PreviewRendering.swift) freezes nonlinked `Sources`, optional `Tests`, `Package.swift` and optional `Package.resolved` under `.mac-apper/PreviewBuild/<request-uuid>/` before discovery/build.
- Copying is bounded to 1 MiB per file, a shared 16 MiB byte budget, 1024 enumerated entries and directory depth 12. Dependency-module copies share the budget.
- It builds AppViews with `MAC_APPER_PREVIEW`, then inspects the selected file's compiler JSON AST both with and without the flag. [PreviewDiscovery](../Sources/Application/PreviewDiscovery.swift) rejects missing, ambiguous, invalid or production-visible factories instead of guessing from text.
- The adapter uses bounded standalone compiler calls, not a SwiftSyntax runtime dependency. Compiler JSON AST is not a stable public format; recorded evidence covers CLT Apple Swift 6.2.3 and standalone Swift 6.4.0, not future toolchains.
- A DevTools-owned `ApperSnapshot` executable is added only to the copied package, using conventional AppModel/AppViews targets and the packaged renderer template. Original manifest, protected sources and older protected PreviewApp infrastructure are not rewritten.
- Module lookup supports Swift Build directories beside products and older `Modules/` layouts, excluding AppViews' own module from discovery dependencies.
- Child limits:
  - Each build: 120 seconds; normal captured output: 65,536 bytes.
  - Bin-path query: 10 seconds and 4096 output bytes; SDK discovery: 10 seconds.
  - Each AST call: 30 seconds and 4 MiB output.
  - Snapshot execution: 15 seconds and 65,536 output bytes.
- Owned processes are canceled/reaped on execution failure/cancellation. Request workspace removal is attempted on exit; do not generalize this best-effort removal to a guarantee under arbitrary filesystem or process-cleanup failure.

## Native capture and limits

- The [packaged renderer](../Sources/Application/Resources/PreviewRenderer.swift) hosts the factory in NSHostingView inside an owned buffered borderless off-desktop AppKit window. NSApplication activation is prohibited; the window cannot become key or main.
- Capture uses explicit Aqua/light appearance, disabled animations and the requested scale-1 canvas. Layout/display receive a bounded 0.25-second run-loop settling opportunity before `cacheDisplay` captures the owned view into an explicit RGB bitmap.
- Normal return or thrown capture failure orders out, detaches and closes the window before PNG publication. Crashes/cancellation use owned-process cleanup.
- There is no desktop screenshot, external screenshot application, generated-app capture mode, accessibility traversal or Screen Recording permission requirement.
- This is seeded initial state, not physical interactions or an async-content readiness handshake. PNG creation is distinct from visual fidelity and model inspection.
- Inactive controls may appear subdued. Active accent, dark/Retina appearance, popup/tab interactions and arbitrary layer-backed/media/web content remain unverified. The broader [capture spike](../../../../spike/README.md) records missing unselected tab labels and capsule side-mark artifacts; native capture is not a blanket promise to fix them.

## Results and diagnostics

- `status: rendered` includes summary, width/height and `artifact: {kind: "png", relativePath, reviewPath}`. The service validates a bounded regular nonlinked single PNG, ImageIO decoding and exact requested dimensions before publishing.
- `status: error` contains bounded summary diagnostics and no artifact/dimensions. [PreviewController](../Sources/Application/Controllers/PreviewController.swift) formats discovery errors with code, selected source path, explanation, repair instructions and a guarded example, aligned with the schema-owned tool description.
- `missing_preview`, `ambiguous_preview`, `invalid_preview_factory` and `preview_in_production` describe discovery failures. The last means the factory is present without `MAC_APPER_PREVIEW`, not that Preview was invoked in production.
- Transport/scope/request validation failures remain failed XPC/Pi tool operations, distinct from typed rendering errors. Check `status` separately from transport success or Pi `isError`.
- Preview summaries are schema-bounded to 4096; compiler failure output is compacted and tailed before the controller's bounded diagnostic summary.

## Artifacts and optional inspection

- Successful delivery copy: `<project>/.mac-apper/Artifacts/<request-uuid>/render.png`, returned as project-relative `artifact.relativePath`. It lasts only as long as the project.
- Retained review copy: `~/.mac-apper/previews/<project-id>/<session-id>/preview-<Unix-microseconds>.png`, returned as absolute `artifact.reviewPath`. It survives project/scenario cleanup and has no automatic pruning.
- Request/envelope identities determine project/session paths; the model cannot supply an archive destination. [PreviewArchive](../Sources/Application/PreviewArchive.swift) uses descriptor-relative no-follow traversal and exclusive creation, with new archive directories at 0700 and images at 0600. Timestamp collisions advance one microsecond, with at most 100 attempts and no overwrite.
- Direct and nested Preview carry text/typed metadata through XPC, not image bytes. DevTools deliberately omits `tool.imageArtifact`; its generated extension neither reads nor attaches the PNG. Generic OpenXPC imageArtifact remains opt-in for other contracts.
- Optional inspection uses existing production Pi `read`, preferably the absolute retained review path without cwd dependence. The relative path works while in the project. Optional codemode forwarding is:

  ```ts
  image(await tools.read({path: result.artifact.reviewPath}))
  ```

- No read/forwarding call or tool order is required. Rendering does not establish that a model inspected the image; read's user permissions do not replace service validation or provide a sandbox.
- Agent's independent Pi RPC record bound remains 4 MiB for other tools that may return a 2 MiB base64 PNG; larger aggregates fail, and presentation events retain only text/metadata. This is not DevTools automatic-image delivery.

## Canonical path identity

- PreviewArchive derives the configured root and completed file pathname with `F_GETPATH`, avoiding Foundation resolution that can abbreviate `/private/tmp` to linked `/tmp`.
- Before publication, it reopens every canonical ancestor/leaf with no-follow traversal, checks exact device/inode identity and the expected project/session filename, and preserves kernel spelling without URL standardization. Configured-root semantics are retained rather than admitting arbitrary model-supplied aliases.
- Scenario consumers compare validated existing archive-parent directory identity rather than reconstructed client URL spelling, then strictly no-follow read the unchanged returned path. VisionCLI receives that canonical path without rewriting it.
- These are point-in-time checks, not a filesystem sandbox, an atomic path lease or protection against later rename/replacement or privileged mutation. Consumer complete-PNG-envelope/ancestry audits are additional [scenario evidence](../../../../Agent/README.md), not a claim that service ImageIO checks provide every consumer guarantee.
