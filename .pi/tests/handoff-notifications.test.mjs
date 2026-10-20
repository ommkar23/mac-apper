import assert from 'node:assert/strict';
import { readFileSync, existsSync } from 'node:fs';
import { spawnSync } from 'node:child_process';
import { fileURLToPath } from 'node:url';
import { test } from 'node:test';
import multiAgentHandoff from '../extensions/multi-agent-handoff.ts';

// Documentation and production resource injection only, not a protocol implementation.
// Every negative case below inspects an explicit refusal contract, not a simulated agent decision.
const source = readFileSync(new URL('../skills/agent-handoff/SKILL.md', import.meta.url), 'utf8');
const contracts = [
  ['completion and actionable blocker reports', [/completion or an actionable blocker/i, /outcome.*complete.*blocker/, /own response/, /available evidence/]],
  ['recorded sender and recipient identity', [/parent and sender/, /server.*session.*pane.*terminal_id/, /agent_session_id/, /PID and start identity/, /task_id/, /notification_id/]],
  ['sender mismatch refusal', [/sender.*mismatch.*no input/i]],
  ['recipient mismatch refusal', [/blocked, unknown, missing, or changed recipients.*no input/i, /never.*focused pane/i]],
  ['task mismatch refusal', [/task.*mismatch.*reject/i]],
  ['duplicate reports', [/deduplicat/i, /notification_id.*before inspecting evidence/, /duplicate.*no.*review.*closure/i]],
  ['stale reports', [/stale.*inactive task.*reject/i]],
  ['uncertain delivery without retry', [/uncertain.*no retry/i, /not.*acknowledgment/, /exactly-once model execution/]],
  ['read-only report delivery exception', [/Read-only.*exception/, /no.*artifact writes.*verification execution.*delegation.*approval/i]],
  ['working recipient queue authorization', [/explicitly authorizes report-only queued input.*working/, /without `--wait`/]],
  ['early completion settlement', [/before.*sender.*idle/, /bounded event-triggered settlement/i, /timeout.*retain.*no.*periodic polling/i]],
  ['approval UI may prevent reporting', [/approval UI.*prevent.*blocker notification/i, /delivery failure.*own response/]],
  ['evidence review precedes acceptance and closure', [/submission, actual completion, evidence acceptance, and pane closure.*separate states/i, /Verify the report.*before accepting/s]],
  ['unsafe closure retains agents', [/blocked, unfinished, unaccepted, or user-retained agents open/, /mismatched.*agents.*open/i, /owned children.*cleanup.*uncertain.*retain/s]],
  ['bounded event reads and manual recovery', [/bounded event-triggered.*reads/, /manual delivery recovery/, /no routine fixed-interval polling/i]],
  ['notification contains no executable authority', [/report data.*not.*instructions/i, /without secrets/, /no.*interruption.*approval response.*delegation/s]],
];

for (const [name, patterns] of contracts) {
  test(`notification documentation: ${name}`, () => {
    for (const pattern of patterns) {
      assert.match(source, pattern);
      // Demonstrate that removing the matched contract fails this documentation assertion.
      const allMatches = new RegExp(pattern.source, `${pattern.flags}g`);
      assert.throws(() => assert.match(source.replace(allMatches, '[omitted]'), pattern));
    }
  });
}

