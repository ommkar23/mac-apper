# Project Pi resources

These resources customize developer Pi sessions. They are not packaged app resources.

## Multi-agent handoff

- [Extension](extensions/multi-agent-handoff.ts): exposes the canonical [multi-agent-handoff skill](skills/multi-agent-handoff/SKILL.md).
- [Role instructions](resources/multi-agent-handoff/): one plain-text file per role.
  - `coordinator` is read-only and is the only agent the user interacts with.
  - `researcher` is read-only and inspects requirements and existing evidence.
  - `worker` has write access within its assigned scope and runs authorized checks.
  - `reviewer` is read-only and inspects completed changes and retained evidence.
- All changes decided by the coordinator go through workers.
- Workers also own verification execution, reconciliation edits, report files, evidence artifacts, and cleanup.
- Read-only agents report through messages without writing files or executing verification.
- Coordinator Herdr orchestration and authorized pane closure remain permitted.
- After handoff, the coordinator polls researchers every 3 minutes, workers every 5 minutes, and reviewers every 2 minutes by default.
- A user-specified polling duration overrides the default for its stated scope.
- Agents leave results in their own responses. The coordinator reads them through Herdr; agents do not send reports through Herdr.
- Pi discovers the extension from the project-root `.pi/extensions/` directory after project trust.
- The extension reads `AGENT_TYPE` when it loads.
  - Unset means `coordinator`.
  - Empty, misspelled, or unsupported values produce an extension error instead of falling back.
- Role text loads at `session_start` and applies to each request from the exact project root.
- A dedicated `multi_agent_handoff` prompt section preserves the existing shared user instructions.
- The skill remains the workflow authority. Role text adds session-specific instructions.
- These instructions do not enforce tool permissions or grant delegation authorization.

After the root README's temporary-work setup, start a session with its intended role:

```sh
AGENT_TYPE=coordinator pi
AGENT_TYPE=researcher pi
AGENT_TYPE=worker pi
AGENT_TYPE=reviewer pi
```

Follow the skill's target-shell setup before starting delegated Herdr agents. An environment assignment on the coordinator's command does not configure another pane. Restart Pi to change its inherited role. Use `/reload` after editing instruction resources.

## Offline verification

```sh
TMPDIR="$PWD/.tmp/" node --experimental-strip-types --test \
  .pi/tests/multi-agent-handoff.test.mjs .pi/tests/user-instructions.test.mjs
```

The tests exercise role selection, skill registration, lifecycle hooks, root scoping, and coexistence with shared user instructions. They do not launch Herdr agents or make model calls.
