---
name: multi-agent-handoff
description: Divide an authorized request among parallel agents in one shared working directory, review their work, and reconcile the results through the agent-handoff skill.
---

# Multi-agent handoff

## Preconditions
- Use this skill when the user requests multi-agent delegation.
  - Read [agent-handoff](../agent-handoff/SKILL.md).
  - Follow its Herdr setup, identity checks, prompt format and [return-route notification protocol](../agent-handoff/SKILL.md#return-route-and-notifications).
  - Apply agent-handoff's default closure after accepted completion, subject to user retention requests.
  - Keep the coordinator open.

## Agent role setup
- The project-root [extension](../../extensions/multi-agent-handoff.ts) exposes this skill and loads [role instructions](../../resources/multi-agent-handoff/) for project-root sessions.
  - `AGENT_TYPE` accepts exactly `coordinator`, `researcher`, `worker`, or `reviewer`.
  - An unset value defaults to `coordinator`; empty or invalid values produce an extension error.
  - These are prompt instructions, not tool restrictions or a security boundary.
- Set the intended role in the target shell before its Pi process starts and before submitting a handoff.
  - The user-facing session uses `AGENT_TYPE=coordinator pi`, or leaves `AGENT_TYPE` unset.
  - Research agents use `researcher`, implementing agents use `worker`, and read-only review agents use `reviewer`.
  - For a new Herdr pane, use the confirmed idle shell and discovered CLI syntax to run `export AGENT_TYPE=worker` through `herdr pane run <confirmed-pane-id> 'export AGENT_TYPE=worker'`, substituting the assigned role.
  - Confirm the shell command completed with a fresh completion marker and exit status before starting Pi through `herdr agent start` as described in agent-handoff.
  - Record the role setup against the same shell and startup pane, terminal, process/session identity and readiness evidence required by Herdr.
  - Setting the variable only on the coordinator's `herdr` command does not establish the target pane's environment.
  - Do not reuse a running agent with a different role; escalate for an authorized replacement instead.
  - Role instructions load at session start; fresh sessions load changed resources while existing sessions retain their injected instructions until an authorized `/reload` or restart.
  - An environment change requires restarting Pi from the correctly configured shell.
  - Resource edits do not authorize live notification tests or reloading existing agents.
- Include the assigned role in the handoff and track it alongside the agent identity.
  - Workers and reviewers do not become coordinators or delegate further.
  - A role assignment grants no additional implementation, execution, live-call, or pane-closure authorization.

## Access and user interaction
- The user interacts only with the coordinator.
  - Researchers, workers and reviewers report to the coordinator.
  - Questions, blockers and approval requests reach the user through the coordinator.
- Access follows the assigned role.
  - `coordinator`: read-only.
  - `researcher`: read-only.
  - `worker`: write access within its assigned files and authorized scope.
  - `reviewer`: read-only.
- Read-only agents inspect existing files and evidence without modifying files or artifacts.
  - They do not author tests, run tests, builds or probes, launch apps, make live calls or perform filesystem/process cleanup.
  - Their findings and reports stay in agent messages; workers create any required report files, baseline copies, hashes or other evidence artifacts.
  - Herdr's report-file fallback does not authorize read-only agents to write; an authorized worker saves recoverable response text without rerunning the original work.
  - Coordinator orchestration through Herdr, including role setup, handoff messages and authorized pane closure, remains permitted.
  - Delegated read-only roles have a narrow exception for return-route identity reads and report delivery to their recorded coordinator.
  - That exception grants no artifact writes, verification execution, delegation, task assignment, pane closure or approval authority.
- All changes decided by the coordinator go through implementing workers.
  - This includes source, tests, documentation, shared-file reconciliation, retained reports and cleanup.
  - Authorized verification execution also goes through workers.
  - The coordinator does not change its role or edit directly to bypass this boundary.
  - If no suitable worker is available, the coordinator reports the blocker rather than making the change itself.

## Agent archetypes
- **Coordinator**
  - The coordinator is read-only and is the only agent the user interacts with.
  - It owns scope, authorization, delegation, sequencing, reconciliation and the final report.
  - It assigns file ownership and sends review findings back to implementation owners.
- **Researcher**
  - A researcher is read-only and inspects requirements, implementation and existing evidence.
  - It reports findings, confidence limits and proposed implementation or verification steps.
  - Research does not authorize implementation or verification execution; those tasks go to an implementing worker.
- **Implementing worker(s)**
  - Implementing workers have write access only to their assigned files and authorized artifacts.
  - They run authorized checks and save verification reports and supporting evidence so their work can be independently verified.
  - They use a private owned directory under the repository-root `.tmp/` for disposable reports and evidence.
  - Reports include commands, outcomes, logs, and relevant artifact paths for the final changes.
  - Reports exclude secrets, fabricated results, or historical passing claims presented as current verification.
  - They finish with a concise work summary and evidence paths, including blockers and checks not run.
  - Test authoring and verification execution are implementation work, not reviewer work.
- **Reviewer**
  - A reviewer is read-only.
  - It reads implementing workers' changed code, tests and retained verification evidence.
  - It checks that changes and tests run align with requirements and authorization.
  - It does not edit files, alter evidence, run tests, builds or probes, launch apps, make live calls or perform cleanup.
  - It reports findings and acceptance limits to the coordinator; implementation owners make corrections.

## Divide the request
- Define the overall outcome and acceptance criteria.
  - Split the request into independently reviewable tasks.
  - Split larger tasks into smaller branches when useful.
  - Keep delegation under the coordinator's control.
- Assign exclusive file ownership to each worker.
  - All workers use the same working directory.
  - Do not create separate worktrees.
  - Do not assign concurrent edits to the same file.
  - Reserve shared files and cross-task changes for reconciliation.
  - Record source and artifact ownership with concrete paths; directory grants include their descendants.
  - Treat overlapping directory/file grants and evidence directories as ownership conflicts, not disjoint assignments.
- Identify dependencies before launching workers.
  - Agree on interfaces and output paths first.
  - Preserve read-only baseline copies when inputs may change.
  - Run independent tasks in parallel.
  - Run dependent tasks in later waves.
  - Use a dependency launch gate tied to the accepted producer interface, snapshot and required evidence, not merely finished editing.
  - A changed producer input reopens the affected gate; unrelated independent tasks may continue.
- Resolve ownership transfer and worker loss before assigning replacement work.
  - Confirm affected writers have finished editing before transferring any files, including reserved shared files.
  - Worker loss is not ownership release; retain artifacts and hold the affected branch.
  - If the coordinator cannot rule out continued editing, escalate rather than launch a competing writer.
  - Reassignment or scope expansion requires an authorized new task message, not a follow-up or a coordinator/reviewer role change.

## Hand off
- Use agent-handoff for each task.
  - State the owned files and expected result.
  - State the required checks and acceptance criteria.
  - Exclude other workers' files and reserved files.
  - Require escalation for scope conflicts.
  - Exclude further delegation by workers.
  - The handoff records parent and sender server/session, pane, terminal and agent-session or PID/start identity, plus `task_id` and completion/blocker `notification_id` values.
  - It explicitly authorizes report-only queued input to the recorded coordinator when working.
  - The agent leaves results in its own responses and attempts one notification on completion or an actionable blocker.
- Track each worker and its task.
  - Record the agent name, pane ID, session identity and `AGENT_TYPE` role.
  - Track ownership, dependencies, status and review outcome.
  - Keep user focus unchanged.

## Receive delegated reports
- Completion or an actionable blocker triggers agent-handoff's identity-validated notification to the recorded coordinator.
  - Delivery uses one `herdr agent prompt` without `--wait`, interruption, repeated submission or an extra Enter.
  - Blocked, unknown, missing, or changed recipients receive no input and delivery uncertainty permits no blind retry.
  - Approval UI may prevent a sender from reporting; callbacks and acknowledgments are not guaranteed.
  - The sender's own response discloses delivery failure and available evidence without secrets or implied instructions.
- The coordinator validates and deduplicates task, notification and both identities before inspecting evidence.
  - Stale, duplicate or mismatched reports authorize no review, task change or closure.
  - Submission, actual completion, evidence acceptance and pane closure remain separate states.
  - A completion report may precede sender idle; bounded event-triggered settlement follows agent-handoff before review or closure.
  - A settlement timeout retains the pane without restarting periodic polling or interrupting work.
  - A blocked branch holds its dependents without stopping independent work.
  - Blocked approvals reach the user without an agent answering them.
- There is no routine fixed-interval polling or scheduled progress loop.
  - Bounded event-triggered status/output reads and explicit manual delivery recovery remain separate from periodic polling.
  - A missing notification is disclosed rather than assumed delivered or automatically resubmitted.
  - No report grants execution, approval, delegation or scope-expansion authority.

## Review and revise
- Review each completion before accepting it.
  - Give the read-only reviewer completed changes, tests, retained execution evidence and requirements.
  - Identify the reviewed snapshot; preserve baseline copies or hashes when files may change.
  - Record dirty working-tree file hashes for relevant review and check inputs; a shared Git HEAD alone does not identify those bytes.
  - Workers record command, cwd, relevant configuration, exit status, logs and input hashes before and after checks without logging secrets.
  - A subsequent relevant input change invalidates affected review acceptance and execution evidence until an authorized worker reruns required checks and the revised snapshot is reviewed.
  - Hashes are point-in-time evidence, not a lock or proof of a complete dependency inventory.
  - Inspect the actual files and verification evidence.
  - Compare the result with the task's acceptance criteria.
  - Check for out-of-scope changes and distinguish recorded results from checks not run.
  - Missing evidence returns to the coordinator for authorized verification by an implementing worker, not execution by the reviewer.
  - Do not treat idle status or successful prompt submission as proof of completion.
- Return rejected work to the same worker.
  - Use an agent-handoff follow-up paragraph for corrections within the existing task.
  - Use a new four-part task message if ownership, authorization or acceptance criteria change.
  - State concrete defects and required checks.
  - Keep file ownership unchanged.
  - Review the revised result again.
- Close completed agents after the coordinator accepts their verified results unless the user asks to keep them open.
  - Actual completion and acceptance are prerequisites; idle status alone is insufficient.
  - A notification never authorizes closing a still-working sender.
  - Unknown or mismatched agents remain open.
  - Immediately before closure, freshly confirm the recorded pane ID and session identity against current Herdr state through agent-handoff.
  - A missing, changed, or unconfirmable identity blocks closure without guessing or retargeting.
  - Close only that confirmed delegated agent's pane.
  - Leave blocked, unfinished, unaccepted, or user-retained agents open.
  - Never close the coordinator.
  - Follow Herdr's owned-child completion and cleanup checks; uncertainty retains the pane and artifacts.
  - Pane closure does not authorize evidence deletion or removal of unrelated temporary work.

## Aggregate and reconcile
- Combine accepted results by task branch.
  - Check each branch against its acceptance criteria.
  - Combine the branches into the overall result.
  - Assign reserved-file reconciliation to an implementing worker after relevant workers finish editing.
  - Track remaining reconciliation and integration checks separately from branch acceptance; assign execution to an available authorized worker or surface the staffing blocker.
  - Route interface, reference and test corrections through the assigned implementing workers.
  - Preserve unrelated user work.
- Verify the integrated result.
  - An implementing worker runs the authorized checks required by project guidance.
  - The coordinator inspects the resulting evidence without executing those checks.
  - The read-only reviewer inspects the resulting evidence without executing those checks.
  - Check cross-task behavior and documentation links.
  - Report blockers and unverified paths.
  - Report worker acceptance separately from integration success.

## Offline case checks
- Read [the ten collaboration cases](cases.json) for concrete requests, expected decisions, baseline observations, provenance and fidelity limits.
- Run authorized checks from the repository root:

  ```bash
  node --experimental-strip-types --test .pi/tests/multi-agent-handoff-cases.test.mjs
  node --experimental-strip-types --test .pi/tests/multi-agent-handoff.test.mjs
  node --experimental-strip-types --test .pi/tests/handoff-notifications.test.mjs
  node --test .pi/tests/herdr-skill.test.mjs
  ```

- The case and notification suites check documentation, local executable fixtures and production extension handlers in an offline harness; they do not prove actual agent decisions, inter-agent delivery or live Herdr lifecycle behavior.
- `MULTI_AGENT_SKILL_FILE` selects a retained skill snapshot for comparison; `HANDOFF_CASE_EVIDENCE_DIR` selects an existing private UUID-scoped `.tmp/multi-agent-handoff-*` directory for retained fixture evidence.
- Save baseline/final source hashes, commands, exit statuses and logs before claiming a rerun; identify moving cross-skill inputs rather than assuming another branch has passed.
- Cases without a safe executable fixture remain static hypothetical reviews; unavailable live paths remain unverified.
- Run cross-skill integration acceptance only after both handoff branches finish and their final snapshots are identified.
