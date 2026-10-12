// @frontmatter:start
// Generates bounded project-scoped PNG loading and Pi image-content conversion for declared artifact responses.
// @frontmatter:end
import Foundation

extension OpenXPCFunctionalGenerator {
	static var piImageArtifactSource: String {
		#"""
		import { constants } from "node:fs";
		import { open, lstat, realpath } from "node:fs/promises";
		import { join } from "node:path";
		async function imageArtifact(result: unknown, field: string) {
		  let value: any = result;
		  for (const component of field.split(".")) value = value?.[component];
		  if (typeof value !== "string")
		    throw new Error((result as any)?.summary ?? "Missing image artifact.");
		  const root = process.env.OPENXPC_PROJECT_ROOT;
		  if (!root || !root.startsWith("/") ||
		      !/^\.mac-apper\/Artifacts\/[0-9a-f-]{36}\/render\.png$/.test(value))
		    throw new Error("Invalid image artifact scope.");
		  const canonical = await realpath(root);
		  let path = canonical;
		  for (const component of value.split("/")) {
		    path = join(path, component);
		    const info = await lstat(path);
		    if (info.isSymbolicLink()) throw new Error("Linked image artifact.");
		  }
		  if ((await realpath(path)) !== path) throw new Error("Aliased image artifact.");
		  const file = await open(path, constants.O_RDONLY | constants.O_NOFOLLOW);
		  try {
		    const info = await file.stat();
		    if (!info.isFile() || info.size < 33 || info.size > 2097152)
		      throw new Error("Invalid image artifact size.");
		    const data = Buffer.alloc(info.size);
		    let offset = 0;
		    while (offset < data.length) {
		      const read = await file.read(data, offset, data.length - offset, offset);
		      if (!read.bytesRead) throw new Error("Incomplete image artifact.");
		      offset += read.bytesRead;
		    }
		    if ((await file.stat()).size !== info.size ||
		        !data.subarray(0, 8).equals(Buffer.from([137,80,78,71,13,10,26,10])) ||
		        data.toString("ascii", 12, 16) !== "IHDR")
		      throw new Error("Invalid PNG artifact.");
		    const width = data.readUInt32BE(16), height = data.readUInt32BE(20);
		    if (width < 64 || width > 2048 || height < 64 || height > 2048 ||
		        width * height > 2097152 ||
		        ((result as any)?.width != null && (result as any).width !== width) ||
		        ((result as any)?.height != null && (result as any).height !== height))
		      throw new Error("Invalid PNG dimensions.");
		    return { type: "image" as const, data: data.toString("base64"), mimeType: "image/png" };
		  } finally { await file.close(); }
		}
		"""#
	}
}
