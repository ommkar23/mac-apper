#!/bin/bash
set -euo pipefail
root=$(cd "$(dirname "$0")/.." && pwd -P)
swift64="$HOME/Library/Developer/Toolchains/swift-6.4.0-RELEASE.xctoolchain/usr/bin/swift"
work=$(python3 "$root/scripts/temporary-directory.py" spike-review-work)
review=$(python3 "$root/scripts/temporary-directory.py" spike-native-review)
export TMPDIR="$(dirname "$work")/"
sdk=$(xcrun --sdk macosx --show-sdk-path)
test -n "$work" && test -d "$work" && test -n "$review" && test -d "$review"
printf 'work=%s\nreview=%s\n' "$work" "$review"
{
  "$swift64" --version
  sw_vers
  printf 'SDK=%s\n' "$sdk"
  xcrun --sdk macosx --show-sdk-version
} > "$work/environment.txt" 2>&1
printf '%s\n' "$review" > "$work/review-path.txt"
python3 "$root/scripts/test-review-capture.py" > "$work/supervisor-tests.log" 2>&1
env -u SDKROOT "$swift64" test --package-path "$root" --scratch-path "$work/build" -j 2 -Xswiftc -sdk -Xswiftc "$sdk" > "$work/test.log" 2>&1
env -u SDKROOT "$swift64" build --package-path "$root" --scratch-path "$work/build" -j 2 -Xswiftc -sdk -Xswiftc "$sdk" > "$work/build.log" 2>&1
bin=$(env -u SDKROOT "$swift64" build --package-path "$root" --scratch-path "$work/build" --show-bin-path)
python3 "$root/scripts/review-capture.py" "$bin/render-spike" "$work" "$review" "$root/fixtures/local-checker.png" | tee "$work/result.txt"
# No cleanup/deletion: builds, logs, repeat PNGs and failed evidence remain outside review.
