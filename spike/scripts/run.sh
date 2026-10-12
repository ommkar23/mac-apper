#!/bin/bash
set -euo pipefail
root=$(cd "$(dirname "$0")/.." && pwd)
swift64="$HOME/Library/Developer/Toolchains/swift-6.4.0-RELEASE.xctoolchain/usr/bin/swift"
sdk=$(xcrun --sdk macosx --show-sdk-path)
run=$(mktemp -d "$root/evidence/run.XXXXXX")
test -n "$run" && test -d "$run"
export TMPDIR="$run/tmp"
mkdir "$TMPDIR"
python3 "$root/scripts/make-fixtures.py"
{
  "$swift64" --version
  sw_vers
  xcrun --sdk macosx --show-sdk-version
  printf 'SDK=%s\n' "$sdk"
  xcrun --find actool || true
} > "$run/environment.txt" 2>&1
# No dependencies, no product package, default Swift Build, explicit system SDK.
env -u SDKROOT "$swift64" test --package-path "$root" --scratch-path "$run/build" -j 2 -Xswiftc -sdk -Xswiftc "$sdk" > "$run/test.log" 2>&1
env -u SDKROOT "$swift64" build --package-path "$root" --scratch-path "$run/build" -j 2 -Xswiftc -sdk -Xswiftc "$sdk" > "$run/build.log" 2>&1
bin=$(env -u SDKROOT "$swift64" build --package-path "$root" --scratch-path "$run/build" --show-bin-path)
# Python supervisor bounds only its direct, spike-owned executable to 30 seconds.
python3 - "$bin/render-spike" "$run" "$root/fixtures/local-checker.png" <<'PY'
import json, os, pathlib, subprocess, sys
exe, run, fixture = sys.argv[1:]
lifecycle = []
fixtures = subprocess.run([exe, '--list'], capture_output=True, text=True, check=True, timeout=5).stdout.splitlines()
assert len(fixtures) == 16
for name in [f'{repeat}/{identity}' for repeat in ('first', 'repeat') for identity in fixtures]:
    identity = name.split('/')[1]
    output = pathlib.Path(run) / name
    output.mkdir(parents=True)
    child = subprocess.Popen([exe, str(output), fixture, identity], stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True)
    try:
        stdout, stderr = child.communicate(timeout=30)
    except subprocess.TimeoutExpired:
        child.kill()  # Exact direct owned child only; executable spawns no children.
        stdout, stderr = child.communicate(timeout=5)
        (output / 'capture.log').write_text(stdout + stderr + '\nTimed out; owned child killed/reaped.\n')
        raise SystemExit('capture timeout; no visual verdict')
    (output / 'capture.log').write_text(stdout + stderr)
    try:
        os.kill(child.pid, 0)
        absent = False
    except ProcessLookupError:
        absent = True
    lifecycle.append({'run': name, 'pid': child.pid, 'returncode': child.returncode, 'waited': True, 'ESRCH_after_wait': absent})
    (pathlib.Path(run) / 'lifecycle.json').write_text(json.dumps(lifecycle, indent=2) + '\n')
    if child.returncode or not absent:
        raise SystemExit('owned process exit not confirmed')
PY
python3 "$root/scripts/compare.py" "$run"
printf '%s\n' "$run"
