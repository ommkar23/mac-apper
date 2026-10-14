# Isolation, identity and cleanup

[Scenario introduction](../README.md) · [Hosting](Hosting.md) · [Recorded evidence](Verification.md#recorded-evidence-not-new-verification)

## Home isolation

- [IsolatedScenarioHome](../Sources/Scenario/IsolatedScenarioHome.swift) creates one owned UUID directory beneath repository-root `.tmp/` with mode 0700. See the [temporary-work contract](../../README.md#temporary-work).
  - `environment` supplies `HOME` and `CFFIXED_USER_HOME` for client/child commands.
  - Pass these overrides to `TestHostService.environment` before host preparation/signing to scope launchd services and their inherited development children too.
  - Client-only HOME overrides and isolated bundle IDs do not prove service-home isolation before automatic workspace reads.
- `privateDirectory` creates nonlinked private relative subdirectories and rejects empty, dot, traversal and backslash components.
- `linkInstalledToolchain` links only the selected installed standalone compiler tree into the owned home for home-relative tool selection. It is an intentional compiler link, not permission to copy/link user home or configuration trees.
- Scope generated projects, stores, histories and child output to test-owned fixtures. Archive only owned evidence outside the home when the case requires retention; do not append to `dist/evidence` or delete unrelated/historical artifacts.
- Private homes and path checks are isolation aids, not an OS sandbox. Original-product GUI verification needs separately approved service isolation; these host APIs do not grant it.

## Selective credential staging

- Credential operations require explicit authorization. Availability does not authorize inspection, refreshing authentication, starting Pi or making model/MCP/Gemini calls.
- `stageCredentialEntry(from:key:relativePath:project:)` reads only one explicitly supplied private JSON file and writes only the selected dictionary entry, optionally transformed by a caller-provided projection.
  - The absolute source is traversed with descriptor-relative no-follow opens. It must be an owner-only regular file owned by the current UID, nonempty and at most 256 KiB.
  - The destination is exclusively created with no-follow and mode 0600 in the private home; it is tracked for `scrubCredentials()`.
  - The API does **not** itself define provider keys, remove refresh tokens, check expiration or prove readiness. Callers own selective projection and lifetime gates.
- Agent-specific access/account/expiry snapshot policy and hosted-time budget belong in the [Agent guide](../../Agent/README.md), not in this generic library contract. Do not copy entire config/home trees or treat a historical auth probe as authorization for a new one.
- Cleanup failure may deliberately retain a staged snapshot along with the fixture. Do not bypass confirmation gates to scrub historical credentials without separate exact-owned safety authorization.

## Directory identity

- Audit the recorded and expected **existing directory**, not literal spelling, suffix matches, prefix replacement or identical nonexistent paths.
- The current shared implementation is `ScenarioDirectoryIdentity` in [Agent scenario support](../../Agent/Tests/AgentScenarioSupport/ScenarioRuntimeAudit.swift), **not an exported Scenario-library API**. Its generic audit contract is documented here because it governs scenario isolation:
  - Descriptor-relative traversal requires absolute existing directories, rejects empty/dot/traversal components, NUL/backslash, missing/non-directory components and untrusted ancestor/leaf links on either side.
  - Identity combines descriptor-derived canonical pathname with device/inode equality. Trusted OS aliases such as `/tmp` and `/var` can identify the same directory as their `/private` spelling.
  - Eligible aliases are root-owned links beneath wholly root-owned, non-group/world-writable ancestors without extended ACLs. Targets undergo the same traversal checks, with at most 16 link expansions. User/project links remain rejected.
  - Unsupported ACL/path lookup and unusual targets fail closed. This test-support audit does not loosen production path validators or authorize reading file contents.
- Retained artifact consumers compare validated existing archive-parent identity but strictly no-follow read the producer's canonical returned file path without rewriting it. The producer/Preview contract belongs to [DevTools](../../apps/built-in/dev-tools/README.md), not Scenario hosting.
- These are point-in-time checks, not a directory lease or protection from subsequent rename/replacement/privileged mutation. Foundation symlink resolution alone is not proof of kernel path spelling.

## Exact-owned process identity

- [OwnedProcessIdentity](../Sources/Scenario/OwnedProcessIdentity.swift) captures PID, kernel executable path and microsecond start identity using `proc_pidpath`/`proc_pidinfo`, then validates that captured identity.
  - Capture while the owned executable still exists. Removing a host first can make kernel-path attribution unavailable.
  - Match exact owned identities, not executable names, broad process scans or reused service identifiers. Unrelated same-binary processes are not cleanup targets.
- `reap()` rejects PIDs ≤1 before probing, checks liveness and revalidates exact path/start identity before each TERM/KILL.
  - TERM waits up to two seconds; if still alive, KILL requires a fresh identity validation. The final wait is up to ten seconds and success requires a fresh `kill(pid, 0)` ESRCH result.
  - Failed validation/signaling can mean an exit race. It counts as already-reaped success only after a fresh ESRCH probe, including after signal-time ESRCH.
  - Live mismatch, uninspectable identity, permissions or observed PID reuse fail closed without further signals. Missing identity by itself is not proof of exit.
- `requireReaped()` independently requires a valid PID and ESRCH. A later read-only PID absence or `proc_pidinfo` disappearance is not a substitute for the cleanup sequence/confirmation.
- Kernel inspection and signaling are separate point-in-time operations, not atomic protection against all PID reuse. Offline exit-race reproduction does not establish the cause/component of an uninstrumented historical mismatch.

## Cleanup order

- Consuming tests own the dependency-aware sequence:
  1. Finish/cancel owned requests and stop the runtime.
  2. Confirm exact-owned inner processes (including Pi/development children where applicable) are reaped; stop/detach subscriptions and archive only owned evidence before fixture file removal.
  3. Record explicit successful inner cleanup confirmation.
  4. Reap exact-owned XPC services while their signed host paths still exist.
  5. Scrub staged credentials, then remove only the owned host/home/project allowed by retention policy.
- `IsolatedScenarioHome.finishHost(cleanupConfirmed:removeFixtures:stopServices:removeHost:)` enforces the outer gate:
  - False inner confirmation throws before service stop or credential scrub, retaining host/home.
  - Service-stop failure propagates before scrub/removal.
  - After successful service stop, tracked credentials are scrubbed.
  - `removeFixtures: false` returns false and retains host/home after scrubbing; true removes the host, then the home and returns true.
  - `remove(cleanupConfirmed:)` likewise refuses an unconfirmed home removal. Confirmation is supplied by tests, not inferred by the home API.
- Host `remove()` has no equivalent inner/service gate. Do not place unconditional host removal in a defer around a potentially failing cleanup sequence.
- **Current provider coverage is narrower than this cleanup contract.** As documented in [DevTools verification](../../apps/built-in/dev-tools/docs/verification.md#cleanup-boundaries-and-source-inspected-limit), Preview explicitly captures/revalidates exact service identity and requires reaping before host removal. Current Plan/Test call `host.remove()` directly; the toolchain fixture uses best-effort project/host removal after development-child ESRCH, without Preview's explicit service-reaping gate.
  - This is a source-inspected limit, not a newly observed leak or test failure. It does not authorize a runtime repair or historical cleanup; review it before execution requiring strict exact-service cleanup.
- A failed assertion can retain evidence **after safe cleanup**; an unconfirmed cleanup must retain fixtures **without bypass**. Neither implies authorization to clean historical retained processes, stores, archives or snapshots.
- Registry teardown and bounded child commands cannot guarantee cleanup after abrupt external termination. Report unconfirmed cleanup as a failure, not a pass obtained by sleeping or deleting paths.
