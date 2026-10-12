import {
  createCodemodeExtension,
  createMcpExtension,
  type ExtensionAPI,
} from "@earendil-works/pi-coding-agent";
import { fileURLToPath } from "node:url";

// These static tool keys normalize to the working session's web_search/web_fetch exposure.
// Keep Pi's default transport, authentication, discovery and failure handling.
export default async function parallelCodemode(pi: ExtensionAPI) {
  await createCodemodeExtension({ mode: "on", models: false })(pi);
  await createMcpExtension({
    loadConfig: () => ({
      servers: [{
        name: "parallel",
        source: fileURLToPath(import.meta.url),
        scope: "extension",
        config: {
          url: "https://search.parallel.ai/mcp",
          exposure: "hidden",
          toolExposure: {
            web_search: "codemode",
            web_fetch: "codemode",
          },
        },
      }],
      errors: [],
    }),
  })(pi);
}
