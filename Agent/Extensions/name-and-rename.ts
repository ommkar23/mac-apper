import type { ExtensionAPI } from "@earendil-works/pi-coding-agent";
import { execFile as execFileCallback } from "node:child_process";
import { promisify } from "node:util";
import { mkdir, rm, writeFile, chmod, copyFile } from "node:fs/promises";
import { join, sep } from "node:path";
import { randomUUID } from "node:crypto";

const execFile = promisify(execFileCallback);
const maxOutput = 8000;
const launchServices = "/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister";

function bounded(value: string): string {
  return value.length <= maxOutput ? value : value.slice(value.length - maxOutput);
}

function sanitizeAppName(input: string): string {
  let name = input
    .replace(/[\u0000-\u001f\u007f/\\:]/gu, " ")
    .trim()
    .replace(/\s+/gu, " ");
  while (/\.app$/iu.test(name)) name = name.slice(0, -4).trim();
  if (!name || name === "." || name === ".." || name.startsWith(".") || Array.from(name).length > 64) {
    throw new Error("App name must contain 1 to 64 visible characters.");
  }
  return name;
}

function xml(value: string): string {
  return value.replaceAll("&", "&amp;").replaceAll("<", "&lt;").replaceAll(">", "&gt;").replaceAll('"', "&quot;").replaceAll("'", "&apos;");
}

function decodeNameArgument(argument: string): string {
  if (!argument || !/^[A-Za-z0-9+/]+={0,2}$/u.test(argument)) throw new Error("Rename request is malformed.");
  const bytes = Buffer.from(argument, "base64");
  if (bytes.toString("base64") !== argument) throw new Error("Rename request is malformed.");
  return sanitizeAppName(bytes.toString("utf8"));
}


async function command(executable: string, args: string[], cwd: string, signal?: AbortSignal): Promise<string> {
  const response = await execFile(executable, args, {
    cwd,
    signal,
    maxBuffer: 1024 * 1024,
    encoding: "utf8",
    env: { ...process.env, PATH: "/usr/bin:/bin:/usr/sbin:/sbin:/usr/local/bin" },
  });
  return bounded(`${response.stdout ?? ""}${response.stderr ?? ""}`);
}

async function buildProduct(cwd: string, product: "PreviewApp" | "ProductionApp", signal?: AbortSignal): Promise<{ executable: string; output: string }> {
  const scratch = join(cwd, ".mac-apper", "build", product);
  await mkdir(scratch, { recursive: true, mode: 0o700 });
  const args = ["swift", "build", "-c", "release", "--product", product, "--scratch-path", scratch, "--disable-automatic-resolution", "-j", "2"];
  const output = await command("/usr/bin/xcrun", args, cwd, signal);
  const bin = (await command("/usr/bin/xcrun", ["swift", "build", "-c", "release", "--show-bin-path", "--scratch-path", scratch], cwd, signal)).trim();
  return { executable: join(bin, product), output };
}

async function updateAppName(cwd: string, requestedName: string): Promise<string> {
  const appName = sanitizeAppName(requestedName);
  const settings = join(cwd, "Info.plist");
  await command("/usr/bin/plutil", ["-lint", settings], cwd);
  for (const key of ["CFBundleDisplayName", "CFBundleName"]) {
    await command("/usr/bin/plutil", ["-replace", key, "-string", appName, settings], cwd);
  }
  await command("/usr/bin/plutil", ["-lint", settings], cwd);
  return appName;
}

async function packageProduction(cwd: string, signal?: AbortSignal): Promise<string> {
  const appName = await currentAppName(cwd);
  const built = await buildProduct(cwd, "ProductionApp", signal);
	const outputRoot = process.env.MAC_APPER_OUTPUT_ROOT;
	if (!outputRoot) throw new Error("Mac Apper did not bind the common output folder.");
	const projectID = cwd.split(sep).at(-1)?.toLowerCase().replace(/[^a-z0-9.-]/gu, "-") || randomUUID().toLowerCase();
	const projectOutput = join(outputRoot, projectID);
	const app = join(projectOutput, `${appName}.app`);
	await rm(projectOutput, { recursive: true, force: true });
  await mkdir(join(app, "Contents", "MacOS"), { recursive: true });
  await copyFile(built.executable, join(app, "Contents", "MacOS", "ProductionApp"));
  await chmod(join(app, "Contents", "MacOS", "ProductionApp"), 0o755);

  const escapedName = xml(appName);
  const plist = `<?xml version="1.0" encoding="UTF-8"?>\n<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">\n<plist version="1.0"><dict><key>CFBundleExecutable</key><string>ProductionApp</string><key>CFBundleIdentifier</key><string>com.macapper.generated.${projectID}</string><key>CFBundleDisplayName</key><string>${escapedName}</string><key>CFBundleName</key><string>${escapedName}</string><key>CFBundlePackageType</key><string>APPL</string><key>CFBundleVersion</key><string>1</string><key>LSMinimumSystemVersion</key><string>14.0</string></dict></plist>`;
  await writeFile(join(app, "Contents", "Info.plist"), plist, { mode: 0o600 });
  await command("/usr/bin/codesign", ["--force", "--deep", "--sign", "-", app], cwd, signal);
  await command("/usr/bin/codesign", ["--verify", "--deep", "--strict", app], cwd, signal);
  await command("/usr/bin/plutil", ["-lint", join(app, "Contents", "Info.plist")], cwd, signal);
  await command(launchServices, ["-f", app], cwd, signal);
  return `${appName} rebuilt, packaged, signed, verified, and registered with Launch Services. Artifact: ${app}\n${built.output}`;
}

async function currentAppName(cwd: string): Promise<string> {
  return sanitizeAppName((await command("/usr/bin/plutil", ["-extract", "CFBundleDisplayName", "raw", "-expect", "string", "-o", "-", join(cwd, "Info.plist")], cwd)).trim());
}

export default function macApper(pi: ExtensionAPI) {
  pi.registerCommand("mac-apper-tools", {
    description: "Confirm that the Mac Apper build, preview, and run tools are loaded.",
    handler: async (_args, ctx) => { ctx.ui.notify("Mac Apper tools loaded", "info"); },
  });
  pi.registerCommand("mac-apper-rename", {
    description: "Rebuild, repackage, and register the generated app with a sanitized display name.",
    handler: async (args, ctx) => {
      const appName = await updateAppName(ctx.cwd, decodeNameArgument(args.trim()));
      await packageProduction(ctx.cwd);
      ctx.ui.notify(`MAC_APPER_RENAMED:${Buffer.from(appName, "utf8").toString("base64")}`, "info");
    },
  });
}
