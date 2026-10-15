---
name: new-session-handoff
description: Transfer a context-heavy Pi session to a fresh sibling Pi session with a compact general summary, including when work is complete and no agenda remains, only on explicit user request. Working direction is optional. Not for ordinary delegation, summary-only requests, or creating or editing this skill. Requires HERDR_ENV=1.
---

# New-session handoff

## Authorization and safety
- Execute only on an explicit user request to move into a new session, including switching focus and closing this original pane after acknowledgement.
- Summary-only requests and requests to create, review or edit this skill do not authorize execution.
- Require `test "${HERDR_ENV:-}" = 1`; otherwise stop and report the blocker.
- Read [Herdr](../herdr/SKILL.md) and [agent-handoff](../agent-handoff/SKILL.md) for applicable launch, discovery and safety guidance, not delegation or callback authority. This skill's exact successor-message format supersedes generic prompt formatting.
- Follow the [temporary-work contract](../../../README.md#temporary-work) for inherited `TMPDIR`; never put durable memory in `.tmp/`.
- Before proceeding, establish that active owned processes and staged credentials are already safely resolved or explicitly retained with ownership, safety constraints and follow-up communicated to the successor and user.
- Unsafe or uncertain retention blocks closure. This skill grants no process termination, credential handling, automatic cleanup or directory purge authority.

## Compact inline payload
- Treat the codebase as durable memory. Prepare an inline declarative handoff of **at most ten nonempty logical lines**, one short sentence per line; visual wrapping does not create extra lines.
- A general summary is valid when all work, issues and blockers are complete and no current agenda remains. In that case, lead with completed work and current state; do not invent next tasks or reopen completed work.
- Working direction is optional. Include it only from explicit user instructions or supported session context; leave it absent when neither supplies one. Distinguish an inferred direction from an explicit request and never treat either as permission to act before further user instructions.
- Lead with real priority pending tasks and blockers only when they actually remain; do not bury them under completed work. Otherwise, lead with general completed work and current state.
- Include compact completed work, current state (including actual verification and unverified paths), authorization limits and only essential code/report references as relevant.
- Identify the session's subject or feature/issue when applicable and exact physical cwd. Preserve existing user work and distinguish observed results from historical evidence.
- Omit empty categories, transcript reconstruction, command diaries and exhaustive file lists. Do not create a mandatory handoff archive or dump session history.
- Count the payload before submission and compress it if necessary. Keep payload lines declarative, not commands to continue work.

## Capture and start
1. Discover installed syntax with `herdr --help` and the available `herdr pane` and `herdr agent` groups, including pane `process-info`; never bare `herdr` or argumentless mutating subcommands. No terminal command group is required.
2. Record `cwd=$(pwd -P)` and `herdr pane current --current`. Capture the original workspace/tab/pane and terminal IDs, `herdr agent get <original-pane-id>` metadata, and foreground Pi process identity using pane `process-info` with the discovered exact-pane syntax.
   - Prefer the exposed Herdr `agent_session` as the original session identity. Also record the current caller's inherited `PI_SESSION_ID` directly, without broad environment output; conflicting session identities block transfer.
   - If `agent get` omits `agent_session` for this current caller, require the recorded current-caller pane and terminal IDs, same physical cwd, inherited `PI_SESSION_ID`, and foreground Pi process identity from `process-info` (including PID and available start/executable identity sufficient to detect replacement).
   - The absent field alone is not a blocker when this fallback evidence is sufficient. Conflicting, missing or insufficient caller/process identity evidence remains a blocker. Use returned identifiers, not focused-pane assumptions, sidebar order or a name alone.
3. Follow Herdr's geometry rule to create exactly one sibling shell pane in the current tab, preserving focus: `herdr pane split --current --direction <right-or-down> --cwd "$cwd" --no-focus`.
   - Read the new pane ID from the response. Verify it is distinct, its physical cwd matches, and its shell is ready before starting anything.
4. Start a fresh Pi agent with `herdr agent start <unique-name> --kind pi --pane <new-pane-id>`.
   - Do not reuse an agent, resume/fork old history, create a worktree, change cwd or alter settings/configuration. Preserve the repository's temporary-work setup without changing global configuration.
   - Record the successor's pane, terminal and live agent/session identities from `agent start` and `agent get` responses; require an exposed fresh session distinct from the original and readiness for input. The current-caller fallback never substitutes for the successor's session metadata.

## Submit once and await acknowledgement
- Construct the exact successor message as the literal first line `read, ack and do not act.` followed by a newline and the compact handoff content. The fixed opener is control text, not part of the summary's at-most-ten-nonempty-declarative-line budget.
- The actual submitted message has no outer headings, four-bucket envelope, extra control text, quotes, XML placeholder tags or code fences. Inline backticks here delimit documentation, not submitted message content.
- Submit that exact message once as the message argument to `herdr agent prompt <successor-name> <message> --wait --timeout 120000`, using safe argument quoting rather than evaluating message text as shell code. Shell argument quoting is not part of the submitted message.
- The fixed opener requires the successor to read only the inline handoff, acknowledge receipt and wait for the user. Receipt verification consists only of an actual acknowledgement in the successor's own response; no exact acknowledgement wording is required.
- Authorization excludes successor tools, file reads, edits, tests, delegation and work continuation until a further user request. These are transfer gates for the coordinator, not extra control text to append to the successor message.
- Inspect `herdr agent get <successor-pane-id>` and `herdr agent read <successor-pane-id> --source recent-unwrapped --lines 120` after the wait.
- Require an actual fresh assistant acknowledgement from the same recorded new agent/session, not the echoed prompt, idle status, successful submission or another agent's response. No callback or report file is required.

## Verify, focus, self-close last
1. Re-read both pane records, pane `process-info` and live agent metadata immediately before transfer. Revalidate the original identity branch recorded at capture: matching exposed Herdr session metadata, or, when that field is absent, matching current-caller pane and terminal IDs, physical cwd, inherited `PI_SESSION_ID` and unchanged foreground Pi process identity. Any newly exposed session metadata must agree with the recorded identity; conflicts or insufficient evidence block closure. Require the successor's exposed session and pane/terminal identities to match the recorded fresh agent, same physical cwd and actual matching acknowledgement in a waiting state.
2. Reconfirm the process/credential safety gate above. Report any explicitly retained ownership and limits before closure.
3. Focus only the verified successor with `herdr agent focus <successor-pane-id>`; confirm the focus change and repeat step 1's revalidation of the recorded original identity branch and the successor identity before closing. Do not assume pane-focus syntax accepts an exact ID.
4. As the **final action**, run `herdr pane close <recorded-original-pane-id>` only after every gate passes. Never target the now-focused pane, successor, workspace, tab, server or unrelated pane. Do not schedule tools, cleanup or reporting after self-close.

## Fail closed
- Any startup, approval, submission, identity, missing-ack or unsafe-process blocker preserves the original pane and reports the specific issue there.
- Inspect state/output on a failed or ambiguous submission; never blindly resend, answer approvals, start another successor or choose another closure target.
- Leave newly created panes and existing artifacts intact on failure. No automatic worker/process termination, credential cleanup or directory deletion is implied.
