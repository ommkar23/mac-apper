// @frontmatter:start
// Exercises both authored naming entry points and later production branding with offline Node process and filesystem doubles.
// @frontmatter:end
import Foundation
import Testing

@Test func nameAndRenameExtensionPersistsCanonicalBranding() throws {
	let package = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
		.deletingLastPathComponent().deletingLastPathComponent()
	let process = Process(), output = Pipe()
	process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
	process.arguments = [
		"node", "--no-warnings", "--input-type=module", "-e", nameAndRenameNodeRegression,
		package.appendingPathComponent("Extensions/name-and-rename.ts").path,
	]
	process.standardOutput = output
	process.standardError = output
	try process.run()
	let data = output.fileHandleForReading.readDataToEndOfFile()
	process.waitUntilExit()
	try #require(
		process.terminationStatus == 0 && data.count <= 65_536,
		"\(String(decoding: data, as: UTF8.self))")
}

private let nameAndRenameNodeRegression = #"""
	import assert from "node:assert/strict";
	import { readFile } from "node:fs/promises";
	import fs from "node:fs/promises";
	import cp from "node:child_process";
	import { stripTypeScriptTypes, syncBuiltinESMExports } from "node:module";
	import { promisify } from "node:util";
	const source = await readFile(process.argv[1], "utf8");
	const cwd = process.cwd();
	const settings = `${cwd}/Info.plist`;
	const identity = { CFBundleExecutable: "DevelopmentApp", CFBundleIdentifier: "com.fixture.identity",
	  CFBundleVersion: "27", CFBundleShortVersionString: "3.2", AppUUID: "unchanged-app-uuid",
	  DataUUID: "unchanged-data-uuid", Extra: "retain me" };
	let root = { ...identity, CFBundleDisplayName: "Generated App", CFBundleName: "Generated App" };
	const calls = [], writes = [];
	cp.execFile = (executable, args, options, callback) => {
	  calls.push({ executable, args, branding: [root.CFBundleDisplayName, root.CFBundleName] });
	  let stdout = "";
	  try {
	    if (executable.endsWith("PlistBuddy")) {
	      const match = /^Set :(\w+) (.*)$/u.exec(args[1]);
	      assert.ok(match); root[match[1]] = match[2];
	    } else if (executable.endsWith("plutil")) {
	      if (args[0] === "-extract") {
	        if (!(args[1] in root)) throw new Error("Missing plist key");
	        const value = root[args[1]];
	        if (args.includes("-expect")) {
	          assert.equal(args[args.indexOf("-expect") + 1], "string");
	          if (typeof value !== "string") throw new Error("Unexpected plist type");
	        }
	        stdout = String(value);
	      }
	      else if (args[0] === "-replace") {
	        assert.equal(args[2], "-string"); assert.equal(args.at(-1), settings);
	        root[args[1]] = args[3];
	      } else assert.equal(args[0], "-lint");
	    } else if (args.includes("--show-bin-path")) stdout = "/fixture/bin";
	    callback(null, stdout, "");
	  } catch (error) { callback(error); }
	};
	cp.execFile[promisify.custom] = (executable, args, options) => new Promise((resolve, reject) => {
	  cp.execFile(executable, args, options, (error, stdout, stderr) => {
	    if (error) reject(error); else resolve({ stdout, stderr });
	  });
	});
	for (const name of ["mkdir", "rm", "chmod", "copyFile"]) fs[name] = async () => {};
	fs.writeFile = async (path, contents) => { writes.push({ path, contents }); };
	syncBuiltinESMExports();
	const isolated = stripTypeScriptTypes(source.replace('import { Type } from "typebox";',
	  'const Type = { Object: x => x, String: x => x };') + '\nexport { packageProduction };');
	const { default: extension, packageProduction } = await import(
	  `data:text/javascript;base64,${Buffer.from(isolated).toString("base64")}`);
	const commands = new Map(), tools = new Map(), notices = [];
	extension({ registerCommand: (name, spec) => commands.set(name, spec),
	  registerTool: spec => tools.set(spec.name, spec) });
	process.env.MAC_APPER_OUTPUT_ROOT = "/fixture/output";
	const tool = tools.get("set_app_name");
	const rename = commands.get("mac-apper-rename");
	const ctx = { cwd, ui: { notify: value => notices.push(value) } };
	function verifyRoot(name) {
	  assert.equal(root.CFBundleDisplayName, name, "canonical display name must persist");
	  assert.equal(root.CFBundleName, name, "canonical bundle name must persist");
	  for (const [key, value] of Object.entries(identity)) assert.equal(root[key], value);
	}
	const long = "A".repeat(64);
	assert.equal((await tool.execute("id", { name: long })).isError, undefined);
	verifyRoot(long);
	await packageProduction(cwd);
	assert.ok(writes.at(-1).path.endsWith(`/${long}.app/Contents/Info.plist`), "64-character name must not be truncated");
	const input = '  Full / Name: & "Quotes".app.app  ';
	const canonical = 'Full Name & "Quotes"';
	await rename.handler(Buffer.from(input).toString("base64"), ctx);
	verifyRoot(canonical);
	const lastBuild = calls.findLast(call => call.executable.endsWith("xcrun"));
	assert.deepEqual(lastBuild.branding, [canonical, canonical], "rename must persist before building");
	assert.equal(notices.at(-1), `MAC_APPER_RENAMED:${Buffer.from(canonical).toString("base64")}`);
	await packageProduction(cwd);
	const artifact = writes.at(-1);
	assert.ok(artifact.path.endsWith(`/${canonical}.app/Contents/Info.plist`));
	assert.ok(artifact.contents.includes('<key>CFBundleDisplayName</key><string>Full Name &amp; &quot;Quotes&quot;</string>'));
	assert.ok(artifact.contents.includes('<key>CFBundleName</key><string>Full Name &amp; &quot;Quotes&quot;</string>'));
	assert.ok(artifact.contents.includes('<key>CFBundleExecutable</key><string>ProductionApp</string>'));
	assert.ok(artifact.contents.includes('<key>CFBundleIdentifier</key><string>com.macapper.generated.'));
	assert.ok(artifact.contents.includes('<key>CFBundleVersion</key><string>1</string>'));
	verifyRoot(canonical);
	for (const invalid of ["", " / : ", ".", "..", ".hidden", "B".repeat(65)]) {
	  const before = JSON.stringify(root), count = calls.length;
	  assert.equal((await tool.execute("id", { name: invalid })).isError, true);
	  await assert.rejects(() => rename.handler(Buffer.from(invalid).toString("base64"), ctx));
	  assert.equal(JSON.stringify(root), before);
	  assert.equal(calls.length, count, "invalid names must not invoke subprocesses");
	}
	await assert.rejects(() => rename.handler("not-base64!", ctx));
	root.CFBundleDisplayName = "B".repeat(65);
	const buildCount = calls.filter(call => call.executable.endsWith("xcrun")).length;
	await assert.rejects(() => packageProduction(cwd));
	assert.equal(calls.filter(call => call.executable.endsWith("xcrun")).length, buildCount);
	const typedFailures = [];
	for (const [label, value] of [["numeric", 42], ["Boolean", true], ["missing", undefined]]) {
	  if (value === undefined) delete root.CFBundleDisplayName;
	  else root.CFBundleDisplayName = value;
	  const beforeBuilds = calls.filter(call => call.executable.endsWith("xcrun")).length;
	  const beforeWrites = writes.length;
	  let rejected = false;
	  try { await packageProduction(cwd); } catch { rejected = true; }
	  if (!rejected || calls.filter(call => call.executable.endsWith("xcrun")).length !== beforeBuilds
	      || writes.length !== beforeWrites) typedFailures.push(label);
	}
	assert.deepEqual(typedFailures, [], "non-string or missing canonical branding must fail before build or writes");
	console.log("Both naming entry points, later packaging, invalid names, typed metadata and identity preservation passed.");
	"""#
