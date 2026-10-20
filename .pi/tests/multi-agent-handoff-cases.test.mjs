import assert from 'node:assert/strict';
import { test } from 'node:test';
import { createHash, randomUUID } from 'node:crypto';
import { spawnSync } from 'node:child_process';
import { mkdirSync, lstatSync, readFileSync, writeFileSync } from 'node:fs';
import { readFile, writeFile } from 'node:fs/promises';
import { dirname, join, resolve } from 'node:path';
import { fileURLToPath } from 'node:url';
import multiAgentHandoff from '../extensions/multi-agent-handoff.ts';
import { projectTempRoot } from './project-temporary-directory.mjs';

// Offline only: documentation checks, real local fixtures, and a handler harness.
// No model decisions, Herdr API calls, agent startup, approvals, or pane closure.
const root = fileURLToPath(new URL('../../', import.meta.url));
const skillPath = process.env.MULTI_AGENT_SKILL_FILE ?? join(root, '.pi/skills/multi-agent-handoff/SKILL.md');
const skill = readFileSync(skillPath, 'utf8');
const cases = JSON.parse(readFileSync(new URL('../skills/multi-agent-handoff/cases.json', import.meta.url), 'utf8'));
const evidence = resolve(process.env.HANDOFF_CASE_EVIDENCE_DIR ?? join(projectTempRoot(), `multi-agent-handoff-${randomUUID()}`));
assert.equal(dirname(evidence), projectTempRoot(), 'Evidence must be a direct private .tmp child');
assert.match(evidence.slice(dirname(evidence).length + 1), /^multi-agent-handoff-[0-9a-f-]{36}$/);
mkdirSync(evidence, { recursive: true, mode: 0o700 });
const info = lstatSync(evidence);
assert.ok(info.isDirectory() && !info.isSymbolicLink() && info.uid === process.getuid() && (info.mode & 0o077) === 0);
const fixtures = join(evidence, `fixtures-${randomUUID()}`);
mkdirSync(fixtures, { mode: 0o700 });
const hash = (value) => createHash('sha256').update(value).digest('hex');

function child(label, args, cwd = fixtures, command = process.execPath) {
  const result = spawnSync(command, args, {
    cwd, encoding: 'utf8', timeout: 3000, maxBuffer: 32 * 1024,
    env: { PATH: '/usr/bin:/bin', HOME: fixtures, TMPDIR: `${fixtures}/` },
  });
  writeFileSync(join(fixtures, `${label}.json`), JSON.stringify({
    command: [command, ...args], cwd, status: result.status, signal: result.signal,
    error: result.error?.message, stdout: result.stdout, stderr: result.stderr,
  }, null, 2));
  assert.equal(result.error, undefined);
  assert.equal(result.signal, null);
  return result;
}

async function roleInstructions(role, mutateAfterLoad) {
  const original = process.env.AGENT_TYPE;
  const handlers = new Map();
  try {
    process.env.AGENT_TYPE = role;
    multiAgentHandoff({ on: (name, handler) => handlers.set(name, handler) });
    if (mutateAfterLoad) process.env.AGENT_TYPE = mutateAfterLoad;
    await handlers.get('session_start')({}, { cwd: root });
    const event = { systemPromptOptions: { sections: { existing: 'preserved' } } };
    handlers.get('before_agent_start')(event, { cwd: root });
    assert.equal(event.systemPromptOptions.sections.existing, 'preserved');
    // The real extension registers handlers only, not a permission-enforcing tool guard.
    assert.deepEqual([...handlers.keys()].sort(), ['before_agent_start', 'resources_discover', 'session_start']);
    return event.systemPromptOptions.sections.multi_agent_handoff;
  } finally {
    if (original === undefined) delete process.env.AGENT_TYPE;
    else process.env.AGENT_TYPE = original;
  }
}

const contracts = {
  C01: [/fresh completion marker and exit status/i, /same.*startup.*identity.*readiness/i],
  C02: [/directory grants include their descendants/i, /source.*artifact ownership/i],
  C03: [/confirm.*affected writers.*finished editing/i, /ownership transfer/i],
  C04: [/dependency launch gate/i, /accepted.*producer.*snapshot/i],
  C05: [/Herdr.*report-file fallback.*read-only/i],
  C06: [/worker loss.*ownership release/i, /cannot rule out.*editing.*escalate/i],
  C07: [/blocked branch.*dependents/i, /without stopping independent work/i, /validates and deduplicates.*before inspecting evidence/i, /bounded event-triggered settlement/i, /no routine fixed-interval polling/i],
  C08: [/dirty.*file hashes/i, /subsequent.*input.*change.*invalidates/i],
  C09: [/Return rejected work to the same worker/, /new four-part task message/, /Review the revised result again/],
  C10: [/remaining.*integration.*available.*worker/i, /pane closure.*evidence deletion/i],
};

