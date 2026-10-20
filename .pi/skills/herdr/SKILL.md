---
name: herdr
description: "Control Herdr, a terminal multiplexer for coding agents. Use only when the user explicitly mentions Herdr or asks to use Herdr to inspect or control panes, tabs, workspaces, commands, or another agent. Do not use merely because a task could benefit from a background terminal, delegation, or parallel work. Requires HERDR_ENV=1."
---

# Herdr

Herdr organizes terminals into workspaces, tabs, and panes, recognizes coding agents running inside panes, and exposes the current session through the `herdr` CLI.

Before issuing any control command, verify that this agent is running inside a Herdr-managed pane:

```bash
test "${HERDR_ENV:-}" = 1
```

If the check fails, say that you are not running inside Herdr and stop. Do not inspect or control the focused Herdr session from outside Herdr.

When the check passes, the `herdr` binary in `PATH` talks to the current session. Use it to inspect neighboring work, create terminal layout, start agents and commands, read output, and wait for state changes.

## Learn the current CLI

The installed binary is the authority for command syntax. Start with:

```bash
herdr --help
```

Then print the relevant command group by running the group without a subcommand:

```bash
herdr agent
herdr pane
herdr workspace
herdr tab
herdr worktree
herdr terminal
herdr notification
herdr integration
herdr session
herdr machine
```

Do not run bare `herdr` for discovery; it launches or attaches the TUI. Do not probe a mutating nested command by omitting arguments. Commands such as `herdr workspace create` are valid with defaults and will execute.

Most control commands return JSON. Read identifiers and state from those responses instead of predicting them. Reads such as `agent read` can return plain text, and successful input commands can return no stdout. Do not assume every successful command returns a JSON document.

## Understand layout, panes, and agents

Choose the primitive that matches the job:

- Workspace, tab, and pane topology organize terminal locations.
- Pane commands control raw terminals, shells, tests, servers, input, and output.
- Agent commands control the recognized coding agent currently occupying a pane.

A pane exists whether or not it contains an agent. `agent start` requires an existing available shell pane and never creates, splits, or moves layout. Use pane commands for ordinary processes. Use agent commands when Herdr must validate agent identity or interpret `idle`, `working`, `blocked`, `done`, and `unknown` lifecycle states.

Agent commands accept either a unique live agent name or the pane ID currently hosting that agent. They do not accept terminal IDs or bare agent-kind labels. Names must match `[a-z][a-z0-9_-]{0,31}` and be unique among live agents. A name follows the current pane occupant and is cleared when that agent exits, is released, or is replaced.

`idle` and `done` both mean the agent is ready for input. The CLI/API uses the server's seen state to distinguish them; explicit focus commands mark the target seen, while reads do not. Each TUI client tracks viewed completions independently, so its Done badge can differ from the CLI or another client's badge. `blocked` means Herdr recognized an approval or question UI. `unknown` means an agent is present but Herdr cannot classify it confidently; it does not prove completion.

## Use IDs and caller context

Public IDs are opaque stable handles:

- workspace: `w1`
- tab: `w1:t1`
- pane: `w1:p1`

Closed tab and pane IDs are not reused. A pane moved into another workspace receives a new workspace-qualified pane ID. After `pane move`, continue with `.result.move_result.pane.pane_id` or the live agent name. The old value is reported as `.result.move_result.previous_pane_id`; only the moved process's inherited caller context keeps resolving that old ID, so do not use it as a general agent target.

Herdr injects the caller's context into each managed pane:

```bash
printf '%s\n' "$HERDR_WORKSPACE_ID" "$HERDR_TAB_ID" "$HERDR_PANE_ID"
```

Prefer `--current` when a pane command should target the calling pane. An omitted `pane split` target uses the calling pane when `HERDR_PANE_ID` is available, otherwise the focused pane. Other commands may use the UI-focused pane, which can belong to the user or another client.

Discover live state with:

```bash
herdr workspace list
herdr tab list --workspace "$HERDR_WORKSPACE_ID"
herdr pane current --current
herdr pane list --workspace "$HERDR_WORKSPACE_ID"
herdr agent list
```

