---
name: multi-agent-handoff
description: Divide an authorized request among parallel agents in one shared working directory, review their work, and reconcile the results through the agent-handoff skill.
---

# Multi-agent handoff

## Preconditions
- Use this skill when the user requests multi-agent delegation.
  - Read [agent-handoff](../agent-handoff/SKILL.md).
  - Follow its Herdr setup, identity checks, prompt format and coordinator polling rules.
  - Confirm authorization to close accepted workers.
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
  - Confirm the shell command completed before starting Pi through `herdr agent start` as described in agent-handoff.
  - Setting the variable only on the coordinator's `herdr` command does not establish the target pane's environment.
  - Do not reuse a running agent with a different role; escalate for an authorized replacement instead.
  - Role instructions load at session start; resource edits require `/reload`, while an environment change requires restarting Pi from the correctly configured shell.
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
  - Coordinator orchestration through Herdr, including role setup, handoff messages and authorized pane closure, remains permitted.
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
  - They run authorized checks and retain evidence of commands, test outcomes and final changes.
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
- Identify dependencies before launching workers.
  - Agree on interfaces and output paths first.
  - Preserve read-only baseline copies when inputs may change.
  - Run independent tasks in parallel.
  - Run dependent tasks in later waves.

## Hand off
- Use agent-handoff for each task.
  - State the owned files and expected result.
  - State the required checks and acceptance criteria.
  - Exclude other workers' files and reserved files.
  - Require escalation for scope conflicts.
  - Exclude further delegation by workers.
  - State that the agent leaves results in its own responses for coordinator polling, without sending reports through Herdr.
- Track each worker and its task.
  - Record the agent name, pane ID, session identity and `AGENT_TYPE` role.
  - Track ownership, dependencies, status and review outcome.
  - Keep user focus unchanged.

## Poll delegated tasks
- After handing off each task, the coordinator polls the agent at the assigned role's interval.
  - `researcher`: every 3 minutes by default.
  - `worker`: every 5 minutes by default.
  - `reviewer`: every 2 minutes by default.
  - A user-specified explicit polling duration overrides the default for its stated scope.
- Track the next poll separately for each agent from its handoff or previous poll.
  - Use agent-handoff's identity-checked status and output reads without busy-waiting, repeated prompts or interruption.
  - Read each agent's own responses for progress, questions, blockers and final results.
  - Agents do not send reports through Herdr or prompt the coordinator's pane.
  - Surface blocked approvals to the user without granting approval on their behalf.
  - Stop polling after established completion or a surfaced blocker.
  - Polling intervals do not impose task timeouts or authorize retries or termination.

## Review and revise
- Review each completion before accepting it.
  - Give the read-only reviewer completed changes, tests, retained execution evidence and requirements.
  - Identify the reviewed snapshot; preserve baseline copies or hashes when files may change.
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
- Close accepted workers through agent-handoff.
  - Confirm the worker's pane and session identity first.
  - Close only that worker's pane.
  - Respect any request to keep workers open.
  - Leave blocked or unfinished workers open.

## Aggregate and reconcile
- Combine accepted results by task branch.
  - Check each branch against its acceptance criteria.
  - Combine the branches into the overall result.
  - Assign reserved-file reconciliation to an implementing worker after relevant workers finish editing.
  - Route interface, reference and test corrections through the assigned implementing workers.
  - Preserve unrelated user work.
- Verify the integrated result.
  - An implementing worker runs the authorized checks required by project guidance.
  - The coordinator inspects the resulting evidence without executing those checks.
  - The read-only reviewer inspects the resulting evidence without executing those checks.
  - Check cross-task behavior and documentation links.
  - Report blockers and unverified paths.
  - Report worker acceptance separately from integration success.
