# VisionCLI interface reference

Return to [VisionCLI](README.md) for build/offline checks, authorization and navigation. This document owns the standalone JSON protocol; Agent owns scenario-specific review criteria and execution.

## Invocation

These commands require explicit authorization for a live upload; run from the repository root after building the executable.

```sh
VisionCLI/.build/release/vision-cli verify < request.json
# Or explicitly select a private credential file:
VisionCLI/.build/release/vision-cli verify --env-file /absolute/path/.env < request.json
```

Send **one JSON object on stdin, then close stdin**. stdout contains exactly one JSON result line; SwiftPM build diagnostics are avoided by invoking the built executable in scenarios. Formal schemas: [`Schemas/request.schema.json`](Schemas/request.schema.json) and [`Schemas/response.schema.json`](Schemas/response.schema.json).

Example request (replace the image path with an existing absolute path):

```json
{
  "version": 1,
  "requestID": "76ec7b0f-a6ea-4bc5-9570-0a4c82745524",
  "imagePath": "/Users/you/.mac-apper/previews/project/session/preview.png",
  "model": "gemini-3.8-flash",
  "context": "A native macOS counter app; review only its visible appearance.",
  "criteria": [
    {"id": "count_visible", "description": "A large readable integer count is visible."},
    {"id": "buttons_visible", "description": "Buttons labeled Increment, Decrement, and Reset are legible."},
    {"id": "layout_usable", "description": "The count and controls are not clipped or overlapping."}
  ]
}
```

## Request validation

Request rules:

- `version`, UUID `requestID`, `imagePath`, and `criteria` are required; `context` and `model` are optional (null also allowed). Unknown fields are rejected.
- Model IDs must match `^gemini-[a-z0-9.-]+$` and be ≤128 UTF-8 bytes; the CLI validates syntax, not live model availability. Image paths are ≤4096 UTF-8 bytes.
- Request ≤64 KiB; 1–20 unique criterion IDs, lowercase ASCII letters/digits/underscore/hyphen, beginning with a letter/digit, ≤64 bytes.
- Nonblank criterion descriptions ≤2048 UTF-8 bytes; optional nonblank context ≤4096 bytes. Text permits LF but rejects other control characters. Schema character bounds are supplemented by runtime UTF-8 byte bounds.
- Absolute nonlinked regular PNG/JPEG ≤8 MiB; one image, dimensions 1–8192 and ≤16,777,216 pixels; complete envelope plus successful ImageIO decode required. Image format comes from bytes, not extension. No OCR is run.
- Any linked path component, `.`/`..`, control characters, or empty component is rejected. macOS `/tmp` and `/var` are symlinks: use `/private/tmp` and `/private/var` when constructing temporary paths. Do not use Foundation's `resolvingSymlinksInPath()` to obtain these paths: it can shorten them back to their aliases.

## Results and exit codes

Illustrative completed result (not an actual verification record):

```json
{
  "version": 1,
  "requestID": "76ec7b0f-a6ea-4bc5-9570-0a4c82745524",
  "status": "completed",
  "model": "gemini-3.8-flash",
  "providerModel": "gemini-3.8-flash",
  "verdict": "pass",
  "summary": "The count and controls are clearly visible.",
  "checks": [
    {"id": "count_visible", "verdict": "pass", "evidence": "A large integer appears above the controls."},
    {"id": "buttons_visible", "verdict": "pass", "evidence": "All three requested labels are visible."},
    {"id": "layout_usable", "verdict": "pass", "evidence": "Controls and count have visible margins."}
  ],
  "image": {"width": 460, "height": 420, "sha256": "0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef"}
}
```

Each requested ID must occur exactly once; checks are reordered into request order. Summary/evidence must be nonblank and ≤2048 UTF-8 bytes. The CLI **computes** the overall verdict: any fail → `fail`; otherwise any uncertainty → `uncertain`; otherwise `pass`. Provider failure/incomplete status, missing/duplicate/foreign IDs, malformed JSON, and oversize responses are operational errors, never a UI verdict.

Errors use `{"version":1,"requestID":null,"status":"error","error":{"code":"invalid_request","message":"..."}}`; the ID is included after a request successfully validates. Messages do not contain API keys, raw provider bodies, image base64, or environment dictionaries.

Exit codes:

- **0**: completed, all criteria pass (also successful help/models/config commands).
- **1**: completed, at least one criterion fails.
- **2**: completed, no failures but at least one uncertain criterion.
- **3**: input/configuration/transport/provider/protocol error.

## Consumer responsibilities

- Parse both the result and process exit code; `status: error` has no visual verdict. Distinguish operational failure from `completed`/`fail` and `completed`/`uncertain`.
- Match request UUID, selected `model`, exact criterion IDs, image dimensions and SHA-256 against the submitted input. `providerModel` reports the provider's model ID; the general CLI checks its syntax rather than requiring equality with the selected model. A caller needing exact pinning must check it.
- Enforce a total child-process deadline, bounded output and owned cleanup. The network timeout does not bound stdin waiting for EOF or all local process work.
- Schema string lengths do not replace runtime UTF-8 byte, nonblank/control-character, unique-ID, filesystem and image checks. The current implementation links are in the [module code map](README.md#code-and-documentation-map).
- Keep the canonical archive pathname unchanged when consuming DevTools `artifact.reviewPath`; see [path and privacy boundaries](security.md). VisionCLI accepts ordinary approved PNG/JPEG files too and does not enforce Agent project/session scope itself.
