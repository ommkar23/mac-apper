import assert from 'node:assert/strict';
import { mkdtempSync, mkdirSync, readFileSync, rmSync, symlinkSync, writeFileSync } from 'node:fs';
import { projectTempRoot as tmpdir } from './project-temporary-directory.mjs';
import { join } from 'node:path';
import test from 'node:test';
import { setSwiftFrontmatter, getSwiftFrontmatter, removeSwiftFrontmatter, collectSwiftFrontmatter } from '../lib/swift-frontmatter.ts';

function fixture(run) {
  const root = mkdtempSync(join(tmpdir(), 'frontmatter-write-'));
  try { return run(root); } finally { rmSync(root, { recursive: true, force: true }); }
}

test('writes bounded, delimited Swift comments, preserves content verbatim and replaces idempotently', () => fixture((root) => {
  mkdirSync(join(root, 'Sources'));
  const path = join(root, 'Sources/Example.swift');
  writeFileSync(path, 'import Foundation\n');
  setSwiftFrontmatter(root, { path: 'Sources/Example.swift', content: '// Describes what Example does.\n// Handles input.' });
  const first = readFileSync(path, 'utf8');
  assert.equal(first, '// @frontmatter:start\n// Describes what Example does.\n// Handles input.\n// @frontmatter:end\nimport Foundation\n');
  assert.match(collectSwiftFrontmatter(root), /Sources\/Example.swift\nDescribes what Example does.\nHandles input./);
  setSwiftFrontmatter(root, { path: 'Sources/Example.swift', content: '// Describes what Example does.\n// Handles input.' });
  assert.equal(readFileSync(path, 'utf8'), first);
  setSwiftFrontmatter(root, { path: 'Sources/Example.swift', content: '// Updated.' });
  assert.equal(readFileSync(path, 'utf8'), '// @frontmatter:start\n// Updated.\n// @frontmatter:end\nimport Foundation\n');
  assert.equal(getSwiftFrontmatter(root, 'Sources/Example.swift'), '// Updated.');
  assert.equal(removeSwiftFrontmatter(root, 'Sources/Example.swift'), true);
  assert.equal(readFileSync(path, 'utf8'), 'import Foundation\n');
  assert.equal(getSwiftFrontmatter(root, 'Sources/Example.swift'), undefined);
  assert.equal(removeSwiftFrontmatter(root, 'Sources/Example.swift'), false);
}));

test('preserves SwiftPM directive and upgrades legacy unmarked headers', () => fixture((root) => {
  writeFileSync(join(root, 'Package.swift'), '// swift-tools-version: 6.0\n// Purpose: Old.\n// Boundary: Old.\nimport PackageDescription\n');
  setSwiftFrontmatter(root, { path: 'Package.swift', content: '// Declares the package.' });
  assert.equal(readFileSync(join(root, 'Package.swift'), 'utf8'), '// swift-tools-version: 6.0\n// @frontmatter:start\n// Declares the package.\n// @frontmatter:end\nimport PackageDescription\n');
  assert.equal(getSwiftFrontmatter(root, 'Package.swift'), '// Declares the package.');
  assert.equal(removeSwiftFrontmatter(root, 'Package.swift'), true);
  assert.equal(readFileSync(join(root, 'Package.swift'), 'utf8'), '// swift-tools-version: 6.0\nimport PackageDescription\n');
}));

test('rejects traversal, symlink escape, generated output, malformed existing markers and invalid fields without writing', () => fixture((root) => {
  mkdirSync(join(root, 'Sources'));
  const path = join(root, 'Sources/Example.swift');
  writeFileSync(path, 'import Foundation\n');
  symlinkSync(path, join(root, 'Sources/Link.swift'));
  symlinkSync(tmpdir(), join(root, 'Sources/Outside'));
  for (const candidate of ['../elsewhere.swift', '/tmp/elsewhere.swift', 'Sources/../Sources/Example.swift', 'Sources/Link.swift', 'Sources/Outside/elsewhere.swift', 'dist/Generated.swift', '.pi/F.swift', 'Sources/No.swift', 'Sources/Example.txt']) {
    assert.throws(() => setSwiftFrontmatter(root, { path: candidate, content: '// Unsafe.' }), candidate);
    assert.throws(() => getSwiftFrontmatter(root, candidate), candidate);
    assert.throws(() => removeSwiftFrontmatter(root, candidate), candidate);
  }
  for (const fields of [{}, { content: '' }, { content: 'import Evil' }, { content: '// Valid\nplain text' }, { content: '// @frontmatter:end' }, { content: '// ' + 'a'.repeat(5000) }]) {
    assert.throws(() => setSwiftFrontmatter(root, { path: 'Sources/Example.swift', ...fields }));
  }
  assert.equal(readFileSync(path, 'utf8'), 'import Foundation\n');
  writeFileSync(path, '// @frontmatter:start\n// Purpose: Old.\nimport Foundation\n');
  assert.throws(() => setSwiftFrontmatter(root, { path: 'Sources/Example.swift', content: '// New.' }));
  assert.throws(() => getSwiftFrontmatter(root, 'Sources/Example.swift'));
  assert.throws(() => removeSwiftFrontmatter(root, 'Sources/Example.swift'));
  assert.equal(readFileSync(path, 'utf8'), '// @frontmatter:start\n// Purpose: Old.\nimport Foundation\n');
}));
