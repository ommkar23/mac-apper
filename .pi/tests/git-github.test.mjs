import assert from 'node:assert/strict';
import { readFileSync, existsSync } from 'node:fs';
import { dirname, resolve } from 'node:path';
import { fileURLToPath } from 'node:url';
import test from 'node:test';

const skillPath = fileURLToPath(new URL('../skills/git-github/SKILL.md', import.meta.url));
const load = () => readFileSync(skillPath, 'utf8');
const contracts = [
  /no automatic commit or push/i,
  /Git authorship.*independent.*GitHub authentication/i,
  /existing valid identity and authentication/i,
  /login.*numeric ID/i,
  /no personal.email.*raw.token/i,
  /git config --local user\.name.*<name>/,
  /git config --local user\.email.*<id>\+<login>@users\.noreply\.github\.com/,
  /git var GIT_AUTHOR_IDENT.*git var GIT_COMMITTER_IDENT/,
  /valid.*gh authentication.*fail.*Git credential routing/i,
  /gh auth status --hostname github\.com/,
  /sanitiz.*before.*display.*log/i,
  /no native.*gh push/i,
  /GIT_CONFIG_GLOBAL="<evidence>\/gitconfig"/,
  /GIT_TERMINAL_PROMPT=0.*GH_PROMPT_DISABLED=1/,
  /gh auth setup-git --hostname github\.com/,
  /same scoped environment.*setup.*push.*ls-remote/i,
  /empty helper reset.*gh.*git-credential/i,
  /already.created commit.*preserved/i,
  /never recreated or amended.*authentication recovery/i,
  /unchanged source hashes.*recorded verification/i,
  /no redundant full tests/i,
  /git diff --cached --name-only.*git diff --cached.*git diff --cached --check/,
  /ordinary non.force.*git push <remote> <branch>/i,
  /git ls-remote <remote> refs\/heads\/<branch>/,
  /expected local.*remote branch SHA.*match/i,
  /clean.*explicitly disclosed.*working.tree/i,
  /unrelated work and evidence.*retained/i,
];
const validateContracts = (text) => {
  for (const contract of contracts) assert.match(text, contract);
};

test('portable triggering frontmatter and compact declarative body', () => {
  const text = load();
  assert.match(text, /^---\nname: git-github\ndescription: [^\n]+\n---\n/);
  const description = text.match(/^description: (.+)$/m)[1];
  assert.ok(description.length <= 1024);
  assert.match(description, /Use when.*Git.*GitHub/);
  assert.ok(text.trimEnd().split('\n').length <= 70);
  assert.ok(text.trim().split(/\s+/).length <= 500);
  const body = text.split('---\n')[2];
  assert.ok(body.split('\n').filter(Boolean).every((line) => /^(?:#{1,3} |\s*- )/.test(line)));
});

test('observed identity, authentication routing and publication contracts remain explicit', () => {
  validateContracts(load());
});

test('relative documentation references exist from the skill directory', () => {
  const links = [...load().matchAll(/\]\(([^)]+)\)/g)].map((match) => match[1]);
  assert.ok(links.length >= 1);
  for (const link of links) {
    assert.ok(!/^(?:[a-z]+:|\/)/i.test(link));
    assert.ok(existsSync(resolve(dirname(skillPath), link.split('#')[0])), link);
  }
});

test('skill has placeholders, not session identities, secret values or history', () => {
  const text = load();
  assert.doesNotMatch(text, /\b[a-f\d]{40,64}\b|\b\d{6,}\b|\/[Hh]ome\/|\b(?:gh[pousr]_|github_pat_)[\w]+|Herdr|worker role/);
  const addresses = text.match(/[^\s`"']+@[^\s`"']+/g) ?? [];
  assert.deepEqual(addresses, ['<id>+<login>@users.noreply.github.com']);
});

test('critical recovery omissions are rejected without executing any workflow', () => {
  const text = load();
  for (const fragment of [
    'gh auth setup-git --hostname github.com',
    'GIT_CONFIG_GLOBAL="<evidence>/gitconfig"',
    'never recreated or amended',
    'git var GIT_COMMITTER_IDENT',
    'git ls-remote <remote> refs/heads/<branch>',
  ]) {
    assert.ok(text.includes(fragment));
    assert.throws(() => validateContracts(text.replaceAll(fragment, '[omitted]')));
  }
});