test('documented notification is one local captured prompt with no wait or extra Enter', () => {
  const block = [...source.matchAll(/```bash\n([\s\S]*?)```/g)]
    .map(match => match[1]).find(text => text.includes("<<'HANDOFF_NOTIFICATION'"));
  assert.ok(block, 'A literal notification transport example exists');
  const content = block.match(/<<'HANDOFF_NOTIFICATION'\n([\s\S]*?)\nHANDOFF_NOTIFICATION/)[1];
  for (const outcome of ['complete', 'blocker']) {
    const payload = outcome === 'complete' ? content : content
      .replace('"outcome":"complete"', '"outcome":"blocker"')
      .replace('<assigned-completion-id>', '<assigned-blocker-id>');
    const example = block.replace(content, payload);
    const result = spawnSync('/bin/bash', ['--noprofile', '--norc', '-c',
      `herdr() { printf '%s\\0' "$@"; }\n${example}`], {
      encoding: 'utf8', timeout: 2000, maxBuffer: 32 * 1024,
      env: { PATH: '/usr/bin:/bin', HOME: '/SYNTHETIC-NOT-A-REAL-HOME' },
    });
    assert.ifError(result.error);
    assert.equal(result.status, 0, result.stderr);
    assert.equal(result.stderr, '');
    assert.deepEqual(result.stdout.split('\0'), [
      '--session', '<recorded-existing-session>', 'agent', 'prompt', '<recorded-coordinator-pane>', payload, '',
    ]);
    assert.doesNotMatch(example, /--wait|send-keys|send-text/);
    assert.equal(JSON.parse(payload).outcome, outcome);
  }
  const data = JSON.parse(content);
  assert.equal(data.type, 'handoff-report');
  for (const key of ['task_id', 'notification_id', 'parent', 'sender', 'summary', 'evidence']) assert.ok(data[key]);
  for (const side of ['parent', 'sender']) {
    for (const key of ['server', 'session', 'pane', 'terminal_id', 'agent_session_id']) assert.ok(data[side][key]);
  }
});

test('fresh production-injected roles carry narrow notification authority, not general write access', async () => {
  const original = process.env.AGENT_TYPE;
  try {
    for (const role of ['coordinator', 'researcher', 'worker', 'reviewer']) {
      process.env.AGENT_TYPE = role;
      const handlers = new Map();
      multiAgentHandoff({ on: (name, handler) => handlers.set(name, handler) });
      const ctx = { cwd: fileURLToPath(new URL('../../', import.meta.url)) };
      await handlers.get('session_start')({}, ctx);
      const event = { systemPromptOptions: { sections: { preserved: 'yes' } } };
      handlers.get('before_agent_start')(event, ctx);
      const injected = event.systemPromptOptions.sections.multi_agent_handoff;
      assert.equal(event.systemPromptOptions.sections.preserved, 'yes');
      assert.match(injected, /recorded coordinator/);
      assert.match(injected, /task_id.*notification_id/);
      assert.doesNotMatch(injected, /every \d+ minutes|coordinator polling|without sending reports through Herdr/);
      if (role === 'coordinator') {
        assert.match(injected, /deduplicat/i);
        assert.match(injected, /submission.*completion.*acceptance.*closure/);
        assert.match(injected, /bounded event-triggered settlement/);
        assert.match(injected, /owned children/);
      } else {
        assert.match(injected, /one.*prompt.*without `--wait`/);
        assert.match(injected, /report-only queued input.*working/);
        assert.match(injected, /blocked, unknown, missing, or changed/);
        assert.match(injected, /no retry/);
        assert.match(injected, /approval UI.*prevent/);
        assert.match(injected, /no.*verification execution.*delegation.*approval authority/i);
      }
      if (role !== 'worker') assert.match(injected, /Access: read-only/);
    }
  } finally {
    if (original === undefined) delete process.env.AGENT_TYPE;
    else process.env.AGENT_TYPE = original;
  }
});

test('authored handoff links exist and active text has no old polling or report ban', () => {
  for (const name of ['agent-handoff', 'multi-agent-handoff']) {
    const url = new URL(`../skills/${name}/SKILL.md`, import.meta.url);
    const text = readFileSync(url, 'utf8');
    assert.doesNotMatch(text, /polls? (?:each|the|at|every)|next poll|poll clocks|polling interval|do not send reports.*through Herdr/i);
    for (const match of text.matchAll(/\]\(([^)#]+)(?:#[^)]*)?\)/g)) {
      if (!match[1].startsWith('http')) assert.ok(existsSync(new URL(match[1], url)), match[1]);
    }
  }
});