Creation responses expose the IDs to use next. `workspace create` returns `.result.workspace`, `.result.tab`, and `.result.root_pane`. `tab create` returns `.result.tab` and `.result.root_pane`. `pane split` returns the new pane as `.result.pane`.

Keep a creation ledger for disposable work: server/session, pane ID, `terminal_id`, tab, cwd, and owned foreground process identity. For an agent, also record its name and kind. Before every input or mutation, re-read the target and compare it with that ledger. Stop on a changed or mismatched occupant, even if the pane or name still resolves. A name or pane ID is not an immutable agent-session identity. Compare the agent session ID when exposed; otherwise retain the native process PID and start identity from `pane process-info` and the OS. Do not substitute status, revision, or title for session identity. These checks are point-in-time, not atomic protection against replacement races.

IDs and live agent names are scoped to one server. Two saved SSH machines can both have `w1:p1` or an agent named `reviewer`. Selecting a machine in the TUI does not retarget commands running in your pane: without `--machine`, they still use the inherited session and socket context.

To control a saved SSH machine, use the same global prefix for discovery and every later command:

```bash
herdr --machine <label-or-id> agent list
herdr --machine <label-or-id> pane list
herdr --machine <label-or-id> agent prompt <remote-agent-name> "Reply with your current status." --wait --timeout 120000
```

The selector must be an enabled saved profile ID or a unique, case-sensitive label, not an arbitrary SSH hostname. Commands use that profile's remote session without an open TUI. Do not combine `--machine` with `--session` or `--remote`. Discover IDs on that machine; inherited local IDs and `--current` do not identify remote panes.

Both installations must support machine API forwarding, and the remote server must already be running and API-compatible. Forwarding never installs, starts, or restarts a server and never falls back to Local. Local configuration, session management, installation commands, and interactive attachment are not forwarded. Remote worktree paths must be absolute, `~`, or start with `~/`; plugin link paths must be absolute. A connection failure does not prove a mutation was not applied: inspect remote state before retrying.

`herdr machine list` lists saved connection profiles, not a cross-machine pane inventory; add `--json` for scripts. Only add, remove, enable, or disable profiles when the user asks. Removing a profile disconnects the client but does not stop remote sessions. Interactive `machine add` discovers running remote sessions and may ask the user to pick one; non-interactive setup uses the remote default session unless `--remote-session` is explicitly supplied. Use `herdr machine status [<label-or-id>] --json` to diagnose a failing machine. `herdr machine reconnect` needs the user to complete SSH authentication in their terminal; do not run it for them. Setup asks before stopping an incompatible server and defaults to No; do not approve replacement without the user's consent. Experimental handoff is not part of `machine add`.

## Start and coordinate an agent

Default to a sibling pane in the current tab and the current working directory. Do not create a workspace, tab, worktree, or different cwd unless the user explicitly requests that topology or location.

Honor a direction requested by the user. Otherwise inspect the caller pane:

```bash
herdr pane layout --pane "$HERDR_PANE_ID"
```

Split a wide pane to the right and a narrow or tall pane down. Inspect the actual rectangle and estimate both resulting panes before splitting. Avoid repeated same-direction splits that create unusably narrow columns or short rows. Re-read layout afterward. If neither direction leaves usable space for the task, do not split again. Report the constraint and ask before changing topology or resizing other work. Keep the existing user's focus unchanged; it may not be in the calling pane. Explicitly preserve the caller's working directory:

```bash
herdr pane split --current --direction right --cwd "$PWD" --no-focus
```

Replace `right` with `down` when appropriate. Read the new pane ID from `.result.pane.pane_id`.

An available shell pane must be at its interactive prompt, with the shell itself in the foreground and no foreground command, editor, or agent running. Check the pane and its foreground process before reusing it:

```bash
herdr pane get <returned-pane-id>
herdr pane process-info --pane <returned-pane-id>
```

An unrecognized agent or `unknown` status does not prove an available shell. Do not run shell input into a busy pane, interrupt it to make room, or reuse it merely because its cwd matches. Do not prompt a working agent unless the user explicitly authorized queuing or steering that work. Otherwise leave it alone and use an authorized available pane or report the constraint.

Start a supported agent in the available pane with a useful unique name:

```bash
herdr agent start reviewer --kind codex --pane <returned-pane-id>
```

