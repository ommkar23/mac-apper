# OpenXPCGenerator

The single OpenXPC generator package. Its build plugin emits typed controller routing for services and self-contained typed clients from a wire contract (`OpenXPC.yaml`) and a separate target generation configuration (`OpenXPCGen.yaml`). [Agent](../Agent/README.md) uses operation and subscription controllers; [DevTools](../apps/built-in/dev-tools/README.md) uses operation controllers. The standalone Web integration is retired. AgentMacosClientModel uses the same plugin for client-only output. Agent scenarios drive that model with its production native adapter; they do not generate a separate scenario client. DevTools scenarios reuse its existing generated terminal client; historical Web scenarios do not verify the current Agent MCP integration. The specification library retains an explicit handler-dispatch mode for compatibility tests, but the build plugin generates controller dispatch for services.

`Sources/OpenXPCSpecification/Schemas/openxpc.schema.json` defines the wire contract, and `openxpc-gen.schema.json` defines generation configuration. `subscriptions` is optional; declare a nonempty list only for services that push typed events. No `schemaVersion` field is accepted. The strict parser rejects unknown fields, invalid type references, recursive types, and missing bounds. The build-tool plugin reads `OpenXPC.yaml` and its sibling `OpenXPCGen.yaml` and writes generated Swift and TypeScript exclusively into SwiftPM plugin output. A scenario target may point to a provider-owned contract with an authored `OpenXPC.specpath` file in its target directory containing a package-root-relative path; the sibling generation configuration is then read from that provider directory. Both inputs are required and tracked for incremental builds. There is no shared OpenXPC runtime library; generated clients and services are self-contained.

Example `OpenXPC.yaml`:

```yaml
service:
  identifier: com.example.web.xpc
types:
  - name: SearchRequest
    fields:
      - name: query
        type: string
        maxLength: 2048
      - name: limit
        type: int
        optional: true
  - name: SearchResponse
    fields:
      - name: results
        type: string
        array: true
        maxLength: 4096
        maxItems: 10
operations:
  - name: search
    request: SearchRequest
    response: SearchResponse
    tool:
      label: Search
      description: Search the web.
```

`OpenXPCGen.yaml`:

```yaml
service:
  target: WebApplication
  generate: service
clients:
  - target: WebTerminalClient
    generate: agentClient
    operations: [search]
  - target: WebAutomationClient
    generate: client
    operations: [search]
```

Wire identity and size limits remain in `OpenXPC.yaml`; target names, allowed operations and subscriptions, and client timeout belong in `OpenXPCGen.yaml`. Pi tool descriptions and injected request fields remain in the wire contract because they describe the exposed operation and its request shape. Generation profiles are checked against that contract.

Targets and products must still be declared by the consuming package. Attach `OpenXPCBuildPlugin` only to targets named in `OpenXPCGen.yaml`. For a `service` target, the plugin generates the typed XPC protocol, bounded JSON envelope, a dispatching `OpenXPCGeneratedService`, operation controllers (and subscription controllers when declared), and a `Controllers` collection. The XPC service executable calls `OpenXPCGeneratedService.listen(controllers:)` from its authored entry point. `client` generates a typed `OpenXPCGeneratedClient(projectID:sessionID:)` with async-only throwing XPC methods. Generated client calls bridge XPC callbacks with continuations, enforce timeouts, and invalidate their connections on cancellation; no client operation blocks a thread waiting for a reply. `agentClient` generates the same client plus a JSONL terminal `@main` and a working `Extension.ts` that registers Pi tools from each selected operation's `tool` metadata. Its executable target must have a non-`main.swift` authored placeholder and **no other entry point**. The extension expects `OPENXPC_<UPPERCASED_TARGET>_CLIENT_PATH`, `OPENXPC_PROJECT_ID`, and `OPENXPC_SESSION_ID` in Pi's environment. A Pi tool request may declare a required string field `{ name: projectRoot, type: string, maxLength: 4096, injected: projectRoot }`: the generated extension takes it from `OPENXPC_PROJECT_ROOT`, omits it from Pi's tool parameters, rejects a caller-supplied value, and includes it in the typed XPC request. The service must still validate that root independently; the value is not authentication. The client path must resolve to an executable in an appropriately signed app hosting the service; SwiftPM output alone does not register an XPC service. The generated extension must be copied into the signed app's resources by the consuming application's packaging. Neither service nor client authenticates its peer: IDs are scoped request values, not proof of origin. Do not expose privileged operations solely on their basis.

