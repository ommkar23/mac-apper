---
name: multi-agent-handoff
description: Divide an authorized request among parallel agents in one shared working directory, review their work, and reconcile the results through the agent-handoff skill.
---

# Multi-agent handoff

## Preconditions
- Use this skill when the user requests multi-agent delegation.
  - Read [agent-handoff](../agent-handoff/SKILL.md).
  - Follow its Herdr setup, identity checks, prompt format and callback rules.
  - Confirm authorization to close accepted workers.
  - Keep the coordinator open.

## Agent archetypes
- **Coordinator**
  - The coordinator is the agent the user interacts with.
  - It owns scope, authorization, delegation, sequencing, reconciliation and the final report.
  - It assigns file ownership and sends review findings back to implementation owners.
- **Researcher**
  - A researcher inspects requirements, implementation and existing evidence.
  - It reports findings, confidence limits and proposed implementation or verification steps.
  - Research does not authorize implementation or execution; either requires an explicit handoff scope.
- **Implementing worker(s)**
  - Implementing workers change only their assigned files.
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
  - Request a completion callback.
- Track each worker and its task.
  - Record the agent name, pane ID and session identity.
  - Track ownership, dependencies, status and review outcome.
  - Keep user focus unchanged.

## Review and revise
- Review each completion before accepting it.
  - Give the read-only reviewer completed changes, tests, retained execution evidence and requirements.
  - Identify the reviewed snapshot; preserve baseline copies or hashes when files may change.
  - Inspect the actual files and verification evidence.
  - Compare the result with the task's acceptance criteria.
  - Check for out-of-scope changes and distinguish recorded results from checks not run.
  - Missing evidence returns to the coordinator for authorized verification by an implementing worker, not execution by the reviewer.
  - Do not treat idle status or a callback as proof of completion.
- Return rejected work to the same worker.
  - Use the agent-handoff prompt format for revision requests.
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
  - Reconcile reserved files after relevant workers finish editing.
  - Resolve interface, reference and test mismatches.
  - Preserve unrelated user work.
- Verify the integrated result.
  - The coordinator or an implementing worker runs the authorized checks required by project guidance.
  - The read-only reviewer inspects the resulting evidence without executing those checks.
  - Check cross-task behavior and documentation links.
  - Report blockers and unverified paths.
  - Report worker acceptance separately from integration success.