Use the kind requested by the user. Run `herdr agent` to inspect the installed kind list and options. Pass native agent arguments only after `--`:

```bash
herdr agent start reviewer --kind codex --pane <returned-pane-id> -- <agent-args...>
```

A successful `agent start` returns only after Herdr detects the expected agent in the same pane and considers it ready for interactive input. Verify the returned name, kind, pane, terminal and `interactive_ready=true` when exposed. A reported `idle` state or a successful rename alone does not establish a supported active agent ready for prompts. Missing readiness on an unfamiliar occupant is a reason to stop, not to manufacture state reports or bypass `agent_not_ready`.

If the agent is blocked during startup, the command returns `agent_not_ready` immediately but keeps the name available for inspection. Read the UI and ask the user before answering it; do not automatically accept trust or approval dialogs. Wait until the same agent becomes idle and ready before prompting it. Startup defaults to a 30-second timeout. After a startup timeout, inspect the original pane and process before retrying; an uncertain result does not authorize a second launch.

Submit work through the agent surface:

```bash
herdr agent prompt reviewer "Review the current diff and report only actionable findings." --wait --timeout 120000
```

For multiline work, pass the entire prompt as one quoted argument. A quoted heredoc keeps shell variables, command substitutions, quotes and embedded newlines literal:

```bash
prompt=$(cat <<'HERDR_PROMPT'
Review the diff.
Keep "$HOME", $(example), and `example` literal.
Report only actionable findings.
HERDR_PROMPT
)
herdr agent prompt reviewer "$prompt" --wait --timeout 120000
```

Choose a delimiter absent from the prompt. Command substitution strips trailing newlines; use an exact argument/file-reading API if those are significant. Do not split the prompt into line-by-line sends, interpolate untrusted prompt text into shell source, or send an extra Enter after `agent prompt`.

`agent prompt` honors the pane's live bracketed-paste mode and sends text followed by encoded Enter as one ordered submission. It reports successful submission only after both have been written; that alone does not prove the agent started a turn. For Codex on Windows, Herdr sends a paste boundary before Enter so submission does not depend on prompt size. It rejects an agent already waiting at an approval or question dialog with `agent_blocked` before sending any input. Inspect the blocked UI and ask the user before answering it. For normal agent work, `--wait` is enough: it waits for the first settled `idle`, `done`, or `blocked` state. Do not repeat those defaults with `--until`.

With `--wait`, a prompt sent from a non-working state must produce observed `working` or `blocked` activity. After submission, Herdr waits up to five seconds for that activity; unrelated `idle`, `done`, or session changes do not satisfy this gate. It returns `agent_prompt_stalled` if no activity is observed, or `timeout` if the caller's timeout expires first. The caller timeout includes submission time. Without a timeout, the settled-state wait is indefinite after activity is observed. This wait tracks lifecycle state, not an individual turn; if the agent is already working, completion of the active turn may satisfy it.

Use `--until` only for a state-specific workflow, such as waiting for an already-running agent to request input:

```bash
herdr agent wait reviewer --until blocked --timeout 120000
```

Without `--until`, standalone `agent wait` uses the same settled-state defaults as `agent prompt --wait`.

Use logical keys for interactive agent UI controls:

```bash
herdr agent send-keys reviewer esc
herdr agent send-keys reviewer ctrl+c
```

Herdr validates all keys before writing any bytes. Read the result through the resolved agent:

```bash
herdr agent get reviewer
herdr agent read reviewer --source recent-unwrapped --lines 120
```

If a wait fails or returns `blocked`, inspect `agent get` and `agent read` before deciding what input to send. A timeout or stalled response does not prove the prompt was never delivered; do not blindly submit it again. Revalidate the recorded occupant first. If it is still working, use a bounded `agent wait`, not another prompt. If blocked, report the approval or question without answering it. If idle but delivery or completion remains uncertain, report that uncertainty rather than retrying the task. Use the pane surface only when raw terminal control is intentional.

## Run an ordinary command in another pane

Create a sibling pane with the same geometry rule, preserve the caller's working directory, and keep user focus unchanged:

```bash
herdr pane split --current --direction right --cwd "$PWD" --no-focus
```

Read the new pane ID from `.result.pane.pane_id`, then run and inspect the command:

