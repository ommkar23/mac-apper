# DevTools

DevTools is Mac Apper's built-in Create provider for naming, building, testing, launching, previewing and planning generated Swift packages. It is a native XPC service plus a generated Pi terminal client, not a shell tool or a standalone GUI editor.

## Start here

- [Tool execution and results](docs/tools.md): Naming, Build, Test, Run and Plan inputs, scoping, limits and success criteria.
- [SwiftUI Preview](docs/preview.md): factory discovery, isolated compilation, native capture and retained PNG paths.
- [Verification](docs/verification.md): package commands, provider scenarios, recorded evidence and remaining limits.
- [Mac Apper overview](../../../README.md): product setup, authorization and final app delivery.
- [Agent](../../../Agent/README.md): Create instructions, scaffold and production client-model workflows.
- [Scenario](../../../Scenario/README.md): reusable signed-host and lifecycle mechanics.
- [Plugins](../../../Plugins/README.md): product bundling and optional clean-test workflow.
- [VisionCLI](../../../VisionCLI/README.md): optional screenshot review, separate from Preview rendering.

## Setup and first checks

- Use macOS 14+, Apple Command Line Tools with a macOS SDK and the standalone Swift 6.4.0 toolchain. Xcode itself is not required.
- From the repository root, select the driver explicitly; inherited PATH or TOOLCHAINS alone is not proof of compiler selection:

  ```sh
  swift64="$HOME/Library/Developer/Toolchains/swift-6.4.0-RELEASE.xctoolchain/usr/bin/swift"
  "$swift64" --version
  "$swift64" build --package-path apps/built-in/dev-tools
  "$swift64" test --package-path apps/built-in/dev-tools \
    --filter 'DevTools(ContractTests|Tests|XPCServiceTests)'
  ```

- Use default Swift Build, not `--build-system native`. Testing remains pinned to 6.2.3. These are developer commands, not checks executed by this documentation rewrite.
- Production Build/Test/Preview and Run's build phase select home-relative standalone `usr/bin/swift`/`swiftc`, require both executables to exist and be executable, and pin `SWIFT_EXEC` to that compiler. Missing tools fail with the required version/path; no CLT compiler fallback is provided.
- CLT `xcrun` still supplies SDK discovery. Injected test tools keep their own arguments/environment rather than being redirected. Private scenario homes must provide the installed compiler at the expected home-relative location; do not copy a user's configuration tree.
- Build products alone do not establish a self-contained signed provider. Use the selected [provider scenarios](docs/verification.md#provider-scenarios) to exercise real generated-client/XPC calls, and the root product workflow for final delivery when authorized.

## Generated boundary and ownership

- [OpenXPC.yaml](OpenXPC.yaml) owns bounded request/response records and Pi tool descriptions/schemas. [OpenXPCGen.yaml](OpenXPCGen.yaml) selects the service and the six generated terminal operations.
- [Package.swift](Package.swift) declares `DevToolsApplication` and `DevToolsTerminalClient`, attaching OpenXPCBuildPlugin to each. Generated Swift/TypeScript remains in SwiftPM plugin output; [ClientTarget.swift](Sources/AgentClient/ClientTarget.swift) is only the authored target anchor.
- Pi's generated extension injects the selected project root and calls the generated terminal client, which crosses native XPC to the generated listener. Authored [controllers](Sources/Application/Controllers/ControllerFactory.swift) retain project validation, filesystem/process ownership and a shared gate that rejects overlapping operations as busy.
- There is no shared XPC runtime target, native DevTools UI client, authored provider Pi extension or provider-specific client implementation inside Agent. Agent's integration generation assigns DevTools to Create; Chat does not select it.
- Built-in metadata comes from the two OpenXPC files and [bundle plists](Resources/Info.plist), not an AppManifest.yaml. Product packaging places `DevTools.app` under Mac Apper's `Contents/Applications/`, with its owned XPC service, terminal client and generated extension.
- Preview's renderer resource belongs to the service's `Contents/Resources/DevTools_DevToolsApplication.bundle`; deployed lookup must not fall back to source-tree files.

## Six tools

- **Set App Name** (`set_app_name`): update both branding keys in the existing project plist and return the canonical name. This is metadata-only. Native rename and production packaging remain separate.
- **Build** (`build`): debug-build the manifest-selected production executable; does not stage, sign, launch or create a production bundle.
- **Test** (`test`): run all package test targets in disposable scratch; require `status: passed` and `exitCode: 0`, not just tool/transport completion.
- **Run** (`run`): build, stage and launch one development instance per project; launch is not a readiness handshake or production delivery.
- **Preview** (`preview`): render one guarded authored SwiftUI factory and return text-only PNG metadata/paths; no automatic image attachment or proof of model inspection.
- **Plan** (`plan`): mutate a project-scoped in-memory task plan through XPC and return its complete snapshot.

Path checks and tool restrictions are safety boundaries, not a sandbox: generated manifests, source, tests and apps execute with the user's permissions. Pi sessions, live model/MCP/Gemini calls, credential operations, GUI launch and historical cleanup require their own authorization; provider documentation does not grant it.
