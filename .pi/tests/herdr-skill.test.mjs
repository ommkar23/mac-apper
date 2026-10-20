import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { test } from 'node:test';
import { spawnSync } from 'node:child_process';

// Documentation regressions only. No Herdr process, pane, model, or network access.
// HERDR_SKILL_FILE permits baseline-vs-final checks against a retained snapshot.
const skill = readFileSync(
  process.env.HERDR_SKILL_FILE ?? new URL('../skills/herdr/SKILL.md', import.meta.url),
  'utf8',
);

const cases = [
  ['C01 background focus and cwd', [
    /pane split --current --direction right --cwd "\$PWD" --no-focus/,
    /pane wait-output/,
    /target's native shell/,
  ]],
  ['C02 exhausted split geometry', [
    /neither direction.*usable/is,
    /do not (?:keep )?split/i,
  ]],
  ['C03 named startup readiness', [
    /agent start reviewer --kind codex --pane/,
    /same pane.*ready for interactive input/s,
    /agent_not_ready/,
    /interactive_ready.*true/i,
  ]],
  ['C04 busy-pane noninterference', [
    /pane process-info --pane/,
    /do not prompt a working agent/i,
  ]],
  ['C05 literal multiline exactly-once submission', [
    /one (?:quoted )?argument/i,
    /<<'HERDR_PROMPT'/,
    /do not.*(?:extra|second).*Enter/i,
  ]],
  ['C06 uncertain delivery recovery', [
    /timeout or stalled response does not prove the prompt was never delivered/i,
    /do not blindly submit it again/i,
    /agent get/,
    /agent read/,
  ]],
  ['C07 blocked is not permission', [
    /agent_blocked/,
    /ask the user before answering/i,
  ]],
  ['C08 missing-response fallback preconditions', [
    /repository.*`\.tmp\/`/i,
    /same.*idle.*done.*(?:occupant|agent)/i,
    /(?:do not|without).*rerun.*original/i,
    /agent_not_idle[\s\S]*?agent read <target> --source visible --lines 35/,
    /do not interrupt or prompt working work/i,
    /defer deeper history recovery until the same agent is idle/i,
  ]],
  ['C09 occupant identity before input', [
    /before (?:each|every).*?(?:input|mutation)/i,
    /terminal_id/,
    /(?:session ID|session identity)/i,
    /(?:changed|mismatch).*?(?:stop|refuse)|(?:stop|refuse).*?(?:changed|mismatch)/i,
  ]],
  ['C10 exact-owned cleanup gating', [
    /pane close <owned-pane-id>/,
    /(?:foreground|child).*?(?:exit|finish|stop)/i,
    /(?:retain|leave).*?(?:uncertain|uncertainty)|(?:uncertain|uncertainty).*?(?:retain|leave)/i,
  ]],
];

for (const [name, contracts] of cases) {
  test(name, () => {
    for (const contract of contracts) {
      assert.ok(contract.test(skill), `Missing documentation contract: ${contract}`);
    }
    if (name.startsWith('C05 ')) {
      // Execute only the documented literal-prompt example against a shell function,
      // not the installed CLI. Nothing touches a pane or starts an agent.
      const example = [...skill.matchAll(/```bash\n([\s\S]*?)```/g)]
        .map((match) => match[1]).find((block) => block.includes("<<'HERDR_PROMPT'"));
      assert.ok(example, 'Literal multiline example is present');
      const content = example.match(/<<'HERDR_PROMPT'\n([\s\S]*?)\nHERDR_PROMPT/)[1];
      const result = spawnSync('/bin/bash', ['--noprofile', '--norc', '-c',
        `herdr() { printf '%s\\0' "$@"; }\n${example}`], {
        encoding: 'utf8', timeout: 2000, maxBuffer: 16 * 1024,
        env: { PATH: '/usr/bin:/bin', HOME: '/SYNTHETIC-NOT-THE-REAL-HOME' },
      });
      assert.equal(result.status, 0, result.stderr);
      assert.equal(result.stderr, '');
      assert.deepEqual(result.stdout.split('\0'), [
        'agent', 'prompt', 'reviewer', content, '--wait', '--timeout', '120000', '',
      ], 'One mock invocation receives one exact multiline argument, not extra Enter');
    }
  });
}
