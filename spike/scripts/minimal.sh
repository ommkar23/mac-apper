#!/bin/bash
set -euo pipefail
root=$(cd "$(dirname "$0")/.." && pwd)
bin="$HOME/Library/Developer/Toolchains/swift-6.4.0-RELEASE.xctoolchain/usr/bin"
sdk=$(xcrun --sdk macosx --show-sdk-path)
run=$(mktemp -d "$root/evidence/minimal.XXXXXX")
test -n "$run" && test -d "$run"
mkdir "$run/tmp"
export TMPDIR="$run/tmp"
env -u SDKROOT "$bin/swiftc" -swift-version 6 -Onone -DDEBUG -parse-as-library -sdk "$sdk" "$root/minimal/CounterRepro.swift" -o "$run/counter-repro" > "$run/build.log" 2>&1
python3 - "$run" <<'PY'
import json, pathlib, subprocess, sys
run = pathlib.Path(sys.argv[1])
child = subprocess.Popen([str(run / 'counter-repro'), str(run / 'counter.png')], stdout=subprocess.PIPE, stderr=subprocess.PIPE)
try:
    stdout, stderr = child.communicate(timeout=15)
except subprocess.TimeoutExpired:
    child.kill()
    child.communicate(timeout=5)
    raise SystemExit('minimal reproduction timed out; direct child reaped')
(run / 'capture.log').write_bytes(stdout + stderr)
(run / 'lifecycle.json').write_text(json.dumps({'pid': child.pid, 'waited': True, 'returncode': child.returncode}) + '\n')
if child.returncode:
    raise SystemExit(child.returncode)
PY
shasum -a 256 "$run/counter.png" > "$run/sha256.txt"
printf '%s\n' "$run"
