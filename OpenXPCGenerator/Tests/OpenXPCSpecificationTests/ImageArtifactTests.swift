import Foundation
import Scenario
import OpenXPCSpecification
import Testing

@Test func generatedImageLoaderReadsScopedPNGAndRejectsUnsafeArtifacts() throws {
	let contract = """
		service:
		  identifier: com.example.images
		  target: ImageService
		  generate: service
		types:
		  - name: Input
		    fields: []
		  - name: Output
		    fields:
		      - { name: path, type: string, maxLength: 4096 }
		operations:
		  - name: image
		    request: Input
		    response: Output
		    tool:
		      label: Image
		      description: Render an image.
		      imageArtifact: path
		clients:
		  - target: ImageAgentClient
		    generate: agentClient
		    operations: [image]
		"""
	let files = try OpenXPCSourceGenerator.generate(
		spec: OpenXPCSpecification(yaml: contract), target: "ImageAgentClient")
	let extensionSource = try #require(files.piExtension)
	let start = try #require(extensionSource.range(of: "import { constants }"))
	let end = try #require(extensionSource.range(of: "async function call("))
	let helper = String(extensionSource[start.lowerBound..<end.lowerBound])
	let root = try ProjectTemporaryDirectory.root().appendingPathComponent(UUID().uuidString)
	try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
	defer { try? FileManager.default.removeItem(at: root) }
	let script = root.appendingPathComponent("image-test.ts")
	let checks = #"""
		const root = process.env.OPENXPC_PROJECT_ROOT!;
		const directory = join(root, ".mac-apper/Artifacts/12345678-1234-1234-1234-123456789abc");
		const relativePath = ".mac-apper/Artifacts/12345678-1234-1234-1234-123456789abc/render.png";
		const fs = await import("node:fs/promises");
		await fs.mkdir(directory, { recursive: true });
		const bytes = Buffer.alloc(33);
		Buffer.from([137,80,78,71,13,10,26,10]).copy(bytes);
		bytes.write("IHDR", 12); bytes.writeUInt32BE(64, 16); bytes.writeUInt32BE(64, 20);
		await fs.writeFile(join(root, relativePath), bytes);
		const image = await imageArtifact({ path: relativePath, width: 64, height: 64 }, "path");
		if (image.type !== "image" || image.mimeType !== "image/png" || image.data !== bytes.toString("base64")) throw Error("bad content");
		async function reject(value: unknown, field = "path") {
		  try { await imageArtifact(value, field); } catch { return; }
		  throw Error("accepted invalid artifact");
		}
		await reject({ path: "../render.png" });
		await reject({ path: relativePath, width: 65 });
		await reject({ summary: "missing_preview" });
		await fs.writeFile(join(root, relativePath), Buffer.alloc(33));
		await reject({ path: relativePath });
		await fs.writeFile(join(root, relativePath), Buffer.alloc(2097153));
		await reject({ path: relativePath });
		await fs.unlink(join(root, relativePath));
		const external = join(root, "external.png");
		await fs.writeFile(external, bytes);
		await fs.symlink(external, join(root, relativePath));
		await reject({ path: relativePath });
		await fs.unlink(join(root, relativePath));
		await fs.rmdir(directory);
		const externalDirectory = join(root, "external-dir");
		await fs.mkdir(externalDirectory); await fs.writeFile(join(externalDirectory, "render.png"), bytes);
		await fs.symlink(externalDirectory, directory);
		await reject({ path: relativePath });
		console.log("image-artifact-checks-passed");
		"""#
	try (helper + "\n" + checks).write(to: script, atomically: true, encoding: .utf8)
	let process = Process()
	process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
	process.arguments = ["node", "--experimental-strip-types", script.path]
	var environment = ProcessInfo.processInfo.environment
	environment["OPENXPC_PROJECT_ROOT"] = root.path
	process.environment = environment
	let output = Pipe()
	process.standardOutput = output
	process.standardError = output
	try process.run()
	let diagnostics = String(
		decoding: output.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
	process.waitUntilExit()
	#expect(process.terminationStatus == 0, "\(diagnostics)")
	#expect(diagnostics.contains("image-artifact-checks-passed"))
}
