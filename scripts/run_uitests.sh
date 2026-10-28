#!/bin/bash
# Runs one xcodebuild UI-test pass with a watchdog (xcodebuild can sit after the suite ends) and
# writes "<name>-final-results.txt" (last result per test decides; retries listed) and "<name>-status.txt".
# usage: scripts/run_uitests.sh <name> <scheme> <udid> <timeout-seconds> [extra xcodebuild args...]
set -u
NAME="$1"; SCHEME="$2"; UDID="$3"; LIMIT="$4"; shift 4
LOG="$OUT/$NAME.log"
mkdir -p "$OUT/screenshots"
TEST_RUNNER_SCREENSHOT_DIR="$OUT/screenshots" xcodebuild test -project Discipline.xcodeproj -scheme "$SCHEME" \
  -destination "id=$UDID" "$@" -retry-tests-on-failure -test-iterations 3 \
  -resultBundlePath "$OUT/$NAME.xcresult" CODE_SIGN_IDENTITY="-" > "$LOG" 2>&1 &
XB=$!
START=$(date +%s); LAST=0; QUIET=0; WHY=""
while kill -0 $XB 2>/dev/null; do
  SIZE=$(wc -c < "$LOG")
  if [ "$SIZE" != "$LAST" ]; then LAST=$SIZE; QUIET=0; else QUIET=$((QUIET+10)); fi
  DONE=0; grep -qE "Test Suite 'All tests' (passed|failed)" "$LOG" && DONE=1
  if [ $DONE -eq 1 ] && [ $QUIET -ge 150 ]; then WHY="stopped after the suite ended (log quiet 150 s)"; break; fi
  if [ $DONE -eq 0 ] && [ $QUIET -ge 600 ]; then WHY="HARD: log quiet 600 s before the suite ended"; break; fi
  if [ $(( $(date +%s) - START )) -ge "$LIMIT" ]; then WHY="HARD: over ${LIMIT}s"; break; fi
  sleep 10
done
if kill -0 $XB 2>/dev/null; then kill -TERM $XB; sleep 5; kill -KILL $XB 2>/dev/null; fi
wait $XB 2>/dev/null
echo "watchdog: ${WHY:-none}"
grep -E "Test Case .*(passed|failed)|error:|\*\* (TEST|BUILD)" "$LOG" | tail -80 || true
python3 - "$LOG" "$OUT/$NAME-retries.txt" > "$OUT/$NAME-final-results.txt" <<'PY'
import re, sys
last, runs = {}, {}
for m in re.finditer(r"Test Case '-\[(\S+) (\S+)\]' (passed|failed)", open(sys.argv[1], errors="ignore").read()):
    k = m.group(1) + "/" + m.group(2); last[k] = m.group(3); runs.setdefault(k, []).append(m.group(3))
with open(sys.argv[2], "w") as r:
    for k, v in sorted(runs.items()):
        if len(v) > 1: r.write(f"{k}: {' then '.join(v)}\n")
for k, v in sorted(last.items()): print(v, k)
print("TOTAL", len(last), "PASSED", sum(v == "passed" for v in last.values()))
sys.exit(0 if last and all(v == "passed" for v in last.values()) else 1)
PY
FINAL=$?
cat "$OUT/$NAME-final-results.txt"
if [ $FINAL -ne 0 ] || [[ "$WHY" == HARD* ]]; then echo FAIL > "$OUT/$NAME-status.txt"; else echo PASS > "$OUT/$NAME-status.txt"; fi
perl -e 'alarm shift; exec @ARGV' 180 xcrun xcresulttool export attachments --path "$OUT/$NAME.xcresult" --output-path "$OUT/attachments-$NAME" >/dev/null 2>&1 || true
echo "$NAME: $(cat "$OUT/$NAME-status.txt")"
exit 0
