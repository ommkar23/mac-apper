---
name: git-github
description: Recover Git authorship and GitHub credential-routing failures safely. Use when authorized Git commits or GitHub publication encounter missing identity or push authentication failures.
---

# Git and GitHub

## Authorization and preconditions
- Loading this skill grants no permission; no automatic commit or push occurs.
- Staging, commits, configuration changes, network/authentication probes and pushes require explicit scope. Missing prerequisites stop publication for user approval.
- Repository, branch, HEAD, fetch/push remote and authorized paths must match expectations; unrelated work and evidence remain retained.
- Matching unchanged source hashes and valid recorded verification permit reuse of prior checks; no redundant full tests are needed for identity/authentication-only recovery.
- [Repository guidance](../../GUIDANCE.yaml) and [temporary-work rules](../../../README.md#temporary-work) apply.

## Git authorship
- Git authorship is independent of GitHub authentication; existing valid identity and authentication are reused, not replaced.
- Missing identity requires an authorized name/email decision. Supplied account login and numeric ID are verified through authorized public metadata; no personal-email or raw-token discovery is needed.
- An authorized repository-local no-reply identity uses `git config --local user.name "<name>"` and `git config --local user.email "<id>+<login>@users.noreply.github.com"`; account/privacy settings remain unchanged. Contribution attribution is not independently guaranteed.
- Effective `git var GIT_AUTHOR_IDENT` and `git var GIT_COMMITTER_IDENT` must match the approved identity before commit, including environment overrides; private evidence records match-only results.

## GitHub credential routing
- Valid existing gh authentication can coexist with failing Git credential routing; an invalid-token push response alone does not prove gh authentication is invalid.
- Authorized `gh auth status --hostname github.com` output is sanitized before display or logging, excluding token lines; token-display flags, raw credential inspection and environment dumps are excluded.
- There is no native `gh push` command; ordinary publication uses Git.
- Authorized routing recovery uses a private UUID-scoped repository `.tmp/` evidence directory, `umask 077`, and temporary `GIT_CONFIG_GLOBAL="<evidence>/gitconfig"`, with `GIT_TERMINAL_PROMPT=0` and `GH_PROMPT_DISABLED=1`.
- The same scoped environment applies to setup, push and ls-remote: `gh auth setup-git --hostname github.com` configures only the temporary global file; `git config --global --get-all credential.https://github.com.helper` confirms an empty helper reset followed by gh `auth git-credential`.
- Existing credentials are consumed in place. Login/logout, token refresh, account switching and permanent configuration changes require separate approval; unresolved authentication stops retries.

## Commit preservation and completion
- An already-created commit is preserved after push failure, never recreated or amended merely for authentication recovery.
- Before an authorized commit: `git diff --cached --name-only`, `git diff --cached` and `git diff --cached --check` confirm only approved paths, privacy and whitespace; disposable evidence and credentials stay unstaged.
- Revalidated branch, HEAD and remote precede ordinary non-force `git push <remote> <branch>`; `git ls-remote <remote> refs/heads/<branch>` uses the same scoped environment.
- Expected local HEAD and remote branch SHA must match. Completion records commands, outcomes, SHA, evidence, blockers and clean or explicitly disclosed working-tree/index status.
- Temporary overrides end with their process; retained evidence is not automatically purged. Historical success is provenance, not a new live check.
