import assert from 'node:assert/strict';
import { mkdtempSync, mkdirSync, writeFileSync, rmSync, symlinkSync } from 'node:fs';
import { projectTempRoot as tmpdir } from './project-temporary-directory.mjs';
import { join } from 'node:path';
import test from 'node:test';
import { collectSwiftFrontmatter } from '../lib/swift-frontmatter.ts';

function fixture(run) {
  const root = mkdtempSync(join(tmpdir(), 'swift-frontmatter-'));
  try { run(root); } finally { rmSync(root, { recursive: true, force: true }); }
}

test('collects only marked top-of-file Swift headers with relative paths in stable order', () => fixture((root) => {
  mkdirSync(join(root, 'Agent/Sources'), { recursive: true });
  writeFileSync(join(root, 'Agent/Sources/B.swift'), '// @frontmatter:start\n// Purpose: Handles B.\n// Boundary: No network.\n// @frontmatter:end\nimport Foundation\n');
  writeFileSync(join(root, 'Agent/Sources/A.swift'), '// @frontmatter:start\n// Purpose: Handles A.\n// @frontmatter:end\nimport Foundation\n');
  writeFileSync(join(root, 'Agent/Package.swift'), '// swift-tools-version: 6.0\n// @frontmatter:start\n// Purpose: Defines the package.\n// @frontmatter:end\nimport PackageDescription\n');
  writeFileSync(join(root, 'Agent/Sources/NoHeader.swift'), 'import Foundation\n// Purpose: Not a header.\n');
  writeFileSync(join(root, 'Agent/Sources/Other.txt'), '// Purpose: Not Swift.\n');
  const result = collectSwiftFrontmatter(root);
  assert.match(result, /Agent\/Package.swift\nPurpose: Defines the package\./);
  assert.ok(result.indexOf('Package.swift') < result.indexOf('Sources/A.swift'));
  assert.match(result, /Sources\/B.swift\nPurpose: Handles B\.\nBoundary: No network\./);
  assert.doesNotMatch(result, /NoHeader|Other.txt|Not a header/);
}));

test('collects marked real project briefs without the SwiftPM directive', () => {
  const root = new URL('../..', import.meta.url).pathname.replace(/\/$/, '');
  const briefs = collectSwiftFrontmatter(root);
  assert.match(briefs, /Agent\/Sources\/Application\/AppName.swift\n/);
  assert.doesNotMatch(briefs, /swift-tools-version:/);
});

test('does not follow symlinks or include build output', () => fixture((root) => {
  mkdirSync(join(root, 'Sources'));
  mkdirSync(join(root, 'dist'));
  writeFileSync(join(root, 'Sources/Real.swift'), '// @frontmatter:start\n// Purpose: Real.\n// @frontmatter:end\n');
  writeFileSync(join(root, 'dist/Generated.swift'), '// Purpose: Generated.\n');
  symlinkSync(join(root, 'dist/Generated.swift'), join(root, 'Sources/Link.swift'));
  assert.match(collectSwiftFrontmatter(root), /Sources\/Real.swift/);
  assert.doesNotMatch(collectSwiftFrontmatter(root), /Generated|Link/);
}));
