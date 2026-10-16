---
name: agent-handoff
description: Delegate scoped work to a coding agent through Herdr and poll its progress and final response. Use when the user asks to hand off work or start another agent; requires HERDR_ENV=1.
---

# Agent handoff

## Preconditions
- Delegate only when the user authorizes it.
  - Run `test "${HERDR_ENV:-}" = 1`; if it fails, stop.
  - Read the Herdr skill, or run `herdr --skill` if unavailable.
  - Discover syntax with `herdr --help` and relevant command groups; never bare `herdr`.

## Start or reuse
- Record the parent identity with `herdr pane current --current`.
  - Keep its pane ID and agent session identity for safe orchestration.
- Reuse an idle agent only when appropriate; otherwise create a sibling pane.
  - Honor requested direction; otherwise choose right/down to fit the layout.
  - Use `herdr pane split --current --direction right --cwd "$PWD" --no-focus`.
  - Read the returned pane ID; never guess IDs or target the user's focused pane.
  - Start with `herdr agent start <unique-name> --kind pi --pane <id>`; honor a different requested kind.
  - If startup fails, inspect state/output before retrying; ensure the new shell is ready.

## Handoff message types
- Submit each message once using `herdr agent prompt <name> '<instructions>'`.
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
     - Implementation follows review of <required documents> and focused test-driven development for behavior changes.
  2. **What to verify**
     - Verification establishes <success criteria> through <selected checks and toolchain> against the final changes.
  3. **What not to do**
     - Authorization excludes <unrelated changes, unapproved checks, and paid calls>.
     - Any <unsafe prerequisite or scope conflict> results in escalation without bypass or retry.
  4. **Others**
     - Task decisions rely on <relevant source and evidence paths>.
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

## Check and close
- Check with `herdr agent get <name>` and `herdr agent read <name> --source recent-unwrapped --lines 120`.
  - Idle status or successful prompt submission alone does not prove completion.
  - Verify the report against relevant files/logs before accepting it.
  - If output is unavailable, ask for a temporary Markdown report and read it.
  - Inspect blocked prompts; do not grant approvals on the user's behalf.
- Close only when requested, using the confirmed pane ID: `herdr pane close <id>`.
  - Preserve unrelated panes, processes, and user focus.
