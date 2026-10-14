---
name: agent-handoff
description: Delegate scoped work to a coding agent through Herdr, check progress, and receive a completion message. Use when the user asks to hand off work or start another agent; requires HERDR_ENV=1.
---

# Agent handoff

## Preconditions
- Delegate only when the user authorizes it.
  - Run `test "${HERDR_ENV:-}" = 1`; if it fails, stop.
  - Read the Herdr skill, or run `herdr --skill` if unavailable.
  - Discover syntax with `herdr --help` and relevant command groups; never bare `herdr`.

## Start or reuse
- Record the parent identity with `herdr pane current --current`.
  - Keep its pane ID and agent session identity for the callback.
- Reuse an idle agent only when appropriate; otherwise create a sibling pane.
  - Honor requested direction; otherwise choose right/down to fit the layout.
  - Use `herdr pane split --current --direction right --cwd "$PWD" --no-focus`.
  - Read the returned pane ID; never guess IDs or target the user's focused pane.
  - Start with `herdr agent start <unique-name> --kind pi --pane <id>`; honor a different requested kind.
  - If startup fails, inspect state/output before retrying; ensure the new shell is ready.

## Handoff
- Submit once using `herdr agent prompt <name> '<instructions>'`.
- Format the prompt as a list with four top-level items, in this order: **What to do**, **What to verify**, **What not to do** (optional), and **Others** (optional).
  - Every sublist item contains exactly one sentence expressing declarative intent, such as “The change preserves existing work,” rather than descriptive narration or an imperative such as “Preserve existing work.”
  - Each sentence belongs to one bucket; split mixed-purpose sentences into separate sublist items.
  - Include only task-relevant intent.
- Assign prompt content to the four buckets.
  - **What to do** contains the exact task, working directory, required document review, implementation boundaries, preservation of existing work, and test-driven development for behavior changes.
  - **What to verify** contains success criteria, selected checks, toolchain, evidence requirements, and verification of the final changes rather than historical results.
  - **What not to do** contains exclusions, authorization limits, and stop/escalation conditions.
  - **Others** contains necessary file/evidence references, progress expectations, final-report requirements, and completion-callback intent.
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

## Completion callback
- When a callback is requested, include its intent as one-sentence declarative sublist items under **Others** in the handoff.
  - Callback delivery requires `HERDR_ENV=1` and a current `herdr agent get <parent-pane>` result matching <recorded parent session identity>.
  - A matching identity permits one `herdr agent prompt <parent-pane> '<outcome and evidence paths>'` submission without `--wait`.
  - Identity mismatch or delivery failure leaves the outcome in the final response without another target or blind resend.
  - Completion ends with reporting and excludes starting other agents or advancing to another task.

## Check and close
- Check with `herdr agent get <name>` and `herdr agent read <name> --source recent-unwrapped --lines 120`.
  - Idle status or successful prompt submission alone does not prove completion.
  - Verify the report against relevant files/logs before accepting it.
  - If output is unavailable, ask for a temporary Markdown report and read it.
  - Inspect blocked prompts; do not grant approvals on the user's behalf.
- Close only when requested, using the confirmed pane ID: `herdr pane close <id>`.
  - Preserve unrelated panes, processes, and user focus.
