# VisionCLI security and integration boundaries

Return to [VisionCLI](README.md) for onboarding and [interface reference](interface.md) for JSON fields and bounds. Repository-wide authorization and retention practices remain owned by [guidance](../.pi/GUIDANCE.yaml), not this document.

## Credentials

- Precedence:
  - A nonempty `GEMINI_API_KEY` in the process environment is used first, including when `--env-file` is supplied. An invalid nonempty environment value fails validation rather than falling back to the file.
  - Otherwise `--env-file /absolute/path/.env` selects a file. Without it, the CLI searches up to eight executable-ancestor locations for a directory named `VisionCLI` containing `Package.swift`, then selects its `.env`.
  - A relocated executable outside that layout requires an exported key or explicit file path. Credentials are not request JSON fields.
- File contract:
  - Nonempty regular UTF-8 file, at most 16 KiB, with no linked path component; current-user ownership and no group/other permission bits are required (0600 is the usual mode).
  - Exactly one `GEMINI_API_KEY=...` assignment is accepted. Blank lines/comments and a single pair of surrounding quotes are allowed; other assignments or duplicates fail.
  - No shell evaluation, interpolation, expansion or credential refresh occurs. Key format is 1–256 UTF-8 bytes of ASCII letters, digits, underscore or hyphen.
- Setup, only when credential operations are authorized:
  - `VisionCLI/.env.example` supplies the placeholder format for a new private local file. Keep the real `.env` private and outside signed hosts; do not copy credentials from shell configuration automatically.
  - `.gitignore` excludes `.env` and `.env.*` except `.env.example`. Exclusion alone is not a permission or confidentiality guarantee.
  - Do not display secret values, dump environment dictionaries, or include credentials in reports.
- `check-config` loads/validates local credentials and reports only source (`environment` or `env_file`) with `networkChecked:false`. It makes no API call and cannot establish account validity, quota, billing or model access. It is still credential access and requires appropriate authorization.

## Image paths and identity

- The CLI loads the selected image before loading credentials and constructing the Gemini client. Local `invalid_image` therefore need not imply any Gemini API call.
- Descriptor-relative `openat` reads reject symlinks in ancestors and the leaf, relative paths, empty/dot/traversal components and control characters; the leaf must be a bounded nonempty regular file.
- Use the private repository-root `.tmp/` for disposable image fixtures and reports. Follow the [temporary-work contract](../README.md#temporary-work). macOS `/tmp` and `/var` remain rejected symlink aliases. Do not use Foundation `resolvingSymlinksInPath()` to obtain canonical review paths because it can abbreviate them back to aliases.
- For a DevTools preview, preserve the returned canonical archived `artifact.reviewPath` unchanged rather than reconstructing it from a client URL or project path. That archive may outlive the generated project; project-relative `artifact.relativePath` does not.
- VisionCLI validates PNG/JPEG bytes, dimensions and SHA-256; callers retain responsibility for approved image selection, project/session scope and comparing returned image identity. It is not a project validator or filesystem sandbox.
- Descriptor/no-follow and identity checks are point-in-time safeguards, not protection against later rename/replacement, concurrent mutation or privileged filesystem changes. A matching hash establishes reviewed bytes, not correctness of the UI.

## Upload and transport

- `verify` makes a review request to `POST https://generativelanguage.googleapis.com/v1beta/interactions` with `x-goog-api-key`, inline base64 image bytes, detected MIME type, context and criteria.
- The client sets `store:false`, `stream:false`, structured JSON `response_format`, no tools and a 4096-token output limit. It accepts completed provider responses only and computes the overall verdict from validated checks.
- `store:false` disables interaction persistence; it is not a promise of no provider retention/data use. Google's service/data-use policies still apply, so approve the actual screenshot and text before uploading sensitive content.
- Ephemeral URLSession disables cache, cookie and credential storage; redirects are refused to prevent forwarding the key to another host.
- Request/resource network timeouts are 90 seconds. Provider response data is capped at 1 MiB and extracted review JSON at 64 KiB. There are no automatic paid retries.
- Sanitized errors omit API keys, raw provider bodies, base64 images and environment dictionaries. Completed results still contain model-generated summaries/evidence that may describe sensitive screenshot content; callers must protect captured output.
- Presence of a key, an earlier pass, or a local build does not authorize a new upload, model/MCP session or authentication probe. Live calls may incur charges; uncertainty and operational failures must not be converted into passes or blindly retried.

## Agent integration boundary

- Agent's Create counter/plan consumers build and preflight the reviewer locally, then stage only its executable into a minimal signed test host, never the private `.env`.
- The caller supplies the credential source: exported `GEMINI_API_KEY` has priority; `AGENT_VISION_ENV_FILE` optionally selects an alternate absolute private file, otherwise the source package's `VisionCLI/.env` is selected. This environment variable belongs to Agent tests, not the standalone CLI's argument parser.
- One integrated pinned-model review uses the last independently validated preview for visible count, control labels and unclipped layout after independent behavior/process checks. The caller verifies request/model/criteria/image identity, aggregate verdict and exit code, treats uncertainty as inconclusive and errors as operational failures.
- Agent's reviewer child uses private bounded temporary I/O, a 120-second deadline and cancellation cleanup. These are caller safeguards, not a total execution deadline built into `vision-cli`.
- [Agent](../Agent/README.md) owns scenario selection, full deadlines, assertions and fixture retention; [Scenario](../Scenario/README.md) owns reusable hosting/isolation support. No orchestration commands or historical live-run transcripts are duplicated here.
- The reviewer contacts Google; that does not prove or change the generated app's offline behavior. Visual review is additional probabilistic evidence, not a replacement for tests, development-process checks, production packaging checks or authorized cleanup.