const executable = {
  async C01() {
    const result = child('target-shell-inheritance', ['--noprofile', '--norc', '-c',
      'export AGENT_TYPE=worker; export TMPDIR="$PWD/"; printf "role-export-complete:%s\\n" "$?"; "$1" -e \'console.log(JSON.stringify({role:process.env.AGENT_TYPE,tmp:process.env.TMPDIR}))\'',
      'fixture-shell', process.execPath], fixtures, '/bin/bash');
    assert.equal(result.status, 0, result.stderr);
    const lines = result.stdout.trim().split('\n');
    assert.equal(lines[0], 'role-export-complete:0');
    assert.deepEqual(JSON.parse(lines[1]), { role: 'worker', tmp: `${fixtures}/` });
    assert.match(await roleInstructions('reviewer', 'worker'), /^Agent role: reviewer/);
  },
  async C02() {
    const a = join(fixtures, 'Parser.swift');
    const b = join(fixtures, 'ParserTests.swift');
    const shared = join(fixtures, 'Package.swift');
    await writeFile(shared, '// reserved shared manifest\n');
    const before = hash(await readFile(shared));
    await Promise.all([writeFile(a, '// worker A\n', { flag: 'wx' }), writeFile(b, '// worker B\n', { flag: 'wx' })]);
    assert.equal(await readFile(a, 'utf8'), '// worker A\n');
    assert.equal(await readFile(b, 'utf8'), '// worker B\n');
    assert.equal(hash(await readFile(shared)), before);
  },
  async C04() {
    const args = ['--input-type=module', '-e', 'import {schema} from "./producer.mjs"; if (schema !== "v2") process.exit(7);'];
    assert.notEqual(child('dependency-absent', args).status, 0);
    writeFileSync(join(fixtures, 'producer.mjs'), 'export const schema = "v2";\n');
    assert.equal(child('dependency-present', args).status, 0);
  },
  async C05() {
    for (const role of ['coordinator', 'researcher', 'reviewer']) {
      const text = await roleInstructions(role);
      assert.match(text, /Access: read-only/);
      assert.match(text, /Reports stay in agent messages/);
      assert.match(text, /authorized.*workers create any required report files/);
      assert.match(text, /does not.*run tests/s);
    }
    assert.match(await roleInstructions('worker'), /Access: write within assigned files and authorized artifacts/);
  },
  async C07() {
    // Actual production injection; assertions cover instructions, not agent behavior.
    const coordinator = await roleInstructions('coordinator');
    assert.match(coordinator, /deduplicates.*before inspecting evidence/);
    assert.match(coordinator, /bounded event-triggered settlement/);
    assert.match(coordinator, /timeout retains.*without restarting periodic polling/);
    for (const role of ['researcher', 'worker', 'reviewer']) {
      const text = await roleInstructions(role);
      assert.match(text, /completion\/blocker notification_id/);
      assert.match(text, /one identity-validated Herdr agent prompt.*without `--wait`/);
      assert.match(text, /report-only queued input.*working/);
      assert.match(text, /blocked, unknown, missing, or changed recipients receive no input/);
      assert.doesNotMatch(text, /coordinator polling|every [235] minutes/);
    }
  },
  async C08() {
    const source = join(fixtures, 'subject.mjs');
    const check = ['--input-type=module', '-e', 'import assert from "node:assert/strict"; import {parse} from "./subject.mjs"; assert.equal(parse(""), null);'];
    writeFileSync(source, 'export const parse = () => null;\n');
    const before = hash(readFileSync(source));
    assert.equal(child('snapshot-A-passes', check).status, 0);
    assert.equal(hash(readFileSync(source)), before);
    writeFileSync(source, 'export const parse = () => 0;\n');
    const after = hash(readFileSync(source));
    assert.notEqual(after, before);
    assert.notEqual(child('snapshot-B-fails', check).status, 0);
    writeFileSync(join(fixtures, 'snapshot-evidence.json'), JSON.stringify({ before, after, stalePassingEvidence: true }, null, 2));
  },
};

assert.equal(cases.length, 10);
assert.deepEqual(cases.map(({ id }) => id), Object.keys(contracts));
for (const entry of cases) {
  for (const key of ['request', 'expectedDecision', 'baselineObservation', 'correction', 'fidelity', 'limitations']) {
    assert.ok(typeof entry[key] === 'string' && entry[key].length > 40, `${entry.id}: missing ${key}`);
  }
  assert.ok(entry.provenance.length >= 2);
  test(`${entry.id} documentation contract (not an agent decision)`, () => {
    for (const pattern of contracts[entry.id]) assert.match(skill, pattern);
  });
  if (executable[entry.id]) {
    test(`${entry.id} offline fixture: ${entry.fidelity}`, executable[entry.id]);
  }
}

test('case provenance and local skill links resolve without executing resources', async () => {
  for (const entry of cases) {
    for (const reference of entry.provenance) {
      const path = reference.split(': ')[0];
      assert.ok((await readFile(new URL(`../skills/multi-agent-handoff/${path}`, import.meta.url), 'utf8')).length > 0);
    }
  }
  for (const match of skill.matchAll(/\]\(([^)#]+)(?:#[^)]*)?\)/g)) {
    if (match[1].startsWith('http')) continue;
    // Relative links always resolve from the authored skill, including when checking a baseline copy.
    const url = new URL(`../skills/multi-agent-handoff/${match[1]}`, import.meta.url);
    assert.ok(lstatSync(url).isDirectory() || readFileSync(url).length > 0);
  }
});
