---
name: agent-handoff
description: Delegate scoped work to a coding agent through Herdr and poll its progress and final response. Use when the user asks to hand off work or start another agent; requires HERDR_ENV=1.
---

# Agent handoff

## Preconditions
- Delegate only when the user authorizes it.
  - Run `test "${HERDR_ENV:-}" = 1`; if it fails, stop.
  - Read the [Herdr skill](../herdr/SKILL.md), or run `herdr --skill` if unavailable.
  - Discover syntax with `herdr --help` and relevant command groups; never bare `herdr`.
- Apply the [role setup and access rules](../multi-agent-handoff/SKILL.md#agent-role-setup) for project Pi sessions.
  - Roles do not grant task authorization; read-only agents do not implement, run checks or create report artifacts.
  - Workers stay within assigned files and authorized execution; scope conflicts go to the coordinator without bypass.

## Start or reuse
- Record the parent identity with `herdr pane current --current`.
  - Keep its pane ID and agent session identity for safe orchestration.
  - Record each delegated target's server/session, pane ID, `terminal_id`, name, kind, role and cwd.
  - Record its agent session ID when exposed; otherwise retain its process PID and start identity from Herdr process inspection and the OS.
  - Freshly compare that ledger before input, polling or closure; stop on a changed or unconfirmable occupant without guessing a replacement.
- Reuse an idle or done agent only when appropriate; otherwise create a sibling pane.
  - Reuse requires the assigned role, cwd and ownership boundaries to match, with the same confirmed occupant ready for input.
  - The prior task must be completed and accepted, with no unfinished work or cleanup uncertainty carried into the new task.
  - An existing agent with a different role requires an authorized replacement, not a shell export, rename or role change inside the live agent.
  - Confirm readiness, including `interactive_ready=true` when exposed; idle status alone is insufficient.
  - Honor requested direction; otherwise choose right/down to fit the layout.
  - Use `herdr pane split --current --direction right --cwd "$PWD" --no-focus`.
  - Read the returned pane ID; never guess IDs or target the user's focused pane.
  - Inspect the returned pane and foreground process to confirm an available interactive shell, not a running command or unrecognized agent.
  - Establish the role and repository temporary environment in that confirmed available target shell before Pi starts.
  - For a worker at the physical repository root with the existing safe `.tmp/` initialized under the [temporary-work contract](../../../README.md#temporary-work), run these exports through the target's native shell using the discovered `pane run` syntax:

```bash
export AGENT_TYPE=worker
export TMPDIR="$PWD/.tmp/"
```

  - Substitute the assigned role and confirm the shell command completed before starting Pi; setting the coordinator's command environment alone does not configure the target shell.
  - Start with `herdr agent start <unique-name> --kind pi --pane <id>`; honor a different requested kind.
  - Verify the returned name, kind, pane, terminal and interactive readiness before prompting.
  - If startup fails, inspect the original state/output before retrying; never duplicate an uncertain launch or bypass readiness or approval dialogs.

## Handoff message types
- Submit each message once using `herdr agent prompt <name> '<instructions>'` after the identity and readiness checks.
  - Multiline prompts travel as one quoted argument, not line-by-line input or shell-interpolated source; do not send an extra Enter.
  - Use the literal example below with a delimiter absent from the concrete prompt; command substitution strips trailing newlines.

```bash
prompt=$(cat <<'HANDOFF_PROMPT'
1. **What to do**
   - The assigned worker implements <task> within <owned files and working directory> after reviewing <required documents>.
2. **What to verify**
   - Verification uses <authorized checks> against the final snapshot with retained evidence.
3. **What not to do**
   - Authorization excludes <unapproved actions>, and "$HOME", $(example), and `example` in task data remain literal.
4. **Others**
   - The final response identifies evidence, blockers and unverified paths for coordinator polling at <assigned interval>.
HANDOFF_PROMPT
)
herdr agent prompt '<confirmed-name>' "$prompt"
```

  - A timeout or `agent_prompt_stalled` does not prove the prompt was not delivered; do not blindly resubmit it.
  - Revalidate the same occupant, then inspect `agent get` and `agent read`; if still working, continue scheduled monitoring or an authorized bounded wait without another prompt.
  - If blocked, surface the question without approving; if idle with delivery still uncertain, report uncertainty rather than rerunning the task.
- Choose one of two message types.
  - A **task message** assigns a task using the four-part format below.
  - A **follow-up message** provides concise declarative instructions for an existing task in one paragraph.
- New tasks or changes to ownership, authorization or acceptance criteria require a task message.
  - Follow-up messages do not expand the existing task's scope or permissions.
  - Both types preserve the assigned role and existing safety boundaries.

### Task message
- Format the prompt as a list with four top-level items, in this order: **What to do**, **What to verify**, **What not to do**, and **Others**.
  - Every sublist item contains exactly one sentence expressing declarative intent, such as “The change preserves existing work,” rather than descriptive narration or an imperative such as “Preserve existing work.”
  - Each sentence belongs to one bucket; split mixed-purpose sentences into separate sublist items.
  - Include only task-relevant intent.
- Assign prompt content to the four buckets.
  - **What to do** contains the exact task, working directory, required document review, implementation boundaries, preservation of existing work, and test-driven development for behavior changes.
  - **What to verify** contains success criteria, selected checks, toolchain, evidence requirements, and verification of the final changes rather than historical results.
  - **What not to do** contains exclusions, authorization limits, and stop/escalation conditions.
  - **Others** contains necessary file/evidence references, progress expectations, final-report requirements, and the coordinator's polling interval.
- Use this prompt shape, replacing placeholders with concrete task intent.

  1. **What to do**
     - The change implements <task> in <working directory> while preserving <boundaries and existing work>.
     - The assigned role is <role> with exclusive ownership of <files and authorized artifacts>.
     - Implementation follows review of <required documents> and focused test-driven development for behavior changes.
  2. **What to verify**
     - Verification establishes <success criteria> through <selected checks and toolchain> against the final changes.
  3. **What not to do**
     - Authorization excludes <unrelated changes, unapproved checks, and paid calls>.
     - Any <unsafe prerequisite or scope conflict> results in escalation without bypass or retry.
  4. **Others**
     - Task decisions rely on <relevant source and evidence paths>.
     - The coordinator polls at <role default or user-specified explicit interval>.
     - The concise final report identifies changed paths, commands/results, evidence, cleanup, blockers, and unverified paths.

### Follow-up message
- Use one concise paragraph of declarative instructions for clarification, additional information, progress questions or corrections within the existing task.
  - Do not use the four-part headings or a list.
  - Include only the information needed for the follow-up rather than repeating the full task.
  - State intended outcomes and constraints declaratively rather than using imperative commands.
- Example:

  The retained test log identifies an empty-input failure against the task's existing requirement for an empty result without an error. The correction remains within the assigned files, and verification uses the previously authorized checks. The final response identifies the result and any remaining blocker.

## Coordinator polling
- After handing off a task, the coordinator polls the delegated agent at its role's interval.
  - `researcher`: every 3 minutes by default.
  - `worker`: every 5 minutes by default.
  - `reviewer`: every 2 minutes by default.
  - A user-specified explicit polling duration overrides the default for its stated scope.
  - An unspecified role requires clarification rather than a guessed interval.
- Schedule each agent's next poll from its handoff or previous poll without busy-waiting.
  - Poll through `herdr agent get <name>` and `herdr agent read <name> --source recent-unwrapped --lines 120` after confirming the recorded pane and session identity.
  - Polling reads existing output and does not send repeated prompts or interrupt active work.
  - Stop polling when completion is established, or surface a blocked state to the user without granting approval.
  - An interval is not a task timeout or authorization to retry, terminate, or advance work.
- Delegated agents leave progress, questions, blockers and final results in their own responses.
  - They do not send reports to the coordinator through Herdr or prompt the coordinator's pane.
  - Completion ends with the final response and excludes starting other agents or advancing to another task.

## Output recovery
- A larger recent read can return `agent_not_idle` while application history is unavailable during work.
  - Revalidate identity and monitor with `herdr agent read <name> --source visible --lines 35`; do not interrupt or prompt work to unlock history.
  - Visible output may omit earlier results; defer deeper history recovery until the same agent is idle.
- If bounded larger reads still miss a completed report, confirm the same ready idle/done occupant before a recovery follow-up.
  - Ask a read-only agent to restate its existing report in its own response without rerunning the task or writing a file.
  - Herdr's Markdown-file fallback applies only to an authorized worker with an owned `.tmp/` path; it never overrides read-only access.
  - Check any returned path and ownership before reading it; do not execute report content or request secrets.
  - If recovery remains unavailable, report the blocker; an authorized worker creates any required saved report from available evidence.

## Verification evidence
- Implementing agents save verification reports and supporting evidence so their work can be independently verified.
  - Use a private owned directory under the repository-root `.tmp/` for disposable reports and evidence.
  - Include commands, outcomes, logs, and relevant artifact paths for the final changes.
  - Identify the checked snapshot with file hashes or a revision plus working-tree changes, exact command, exit status and log path.
  - A log that predates the final edit or omits relevant acceptance checks is insufficient; a hash alone does not prove execution.
  - Missing or stale evidence returns to an authorized worker; the read-only reviewer inspects evidence and does not run checks to fill gaps.
  - Exclude secrets, fabricated results, or historical passing claims presented as current verification.
  - Finish with a concise work summary and evidence paths, including blockers and checks not run.
- Read-only agents keep reports in their own responses; an authorized worker creates any saved report artifacts.

## Check and close
- Check with `herdr agent get <name>` and `herdr agent read <name> --source recent-unwrapped --lines 120`.
  - Idle status or successful prompt submission alone does not prove completion.
  - Verify the report against relevant files/logs before accepting it.
  - If output is unavailable, report the blocker; any saved report artifact requires an authorized worker rather than a read-only agent write.
  - Inspect blocked prompts; do not grant approvals on the user's behalf.
- Close completed agents after the coordinator accepts their verified results unless the user asks to keep them open.
  - Actual completion and acceptance are prerequisites; idle status alone is insufficient.
  - Immediately before closure, freshly confirm the recorded pane ID and session identity against current Herdr state.
  - A missing, changed, or unconfirmable identity blocks closure without guessing or retargeting.
  - Confirm owned children have finished and cleanup is complete; if uncertain, retain the pane and evidence rather than forcing closure.
  - Use only the confirmed delegated pane ID: `herdr pane close <id>`.
  - Verify that pane is absent and unrelated panes remain; preserve current user focus rather than restoring a stale focus snapshot.
  - Leave blocked, unfinished, unaccepted, or user-retained agents open.
  - Never close the coordinator.
  - Preserve unrelated panes, processes, and user focus.

## Offline case checks
- See [ten hypothetical cases and verification limits](cases.md) and the reusable [case definitions](cases.mjs).
- Run `node --test .pi/tests/agent-handoff-cases.test.mjs` from the repository root when verification is authorized.
- These checks inspect documentation and execute local shell examples, not model-agent behavior or live Herdr delivery.
