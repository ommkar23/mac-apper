import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { createHash } from 'node:crypto';
import { spawnSync } from 'node:child_process';
import { fileURLToPath } from 'node:url';
import { test } from 'node:test';
import { cases } from '../skills/agent-handoff/cases.mjs';

// Offline documentation regressions, never an agent behavioral simulator.
// AGENT_HANDOFF_SKILL_FILE selects a retained baseline/final snapshot.
const sourcePath = process.env.AGENT_HANDOFF_SKILL_FILE
  ?? fileURLToPath(new URL('../skills/agent-handoff/SKILL.md', import.meta.url));
const skill = readFileSync(sourcePath, 'utf8');
const sha256 = createHash('sha256').update(skill).digest('hex');
const blocks = [...skill.matchAll(/```bash\n([\s\S]*?)```/g)].map(match => match[1]);
const root = fileURLToPath(new URL('../../', import.meta.url));

function shell(script, extraEnv = {}) {
  const result = spawnSync('/bin/bash', ['--noprofile', '--norc', '-c', script], {
    encoding: 'utf8', cwd: root, timeout: 2000, maxBuffer: 32 * 1024,
    env: { PATH: '/usr/bin:/bin', HOME: '/SYNTHETIC-NOT-A-REAL-HOME', ...extraEnv },
  });
  assert.ifError(result.error);
  return result;
}

const exercises = {
  'environment-gate'() {
    const gate = skill.match(/`(test "\$\{HERDR_ENV:-\}" = 1)`/)[1];
    const observed = [];
    for (const value of [undefined, '', '0', '1']) {
      const result = shell(gate, value === undefined ? {} : { HERDR_ENV: value });
      assert.equal(result.status, value === '1' ? 0 : 1);
      assert.equal(result.stdout + result.stderr, '');
      observed.push({ value: value ?? '<unset>', exit: result.status });
    }
    return observed;
  },
  'role-shell'() {
    const example = blocks.find(block => block.includes('export AGENT_TYPE=worker'));
    assert.ok(example, 'Target-shell environment example exists');
    // Only exports from reviewed documentation execute; no real Herdr or Pi process.
    assert.ok(example.trim().split('\n').every(line => /^export (AGENT_TYPE|TMPDIR)=/.test(line)));
    const result = shell(`${example}\nprintf '%s\\0' "$AGENT_TYPE" "$TMPDIR"`, {
      AGENT_TYPE: 'coordinator', TMPDIR: '/SYNTHETIC-WRONG-TEMP/',
    });
    assert.equal(result.status, 0, result.stderr);
    assert.equal(result.stderr, '');
    assert.deepEqual(result.stdout.split('\0'), ['worker', `${root.replace(/\/$/, '')}/.tmp/`, '']);
    return { exit: result.status, observedRole: 'worker', tmpdir: 'repository .tmp/', herdrCalls: 0, piStarts: 0 };
  },
  'task-template'() {
    const template = skill.split('Use this prompt shape, replacing placeholders with concrete task intent.')[1]
      .split('### Follow-up message')[0];
    const headings = [...template.matchAll(/^  ([1-4])\. \*\*([^*]+)\*\*$/gm)]
      .map(match => [Number(match[1]), match[2]]);
    assert.deepEqual(headings, [[1, 'What to do'], [2, 'What to verify'], [3, 'What not to do'], [4, 'Others']]);
    assert.match(template, /<task>.*<working directory>/);
    assert.match(template, /<selected checks and toolchain>/);
    assert.match(template, /<unsafe prerequisite or scope conflict>/);
    assert.match(template, /changed paths, commands\/results, evidence, cleanup, blockers, and unverified paths/);
    assert.match(template, /parent and sender identities, task_id, completion and blocker notification_id/);
    assert.match(template, /explicitly authorizes report-only queued input.*working/);
    assert.doesNotMatch(template, /polling|assigned interval/);
    return { headings, limitation: 'Structural template check, not natural-language validation' };
  },
  'literal-prompt'() {
    const example = blocks.find(block => block.includes("<<'HANDOFF_PROMPT'"));
    assert.ok(example, 'Literal prompt example exists');
    const content = example.match(/<<'HANDOFF_PROMPT'\n([\s\S]*?)\nHANDOFF_PROMPT/)[1];
    assert.match(content, /\$HOME/);
    assert.match(content, /\$\(example\)/);
    assert.match(content, /`example`/);
    const result = shell(`herdr() { printf '%s\\0' "$@"; }\n${example}`);
    assert.equal(result.status, 0, result.stderr);
    assert.equal(result.stderr, '');
    assert.deepEqual(result.stdout.split('\0'), ['agent', 'prompt', '<confirmed-name>', content, '']);
    return { exit: result.status, invocations: 1, literalPromptBytes: Buffer.byteLength(content), transport: 'local Bash function only' };
  },
};

assert.equal(cases.length, 10);
assert.equal(new Set(cases.map(item => item.id)).size, 10);
for (const item of cases) {
  test(`${item.id} ${item.name}`, t => {
    const checks = item.contracts.map(contract => ({ contract: String(contract), present: contract.test(skill) }));
    const observation = { kind: 'documentation contract inspection', checks };
    let passed = false;
    try {
      assert.ok(checks.every(check => check.present),
        `Missing documentation contracts: ${checks.filter(check => !check.present).map(check => check.contract).join('; ')}`);
      if (item.executable) observation.execution = exercises[item.executable]();
      passed = true;
    } finally {
      t.diagnostic(JSON.stringify({ id: item.id, request: item.request, expected: item.expected,
        observation, outcome: passed ? 'pass' : 'fail', provenance: item.provenance,
        fidelity: item.fidelity, limitations: item.limitations, sourcePath, sha256 }));
    }
  });
}