Wire format: one JSON request (`version`, UUID `requestID`, UUID `projectID`, UUID `sessionID`, `command`, base64 `payload`) and one JSON response (`version`, matching `requestID`/`projectID`, `success`, base64 `payload` or `error`); the XPC interface exchanges bounded `Data` with `execute(_:reply:)`. Terminal input/output is a single LF-delimited record. Messages default to 64 KiB, decoded payloads to 32 KiB, and XPC client requests time out after 30 seconds; `service.maxPayloadBytes` in `OpenXPC.yaml` (up to 65,536, increasing the envelope limit to 131,072) and `service.timeoutSeconds` in `OpenXPCGen.yaml` (up to 600) configure larger/longer operations. Controllers receive both IDs and decoded typed input. Clients accept an optional `serviceName` to connect to a collection-specific signed XPC host without changing the provider-owned spec. `tool.description` supports bounded multiline usage examples (1–4096 characters; LF line breaks allowed, other control characters rejected) and is escaped into the generated Pi tool description. An optional `tool.parameters` object can preserve richer provider-authored Pi JSON Schema constraints; its top-level properties and required fields must match the request type. Without `tool.imageArtifact`, generated tools return text and typed details only; DevTools Preview intentionally uses this path-only contract and leaves optional inspection to Pi's existing read tool. Optional `tool.imageArtifact: artifact.relativePath` identifies a response string field (up to four dotted components, no arrays). Generated Pi extensions read that field as a project-relative `.mac-apper/Artifacts/<UUID>/render.png`, reject links/traversal and oversized/invalid PNG headers/dimensions, and return bounded base64 `image/png` content alongside text. Images are limited to 2 MiB and 64-2048 pixels per dimension, with at most 2,097,152 pixels; providers must validate full PNG decoding before returning the descriptor. Missing artifacts throw the response's `summary` diagnostic when available, producing a failed tool result. Image bytes never enter the XPC envelope. The only client generation modes are `client` and `agentClient`.

Optional `subscriptions` entries each have `name`, `request`, `response` (the initial cursor/acknowledgement), and `event` (a typed pushed record); client profiles select them with `subscriptions: [name]` (or omit the field when unused). An `agentClient` profile must not select subscriptions. The generated subscription controller takes an `OpenXPCGeneratedEmitter<Event>` for each subscription: the controller registers an `onClose` callback to detach its server-owned subscriber, optionally emits records using `send(_:)`, and returns the typed acknowledgement. The generated client `subscribeName(_:)` is `async throws` and returns `(Ack, AsyncThrowingStream<Event, Error>)`. Cancel the consuming task or stop consuming to close the XPC connection. Cancellation while awaiting acknowledgement also closes the connection. Each subscription uses a dedicated XPC connection. The client buffers events arriving before the acknowledgement, validates subscription/project/session identities and monotonically increasing transport sequence numbers, and delivers events on a serial queue into a bounded async stream. An interruption, invalidation, malformed event, or cancellation closes the stream exactly once. The service invokes `onClose` exactly once even if the connection dies while the handler is running. Pushed records, the pre-acknowledgement buffer, and error strings are bounded. The service must supply durable domain sequence numbers, cursor-based history paging, replay, and any access control itself; the transport sequence is **not** a replay cursor. Agent's subscription boundary uses these APIs for typed session subscriptions; authored Agent controllers remain responsible for replay and project/session consistency.

The plugin declares both `OpenXPCGenerated.swift` and `Extension.ts` for every configured target. It does not execute the generator (including `--mode` queries) during planning: Swift Build has not built the tool executable at that point. Generation runs as the declared build command with both contracts tracked as inputs. `agentClient` receives the working Pi extension; service/client-only modes receive an inert empty TypeScript resource, not a registered tool extension. Consumers locate resource files with `Bundle.url(forResource:withExtension:)`, supporting macOS bundle layouts rather than assuming a flat `Extension.ts` path. Each target receives types reachable from its permitted operations; the service gets all operations' types. Scalar field types are `string` (`String`), `int` (`Int`), `bool` (`Bool`), `double` (`Double`), `data` (`Data`), and `uuid` (`UUID`), or a named type. `optional: true` and `array: true` may be combined. Strings require `maxLength` (UTF-8 bytes), data requires `maxBytes`, and arrays require `maxItems`. Generated initializers validate those bounds; decoding rejects unknown keys and uses the same validation. Type graphs must be acyclic, so nested decoding terminates. The transport still must bound the overall encoded message. The plugin and generator never write into `Sources/`.

Run `"$HOME/Library/Developer/Toolchains/swift-6.4.0-RELEASE.xctoolchain/usr/bin/swift" test --package-path OpenXPCGenerator` with default Swift Build. A historical checkpoint recorded 26 passing tests under standalone Swift 6.4.0; log: `/private/tmp/mac-apper-swift64-OpenXPCGenerator-suite.log`. See the [root verification archive](../docs/verification-archive.md) for dated context; this documentation rewrite ran no tests. Pinned swift-testing 6.2.3 is unchanged. The earlier native-build workaround is historical, not required; product-bundle rebuilding/startup remains separate.
