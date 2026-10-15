import type { ExtensionAPI } from "@earendil-works/pi-coding-agent";

export default function createAppInstruction(pi: ExtensionAPI) {
  pi.on("before_agent_start", async (event) => ({
    systemPrompt: `${event.systemPrompt}\n\nThis is the first request for a newly created app. Infer a concise, appropriate app name from the user's request and call set_app_name exactly once before implementation. This generated DevTools tool updates project naming metadata only; it does not build or package the app. The native rename action separately rebuilds and repackages the production app.`,
  }));
}
