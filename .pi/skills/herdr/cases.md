# Herdr case checks

These cases test skill decisions, not model quality. Use only explicitly authorized disposable work. Do not start model agents, change user focus, or reuse unrelated panes to obtain coverage.

## Offline regressions

```bash
node --test .pi/tests/herdr-skill.test.mjs
```

- These are documentation contract checks.
- The multiline example runs against a local shell function named `herdr`, not the installed CLI.
- There is no server, pane, agent, network, or paid-model access.
- Set `HERDR_SKILL_FILE` to a retained skill snapshot for baseline comparison.
- Passing checks do not establish live agent submission, completion, or history recovery.

## Ten cases

For each case, retain the request, expected decision, observed result, fidelity, command exit statuses, relevant output and final rerun. Save the baseline text and hashes before edits. Keep disposable evidence in a private UUID-scoped repository `.tmp/` directory.

1. **Background command focus**
   - Run a harmless command in an owned sibling at the same cwd with `--no-focus`.
   - Check a unique output marker, command exit status, and unchanged focused pane.
2. **Cramped geometry**
   - Read the caller rectangle and estimate both children for each direction.
   - Decline another split when neither direction is usable for the task. Do not silently resize unrelated panes or create another tab.
3. **Named startup readiness**
   - Use an authorized named agent's startup evidence and readback.
   - Check name, kind, pane, terminal and readiness. Do not equate a reported idle state or rename with active-agent readiness.
   - Existing worker startup can supply this evidence without launching another agent. Label supplied startup evidence separately from independently executed checks.
4. **Busy-pane noninterference**
   - Inspect an owned synthetic foreground process and working state.
   - Do not run shell commands, interrupt the process or queue agent prompts into it. Verify no input arrived.
5. **Multiline exactly-once submission**
   - Include quotes, newlines, variables and command-substitution syntax in a literal prompt.
   - Verify one argument and one submission. The offline shell-function check proves quoting only, not Herdr's actual Enter transport.
6. **Timeout without duplication**
   - Simulate a delivered prompt whose wait times out. Inspect identity and output, then wait without another prompt.
   - A live wait on synthetic working state can verify timeout behavior. It does not prove live prompt delivery.
7. **Blocked nonapproval**
   - Use an explicitly synthetic blocked state, never a real approval that would require consent to exercise.
   - Verify inspection and refusal to approve. A guard probe may return `agent_blocked`; verify zero receiver input and never send approval keys.
8. **Missing response recovery**
   - Make the completed response unavailable in a synthetic viewport. Try bounded larger reads first.
   - If history capture returns `agent_not_idle`, revalidate identity and monitor with a bounded visible read. Do not interrupt or prompt working work; defer deeper history recovery until idle. Label coordinator-supplied observations separately from independently replayed checks.
   - Only the same ready idle/done occupant may receive a file-only follow-up for the existing response in owned `.tmp/`. Do not rerun original work.
   - If the synthetic occupant is not an active named agent, mock the fallback instead of bypassing readiness.
9. **Stale or replaced identity**
   - Replace only an explicitly owned synthetic identity. Refuse input after terminal, name, kind or process/session identity changes.
   - After owned cleanup, verify the stale pane cannot be resolved. Do not search for a replacement pane and retry input automatically.
10. **Ownership-gated cleanup**
    - Exercise refusal for an unrelated pane, mismatched terminal and still-running foreground process using deterministic fixtures.
    - For live cleanup, verify the creation ledger, finish owned children, confirm the expected shell, then close only the owned pane.
    - Check pane absence, child exit, preserved unrelated panes and focus. Retain uncertain work instead of forcing closure.

## Fidelity and limitations

- Label live CLI calls, synthetic state reports, deterministic mocks and static assertions separately.
- State reports on owned synthetic occupants are not model-agent completions. Never inject them into a real agent to manufacture readiness.
- A reported occupant can support reads, waits and blocked guards while still rejecting prompts as `agent_not_ready`.
- Record skipped or unavailable transport paths. Do not count these cases as ten live model-agent trials.
