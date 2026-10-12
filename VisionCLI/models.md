# VisionCLI model research

Return to [VisionCLI](README.md) for setup and [interface reference](interface.md) for model selection.

## Recorded research — 2026-10-05

The previous module documentation records official Google documentation retrieved through Parallel CLI on 2026-10-05. That is historical research, not a dependency on the retired Parallel CLI or a new lookup in this rewrite. Current CLI recommendations remain a static list:

- **`gemini-3.8-flash`** — stable, latest listed general-purpose Flash (September 2026); default for screenshot review.
- **`gemini-3.5-flash-lite`** — stable (July 2026); lower-latency/cost alternative.
- **`gemini-3.1-pro-preview`** — preview; more reasoning-oriented alternative, not a stable deployment recommendation.

All three document image input and structured JSON output. These are image-understanding models, not image-generation/OCR-specific models. Recommendations are based on documented capabilities, not a screenshot accuracy benchmark. Earlier documentation records live account access for the default only; the two alternatives were not called at that checkpoint. No account/model access was checked during this rewrite. Use an explicit model ID for scenario reproducibility; there is no automatic fallback.

Sources:

- [Model catalog](https://ai.google.dev/gemini-api/docs/models)
- [Gemini 3.8 Flash](https://ai.google.dev/gemini-api/docs/models/gemini-3.8-flash)
- [Gemini 3.5 Flash-Lite](https://ai.google.dev/gemini-api/docs/models/gemini-3.5-flash-lite)
- [Gemini 3.1 Pro preview](https://ai.google.dev/gemini-api/docs/models/gemini-3.1-pro-preview)
- [Image understanding](https://ai.google.dev/gemini-api/docs/image-understanding)
- [Structured output](https://ai.google.dev/gemini-api/docs/structured-output)
- [Interactions overview](https://ai.google.dev/gemini-api/docs/interactions-overview)
- [REST API reference, including response `steps`](https://ai.google.dev/api/interactions-api)

The implemented Gemini client uses Google's **Interactions API**, not a legacy `generateContent` request assembled from old examples: `POST https://generativelanguage.googleapis.com/v1beta/interactions`. The image is inline base64 with its detected MIME type. `response_format` supplies a JSON schema; `store:false`, `stream:false`, no tools, and 4096 maximum output tokens are set explicitly.

## Evidence interpretation

- `vision-cli models` prints the embedded `researchedAt` list without network access; it does not discover models, pricing or current account availability.
- Recommendations describe documented image-input/structured-output capabilities, not screenshot accuracy, latency or cost measurements. Model names/statuses and external documentation may change.
- Earlier standalone review evidence recorded one positive 460×420 counter fixture at `/private/tmp/mac-apper-vision-cli-live-request.json` and `/private/tmp/mac-apper-vision-cli-live-result.json`. These paths are historical references, not files inspected or recreated here.
- Integrated live-run history belongs to the [root overview/evidence index](../README.md) and [Agent](../Agent/README.md), not a duplicate transcript here. A positive fixture does not establish general accuracy or negative/uncertain coverage; historical failures remain failures.
- No web/model research, Gemini call or credential operation was performed for this documentation rewrite. Any fresh research or live comparison needs separate authorization.
