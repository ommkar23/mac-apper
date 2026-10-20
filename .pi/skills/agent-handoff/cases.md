# Agent handoff case checks

These are ten realistic hypothetical requests, not ten live delegation trials.
The reusable [case definitions](cases.mjs) contain each request, expected decision, source provenance, fidelity and limitations.

## Run authorized offline checks

From the repository root with its safe `.tmp/` initialized:

```bash
node --test .pi/tests/agent-handoff-cases.test.mjs
node --experimental-strip-types --test .pi/tests/multi-agent-handoff.test.mjs
node --experimental-strip-types --test .pi/tests/handoff-notifications.test.mjs
node --test .pi/tests/herdr-skill.test.mjs
```

- `AGENT_HANDOFF_SKILL_FILE` selects a retained agent-handoff skill snapshot.
- `HERDR_SKILL_FILE` selects a retained Herdr skill snapshot for its checks.
- The shared multi-agent checks read the current checkout; save input hashes before and after execution.
- Preserve baseline text and hashes before changing the skill.
- Save commands, exit statuses, logs, snapshot hashes and per-case observations in a private owned repository `.tmp/` directory.
- Each owned test emits a JSON diagnostic with its expected decision, observed documentation matches, any executed example, source hash and limits.
- Missing contracts are documentation gaps, not evidence that an agent performed the unsafe action.
- Rerun the same cases against the final snapshot and retain the baseline failures.
- Report branch completion separately from later cross-skill integration acceptance.

## Cases and evidence boundaries

1. **C01: Authorization and unavailable Herdr.**
   - An advice-only request grants no delegation permission.
   - The documented environment gate runs in Bash with unset, empty, `0` and `1` values without invoking Herdr.
2. **C02: Role-safe target-shell setup.**
   - A worker starts from its target shell's role and repository temporary environment, not the coordinator command's environment.
   - The documented exports run only in an isolated child shell; shared extension tests exercise session-time role capture separately.
3. **C03: Safe idle-agent reuse.**
   - An idle reviewer is not a worker, and idle unfinished work is not available for a new task.
   - Documentation checks cover matching role, cwd, ownership, readiness and accepted prior work without replacing a live occupant.
4. **C04: Complete new-task format.**
   - A shared-repository task needs the four ordered buckets with scope, checks, limits, evidence, the recorded return route and narrow queued-report authorization.
   - Tests inspect the real template structure, not arbitrary sentence semantics or model understanding.
5. **C05: Follow-up versus expanded scope.**
   - An existing-task correction remains one declarative paragraph.
   - Expanded ownership, authorization or acceptance requires a new authorized four-part task.
6. **C06: Literal prompt and uncertain delivery.**
   - Quoted shell variables, substitutions, backticks and newlines remain one literal prompt argument.
   - A local Bash function captures the documented example once; no Herdr transport or model is involved.
   - Timeout and stalled-delivery recovery are documentation checks, not live errors manufactured for coverage.
7. **C07: Identity-checked notifications and early settlement.**
   - Completion and actionable blockers produce one non-waiting report notification to the recorded coordinator.
   - Unsafe recipients receive no input, and uncertainty never authorizes retry.
   - Duplicate and stale reports cannot trigger acceptance or closure.
   - Early completion uses bounded event-triggered settlement, not closure of a working sender or routine polling.
   - The focused suite checks explicit documentation contracts and production role injection without synthetic lifecycle reports.
8. **C08: Busy history and read-only reports.**
   - `agent_not_idle` leads to bounded visible monitoring, not interruption.
   - An idle read-only agent restates an existing report in its own response; only an authorized worker saves artifacts.
   - These are hypothetical recovery branches, not proof of live history completeness.
9. **C09: Stale or incomplete verification.**
   - A passing log before the final edit cannot establish final acceptance.
   - Evidence identifies the snapshot and execution; read-only reviewers do not fill gaps by running tests.
10. **C10: Identity-safe closure with retention.**
    - Accepted completion is necessary but does not override a changed identity, user retention or uncertain owned-child cleanup.
    - No closure or signaling occurs in these tests; supplied startup provenance and own-pane reads identify context only.

## Limits

- Passing documentation assertions prove only that the checked snapshot contains the stated contracts.
- Executable shell examples prove environment and argument handling locally, not target-pane readiness or prompt delivery.
- No extra agents, experiment panes, approvals, credentials, remote configuration or external calls are needed.
- No state reports may be injected into a real agent to manufacture readiness or completion.
- The notification example runs against a local Bash capture function, not Herdr or another agent.
- Sender/recipient/task refusal, duplicates, stale events, delivery failure and closure gates are documentation assertions, not a transport implementation or behavioral simulator.
- Approval UI can prevent blocker delivery; these checks establish no guaranteed callbacks, acknowledgments or exactly-once model execution.
- Live submission, history recovery, settlement and identity-safe closure remain unverified unless separately authorized and observed.
- Existing sessions retain their injected role instructions; these changes govern fresh sessions without authorizing a live reload or callback experiment.
