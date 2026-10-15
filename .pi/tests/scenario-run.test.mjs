import test from 'node:test';
import assert from 'node:assert/strict';
import { spawnSync } from 'node:child_process';
import { mkdtempSync, writeFileSync, readFileSync, rmSync, existsSync, chmodSync } from 'node:fs';
import { homedir } from 'node:os';
import { projectTempRoot as tmpdir } from './project-temporary-directory.mjs';
import { resolve, join } from 'node:path';

const script = resolve('.pi/skills/scenario-run/scripts/scenario-run.swift');
const swift = join(homedir(), 'Library/Developer/Toolchains/swift-6.4.0-RELEASE.xctoolchain/usr/bin/swift');
const root = process.cwd();
process.env.TMPDIR = tmpdir() + '/';
function check(entries, flags = [], command = 'check') {
  const dir = mkdtempSync(join(tmpdir(), 'scenario-run-test-'));
  try {
    const plan = join(dir, 'plan.json');
    writeFileSync(plan, JSON.stringify({ root, entries }));
    return spawnSync(swift, [script, command, plan, ...flags], { encoding: 'utf8', timeout: 30000 });
  } finally { rmSync(dir, { recursive: true, force: true }); }
}
const preview = { package: 'apps/built-in/dev-tools', filter: 'devToolsPreviewScenarios', caseName: 'preview-render' };
const counter = { package: 'Agent', filter: 'agentCreateCounterScenario' };
test('single case and whole collection map to swift test without execution', () => {
  const result = check([preview, { package: 'apps/built-in/dev-tools', filter: 'devToolsPlanScenarios' }]);
  assert.equal(result.status, 0, result.stderr);
  assert.match(result.stdout, /DEV_TOOLS_SCENARIO_CASE=preview-render/);
  assert.match(result.stdout, /--filter devToolsPlanScenarios/);
  assert.match(result.stdout, /CHECK ONLY/);
});
test('mixed sequential plan requires explicit live authorization', () => {
  assert.notEqual(check([preview, counter]).status, 0);
  const result = check([preview, counter], ['--authorize-live']);
  assert.equal(result.status, 0, result.stderr);
  assert.match(result.stdout, /AGENT_SCENARIO_LIVE=1/);
});
test('HTView selection requires live authorization and maps to its exact filter', () => {
  const htview = { package: 'Agent', filter: 'agentCreateHTViewScenario' };
  assert.notEqual(check([htview]).status, 0);
  const result = check([htview], ['--authorize-live']);
  assert.equal(result.status, 0, result.stderr);
  assert.match(result.stdout, /AGENT_SCENARIO_LIVE=1/);
  assert.match(result.stdout, /--filter agentCreateHTViewScenario/);
  assert.match(result.stdout, /CHECK ONLY/);
  assert.notEqual(check([{ ...htview, caseName: 'create-htview' }], ['--authorize-live']).status, 0);
});
test('start refuses unauthorized paid plan before launch', () => {
  const result = check([counter], [], 'start');
  assert.notEqual(result.status, 0);
  assert.match(result.stderr, /authorization/);
});
test('invalid selectors, duplicate selections, empty plans and unrelated filters fail closed', () => {
  for (const entries of [[], [{ ...preview, caseName: 'not-a-case' }], [preview, preview],
    [{ ...counter, caseName: 'preview-render' }], [{ package: 'Agent', filter: '.*' }],
    [{ ...preview, package: '../Agent' }], [{ ...preview, environment: { SDKROOT: '/bad' } }]]) {
    assert.notEqual(check(entries, ['--authorize-live']).status, 0, JSON.stringify(entries));
  }
});
test('resource gate is explicit and inherited selectors do not determine the plan', () => {
  const result = check([{ package: 'Agent', filter: 'agentBundledResourceScenario' }]);
  assert.equal(result.status, 0, result.stderr);
  assert.match(result.stdout, /AGENT_RESOURCE_SCENARIO=1/);
  assert.doesNotMatch(result.stdout, /AGENT_SCENARIO_LIVE=1/);
});
test('status uses only the supplied run and bounds optional log output', () => {
  const dir = mkdtempSync(join(tmpdir(), 'scenario-run-status-test-'));
  try {
    writeFileSync(join(dir, 'state.json'), JSON.stringify({ phase: 'failed', index: 1, total: 2,
      started: 0, updated: 0, exitCode: 1 }));
    writeFileSync(join(dir, 'selection-1.log'), 'PRIVATE_PREFIX_NOT_IN_TAIL\n' + 'z'.repeat(8000) + '\nCASE_FAILED');
    const result = spawnSync(swift, [script, 'status', dir, '--tail'], { encoding: 'utf8', timeout: 30000 });
    assert.equal(result.status, 0, result.stderr);
    assert.match(result.stdout, /phase=failed selection=1\/2/);
    assert.match(result.stdout, /CASE_FAILED/);
    assert.doesNotMatch(result.stdout, /PRIVATE_PREFIX_NOT_IN_TAIL/);
    assert.ok(result.stdout.length < 4600);
    assert.match(result.stdout, /not a scenario pass/);
  } finally { rmSync(dir, { recursive: true, force: true }); }
});
test('supervisor executes sequentially and stops on failure without retries', () => {
  for (const [executable, expected, phase] of [['/usr/bin/false', 1, 'failed'], ['/usr/bin/true', 2, 'commands-completed']]) {
    const dir = mkdtempSync(join(tmpdir(), 'scenario-run-supervisor-test-'));
    try {
      // A private prepared fixture injects a harmless process, never a scenario or Pi executable.
      writeFileSync(join(dir, 'plan.json'), JSON.stringify({ plan: { root, entries: [preview,
        { package: 'apps/built-in/dev-tools', filter: 'devToolsPlanScenarios' }] },
        swift: executable, authorizedLive: false }));
      const result = spawnSync(swift, [script, 'worker', dir], { encoding: 'utf8', timeout: 30000 });
      assert.equal(result.status, 0, result.stderr);
      const state = JSON.parse(readFileSync(join(dir, 'state.json'), 'utf8'));
      assert.equal(state.phase, phase);
      assert.equal(state.index, expected);
      assert.equal(existsSync(join(dir, 'selection-2.result.json')), expected === 2);
    } finally { rmSync(dir, { recursive: true, force: true }); }
  }
});
test('worker clears inherited Vision products without exposing arbitrary plan overrides', () => {
  const dir = mkdtempSync(join(tmpdir(), 'scenario-run-vision-environment-'));
  try {
    // This injected command prints only a synthetic environment; it ignores swift test arguments.
    const fixture = join(dir, 'environment-fixture');
    writeFileSync(fixture, '#!/bin/sh\n/usr/bin/env\n');
    chmodSync(fixture, 0o700);
    writeFileSync(join(dir, 'plan.json'), JSON.stringify({ plan: { root, entries: [preview] },
      swift: fixture, authorizedLive: false }));
    const result = spawnSync(swift, [script, 'worker', dir], { encoding: 'utf8', timeout: 30000,
      env: { HOME: homedir(), PATH: '/usr/bin:/bin', TMPDIR: tmpdir() + '/',
        AGENT_VISION_PRODUCTS: '/must-not-inherit-vision', AGENT_SCENARIO_VISION_CLI: '/hosted-only' } });
    assert.equal(result.status, 0, result.stderr);
    const log = readFileSync(join(dir, 'selection-1.log'), 'utf8');
    assert.doesNotMatch(log, /AGENT_VISION_PRODUCTS|must-not-inherit-vision|AGENT_SCENARIO_VISION_CLI|hosted-only/);
    assert.match(log, /DEV_TOOLS_SCENARIO_CASE=preview-render/);
    assert.notEqual(check([{ ...preview, environment: { AGENT_VISION_PRODUCTS: '/arbitrary' } }]).status, 0);
  } finally { rmSync(dir, { recursive: true, force: true }); }
});
test('worker cannot replay an already-started run', () => {
  const dir = mkdtempSync(join(tmpdir(), 'scenario-run-worker-test-'));
  try {
    writeFileSync(join(dir, 'worker.started'), '');
    const result = spawnSync(swift, [script, 'worker', dir], { encoding: 'utf8', timeout: 30000 });
    assert.notEqual(result.status, 0);
    assert.match(result.stderr, /already started/);
  } finally { rmSync(dir, { recursive: true, force: true }); }
});
test('split skills exist and old skill is retired', () => {
  for (const name of ['scenario-run', 'scenario-write']) {
    const skill = readFileSync(`.pi/skills/${name}/SKILL.md`, 'utf8');
    assert.match(skill, new RegExp(`^---\\nname: ${name}\\ndescription: .+\\n---`));
  }
  assert.equal(existsSync('.pi/skills/scenario/SKILL.md'), false);
  for (const path of ['AGENTS.md', 'README.md']) {
    const doc = readFileSync(path, 'utf8');
    assert.ok(doc.includes('.pi/skills/scenario-run/SKILL.md'));
    assert.ok(doc.includes('.pi/skills/scenario-write/SKILL.md'));
    // README preserves historical failure references; active instructions must use the new skills.
    if (path === 'AGENTS.md') assert.ok(!doc.includes('.pi/skills/scenario/SKILL.md'));
  }
});