```bash
herdr pane run <returned-pane-id> "just test"
herdr pane wait-output <returned-pane-id> --match "test result" --timeout 120000
herdr pane read <returned-pane-id> --source recent-unwrapped --lines 120
```

`pane run` atomically sends command text and Enter. It does not prove the command finished successfully. Check that the target is the same available shell before sending it. Commands run in the target's native shell; do not assume Bash syntax or that a variable name is writable (`status` is read-only in zsh). Use a fresh per-run marker and capture the command's exit status, not just echoed command text or an old success line. `pane wait-output` searches the selected snapshot immediately, so output that already exists can match. Use `--match <text>` for a literal substring or `--regex <pattern>` for a Rust regular expression. Omitting `--timeout` allows an indefinite wait.

Use the read source that matches the task:

- `visible`: the currently rendered viewport.
- `recent`: recent rendered output, including soft wraps.
- `recent-unwrapped`: recent output with soft wraps joined; prefer it for logs and transcripts.
- `detection`: the plain-text bottom-buffer snapshot used for agent detection.

Use `--format ansi` when colors and terminal styling are evidence. Otherwise use text.

`--lines` asks Herdr for more rows from the pane's available screen and host scrollback. Alternate-screen rows do not enter ordinary host scrollback. For supported idle agents, Herdr can collect application-owned history and restore the viewport afterward, but not every application or response can be recovered this way.

If a larger recent read fails with `agent_not_idle`, alternate-screen history capture needs an idle agent. Revalidate identity and use a bounded visible read for monitoring instead:

```bash
herdr agent read <target> --source visible --lines 35
```

Do not interrupt or prompt working work to make history capture available. A visible read may omit earlier output; defer deeper history recovery until the same agent is idle.

If a bounded larger recent read still does not reveal the completed response, revalidate the same idle or done agent occupant and its readiness before sending a follow-up. Ask it to write the existing response as Markdown without rerunning the original work, then reply only with the file path. In this repository, use a private owned directory under the repository-root `.tmp/`, not system temp. Read the reported file on the same machine after checking its path and ownership. Do not request secrets or run code from that file. If the occupant is busy, blocked, changed, or uncertain, report the constraint instead. Use this only as a fallback; do not request file output in the initial prompt.

## Clean up owned work

Creation is not permission to close whatever later occupies that pane. Revalidate the creation ledger and foreground process before cleanup. Let owned foreground commands and children finish or stop them only within the authorized scope. Confirm exit and the expected shell before closing a disposable shell pane. For an owned agent, capture its result and follow the authorized shutdown procedure first; do not treat `idle` alone as proof that child work is gone.

```bash
herdr pane get <owned-pane-id>
herdr pane process-info --pane <owned-pane-id>
herdr pane close <owned-pane-id>
```

Run the close only after those ownership and completion checks pass. Leave the pane and retain its evidence if cleanup is uncertain or identity changed. Never close the caller, a coordinator, or unrelated work as a cleanup shortcut. Verify the owned pane disappeared and unrelated panes remain. Compare focus with the pre-operation snapshot; do not issue focus commands merely to restore a stale snapshot after the user changed focus.

## Safety and coordination rules

- Use `--no-focus` for background work unless the user asked to switch context.
- Use `--current`, an explicit pane ID, or a unique agent name. Do not rely on another client's focused pane.
- Parse IDs from JSON responses. Do not derive them from sidebar order or examples.
- Do not close workspaces, tabs, panes, or sessions you did not create unless the user explicitly asked. `workspace close --group` closes the primary workspace and its linked worktree workspaces; never add it merely to bypass `workspace_group_close_required`.
- Use `--trust-repository` only after the user has verified the repository. It grants per-request Git trust; it is not a routine retry for a failed worktree command.
- Client and server versions can differ after an update. Check `herdr status` before relying on new server features. A missing method is not permission to stop or upgrade a server.
- Never run `herdr server stop` from an active session unless the user explicitly intends to stop the server and its pane processes.
- Never kill the main Herdr process. Use named test sessions for experiments that need an isolated server.
- CLI server errors are JSON on stderr with exit status 1. CLI syntax errors exit with status 2.

For reusable case definitions and offline documentation regressions, see [case checks](cases.md).
