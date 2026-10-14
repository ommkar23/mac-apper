import { lstatSync, openSync, closeSync, readSync, readdirSync, readFileSync, writeFileSync } from "node:fs";
import { isAbsolute, join, relative, resolve, sep } from "node:path";

export const start = "// @frontmatter:start";
export const end = "// @frontmatter:end";
const excluded = new Set([".git", ".pi", ".build", "dist", "HostBuilds", "node_modules", ".swiftpm"]);
const maxFiles = 10_000;
const maxContext = 48_000;
const maxHeader = 4096;

export interface FrontmatterInput {
  path: string;
  content: string;
}

function locate(root: string, input: string): string {
  if (!input || isAbsolute(input) || input.includes("\\") || input.includes("\0") || !input.endsWith(".swift")) throw new Error("Expected a project-relative Swift file path");
  const parts = input.split("/");
  if (parts.some(part => !part || part === "." || part === ".." || excluded.has(part))) throw new Error("Invalid project-relative path");
  let cursor = resolve(root);
  for (const part of parts) {
    cursor = join(cursor, part);
    const stat = lstatSync(cursor);
    if (stat.isSymbolicLink()) throw new Error("Symlinks are not allowed");
  }
  if (!lstatSync(cursor).isFile() || lstatSync(cursor).size > 4 * 1024 * 1024) throw new Error("Expected an existing Swift file under 4 MiB");
  return cursor;
}

function makeHeader(input: FrontmatterInput): string {
  const content = input.content;
  if (typeof content !== "string" || !content.trim() || content.includes("\r") || content.includes("\0") || content.split("\n").some((line, index, all) => !line.startsWith("//") && !(line === "" && index === all.length - 1))) throw new Error("Content must be nonempty Swift line comments");
  if (content.split("\n").some(line => line === start || line === end)) throw new Error("Content cannot contain frontmatter markers");
  const result = `${start}\n${content}${content.endsWith("\n") ? "" : "\n"}${end}\n`;
  if (Buffer.byteLength(result) > maxHeader) throw new Error("Frontmatter exceeds 4 KiB");
  return result;
}

function splitHeader(original: string): { directive: string; content?: string; body: string } {
  const directive = original.match(/^(?:\uFEFF)?\/\/ swift-tools-version:[^\r\n]*\r?\n/)?.[0] ?? "";
  const prefix = original.slice(directive.length);
  if (!prefix.startsWith(start + "\n")) {
    if (prefix.startsWith(start) || prefix.startsWith(end) || prefix.includes(`\n${start}\n`) || prefix.includes(`\n${end}\n`)) throw new Error("Frontmatter markers must be at the top of the file");
    return { directive, body: prefix };
  }
  const closing = prefix.indexOf(`\n${end}\n`);
  if (closing < 0 || Buffer.byteLength(prefix.slice(0, closing + end.length + 2)) > maxHeader) throw new Error("Malformed frontmatter markers");
  const content = prefix.slice(start.length + 1, closing);
  if (!content || content.split("\n").some(line => !line.startsWith("//") || line === start || line === end)) throw new Error("Malformed frontmatter content");
  const body = prefix.slice(closing + end.length + 2);
  if (body.startsWith(start) || body.startsWith(end)) throw new Error("Duplicate frontmatter markers");
  return { directive, content, body };
}

export function setSwiftFrontmatter(root: string, input: FrontmatterInput): void {
  const path = locate(root, input.path);
  const header = makeHeader(input);
  const original = readFileSync(path, "utf8");
  const { directive, content, body: existingBody } = splitHeader(original);
  // One-time migration of unmarked headers written before the delimited format.
  const body = content === undefined && existingBody.startsWith("// Purpose: ")
    ? existingBody.replace(/^(?:\/\/ (?:Purpose|Key types|Dependencies|Boundary):[^\r\n]*\r?\n)+/, "")
    : existingBody;
  const updated = directive + header + body;
  if (updated !== original) writeFileSync(path, updated, "utf8");
}

export function getSwiftFrontmatter(root: string, relativePath: string): string | undefined {
  return splitHeader(readFileSync(locate(root, relativePath), "utf8")).content;
}

export function removeSwiftFrontmatter(root: string, relativePath: string): boolean {
  const path = locate(root, relativePath);
  const original = readFileSync(path, "utf8");
  const { directive, content, body } = splitHeader(original);
  if (content === undefined) return false;
  writeFileSync(path, directive + body, "utf8");
  return true;
}

function frontmatter(path: string): string | undefined {
  const bytes = Buffer.alloc(maxHeader);
  const fd = openSync(path, "r");
  let count: number;
  try { count = readSync(fd, bytes, 0, bytes.length, 0); }
  finally { closeSync(fd); }
  const text = bytes.toString("utf8", 0, count).replace(/^\uFEFF/, "");
  const prefix = text.replace(/^\/\/ swift-tools-version:[^\r\n]*\r?\n/, "");
  if (!prefix.startsWith(start + "\n")) return undefined;
  const closing = prefix.indexOf(`\n${end}\n`);
  if (closing < 0) return undefined;
  const body = prefix.slice(start.length + 1, closing).split("\n");
  if (body.some(line => !line.startsWith("//") || line === start || line === end)) return undefined;
  return body.map(line => line.replace(/^\/\/ ?/, "")).join("\n") || undefined;
}

export function collectSwiftFrontmatter(root: string): string {
  const entries: string[] = [];
  let visited = 0;
  let size = 0;
  const walk = (directory: string) => {
    for (const entry of readdirSync(directory, { withFileTypes: true }).sort((a, b) => a.name.localeCompare(b.name, "en"))) {
      if (visited >= maxFiles || size >= maxContext) return;
      if (entry.isSymbolicLink() || excluded.has(entry.name)) continue;
      const path = join(directory, entry.name);
      if (entry.isDirectory()) { walk(path); continue; }
      if (!entry.isFile() || !entry.name.endsWith(".swift")) continue;
      visited++;
      const brief = frontmatter(path);
      if (!brief) continue;
      const text = `${relative(root, path).split(sep).join("/")}\n${brief}`;
      if (size + Buffer.byteLength(text) + 2 > maxContext) return;
      entries.push(text);
      size += Buffer.byteLength(text) + 2;
    }
  };
  walk(root);
  return entries.join("\n\n");
}
