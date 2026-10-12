# App packaging and owned output

Return to the [tooling introduction](README.md). These commands package Mac Apper itself, not a generated project's production app or a scenario host.

## Bundle and unbundle

- Initialize `swift64` as shown in the [setup](README.md#setup-and-quick-commands), then run from the repository root only with authorization.

```sh
"$swift64" package --disable-sandbox bundle app
"$swift64" package --disable-sandbox unbundle app

# App-only usage; help branches return before assembly/removal.
"$swift64" package bundle --help
"$swift64" package unbundle --help
```

- Disabled plugin sandboxing permits nested build/packaging work and owned-directory writes; it is not a security boundary for the app or generated code.
- Bundle requires executable standalone Swift 6.4.0 `swift` and `swiftc`, checks the app definition and builds release Agent client/service products with two jobs and `SWIFT_EXEC` pinned to that compiler.
- [Bundle.yaml](../Bundles/app/Bundle.yaml) declares fixed Chat/Create agents, DevTools and the AgentMacosClient product; [Info.plist](../Bundles/app/Info.plist) supplies `com.ommkar.mac-apper`.
- [Integration generation](../Scripts/generate-integration.swift) creates the catalog; [provider packaging](../Scripts/package-providers.swift) builds/stages declared provider applications, services, generated clients and extensions.
- `MAC_APPER_SIGNING_IDENTITY` selects a signing identity; the default is ad-hoc (`-`). Assembly invokes codesign verification and plist linting, but a completed build/static check alone does not prove GUI, XPC resource lookup or tool/model workflows.

## Artifact ownership

- Reusable app: `dist/com.ommkar.mac-apper/Mac Apper.app`.
- Owned release scratch: `dist/com.ommkar.mac-apper/build/`, including Agent client/service and provider scratch.
- Generated catalog/extension copies: `dist/com.ommkar.mac-apper/build/generated/`, not a root `Generated/` directory.
- Bundle replacement and unbundle removal are limited to the marked `dist/com.ommkar.mac-apper/` directory.
  - Both require the expected `.bundle-owner` marker and reject unsafe linked ownership paths and detected executable commands under the owned directory.
  - Quit older instances and owned executables before replacing/removing it. Detection is a point-in-time process-list check, not atomic protection against subsequent launches.
  - Unbundle removes the owned build/generated output along with the app; it is not just removal of the `.app`.
  - Neither command removes historical scenario dist artifacts, unrelated outputs, generated projects, histories or logs.
- Do not hand-edit built/signed contents. The [conventions](../.pi/CONVENTIONS.yaml) owns authored/generated file boundaries and retention; [guidance](../.pi/GUIDANCE.yaml) owns release/runtime verification.

## Resource and runtime boundaries

- Host resources live in `Mac Apper.app/Contents/Resources`; the Agent SwiftPM runtime resource bundle is also staged in `Contents/XPCServices/AgentXPCService.xpc/Contents/Resources` for service-local `Bundle.module` lookup.
  - The host copy alone is insufficient for the service executable.
- DevTools is packaged beneath `Contents/Applications/DevTools.app` with its service/client/resources. Details belong to [DevTools](../apps/built-in/dev-tools/README.md); Agent runtime behavior belongs to [Agent](../Agent/README.md).
- Package-local scenarios stage minimal signed dependencies through [Scenario](../Scenario/README.md), not a full Mac Apper bundle.
- Opening is a separate authorized runtime action, not part of static documentation verification:

```sh
# Only after approved GUI/service-home isolation and runtime authorization.
open 'dist/com.ommkar.mac-apper/Mac Apper.app'
```

- `open -n` deliberately creates another instance; it is not a workaround for an in-use bundle.
- Client-only HOME overrides do not establish launchd service-home isolation before automatic workspace reads. Consult the root overview and guidance for the original-product GUI gate; do not alter global configuration or signed contents to bypass it.

## Recorded evidence versus this rewrite

- Learnings records a historical nested SwiftPM `sandbox_apply` failure and the disabled-sandbox recovery, plus an in-use bundle-removal failure followed by the ownership/process check.
- Historical static signing passed before service-local resource lookup failed; the later placement repair had separate no-model XPC evidence. These are recorded checkpoints, not tests repeated here.
- This rewrite inspected source contracts only. Assembly, signing, unbundle removal, GUI startup and release/runtime paths were not exercised.
