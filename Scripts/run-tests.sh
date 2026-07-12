#!/usr/bin/env bash
set -euo pipefail

# Usage: Scripts/run-tests.sh [fast|full]   (default: fast)
CONFIG="${1:-fast}"
PROJECT="Mini Capsule.xcodeproj"
SCHEME="Mini Capsule"
PLAN="MiniCapsule"
COVERAGE_GATE="${COVERAGE_GATE:-85}"   # percent, applied to logic files
LOGIC_PREFIXES=("Mini Capsule/Services/" "Mini Capsule/Settings/" "Mini Capsule/Utilities/" "Mini Capsule/Logging/")

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

# Ensure DEVELOPER_DIR points to Xcode.app (not CommandLineTools) so xcrun
# can find xcodebuild, xcresulttool, xccov, etc.
XCODE_APP="/Applications/Xcode.app/Contents/Developer"
if [ -d "$XCODE_APP" ]; then
  export DEVELOPER_DIR="$XCODE_APP"
fi
XCODEBUILD="$XCODE_APP/usr/bin/xcodebuild"
if ! [ -x "$XCODEBUILD" ]; then
  echo "xcodebuild not found at $XCODEBUILD" >&2
  exit 1
fi

TS="$(date +%Y-%m-%d-%H%M%S)"
OUT="TestResults/$TS"
mkdir -p "$OUT/logs" "$OUT/failures"
# The xctestplan writes per-test chains here (MC_TEST_LOG_DIR points at TestResults/current).
rm -rf "TestResults/current"; mkdir -p "TestResults/current/logs"

echo "▶ Running test plan '$PLAN' config '$CONFIG'…"
set +e
"$XCODEBUILD" test \
  -project "$PROJECT" -scheme "$SCHEME" \
  -destination 'platform=macOS' \
  -testPlan "$PLAN" \
  -resultBundlePath "$OUT/result.xcresult" \
  -enableCodeCoverage YES \
  CODE_SIGNING_ALLOWED=NO \
  CODE_SIGN_IDENTITY="" \
  MC_TEST_LOG_DIR="$ROOT/TestResults/current" \
  2>&1 | tee "$OUT/xcodebuild.log"
TEST_STATUS=${PIPESTATUS[0]}
set -e

# Move the always-captured per-test chains into this run.
if [ -d "TestResults/current/logs" ]; then
  cp -R "TestResults/current/logs/." "$OUT/logs/" 2>/dev/null || true
fi

# --- Extract failures from the .xcresult and promote their chains ---
FAILED_TESTS=()
if [ -d "$OUT/result.xcresult" ]; then
  # xcresulttool JSON shape varies by Xcode; grep test identifiers that failed.
  xcrun xcresulttool get test-results tests --path "$OUT/result.xcresult" --format json > "$OUT/tests.json" 2>/dev/null \
    || xcrun xcresulttool get --format json --path "$OUT/result.xcresult" > "$OUT/tests.json" 2>/dev/null || true
  # Collect names of failing tests (best-effort across Xcode versions).
  while IFS= read -r name; do
    [ -n "$name" ] && FAILED_TESTS+=("$name")
  done < <(grep -oE '"(name|identifier)"[ ]*:[ ]*"[^"]+"' "$OUT/tests.json" 2>/dev/null \
            | sed -E 's/.*: *"([^"]+)".*/\1/' | sort -u | grep -iE 'test' || true)
fi

# Promote: for each failing test, copy its archived chain into failures/.
promoted=0
for f in "${FAILED_TESTS[@]:-}"; do
  safe="$(echo "$f" | sed -E 's/[^A-Za-z0-9]/_/g')"
  if [ -f "$OUT/logs/$safe.jsonl" ]; then
    cp "$OUT/logs/$safe.jsonl" "$OUT/failures/$safe.log"
    promoted=$((promoted+1))
  fi
done

# --- Coverage (scoped to logic files) ---
COV_PCT="n/a"
if [ -d "$OUT/result.xcresult" ]; then
  xcrun xccov view --report --json "$OUT/result.xcresult" > "$OUT/coverage.json" 2>/dev/null || echo '{}' > "$OUT/coverage.json"
  COV_PCT=$(python3 - "$OUT/coverage.json" "${LOGIC_PREFIXES[@]}" <<'PY'
import json, sys
report_path = sys.argv[1]; prefixes = tuple(sys.argv[2:])
try:
    data = json.load(open(report_path))
except Exception:
    print("n/a"); sys.exit(0)
covered = executable = 0
for target in data.get("targets", []):
    for f in target.get("files", []):
        path = f.get("path", "")
        if any(p in path for p in prefixes):
            executable += f.get("executableLines", 0)
            covered += f.get("coveredLines", 0)
print(f"{(100.0*covered/executable):.1f}" if executable else "n/a")
PY
)
fi

# --- Summary ---
{
  echo "# Test run $TS  (config: $CONFIG)"
  echo ""
  echo "- xcodebuild exit: $TEST_STATUS"
  echo "- logic-file coverage: ${COV_PCT}% (gate ${COVERAGE_GATE}%)"
  echo "- failing tests: ${#FAILED_TESTS[@]:-0} (promoted chains: $promoted)"
  echo ""
  if [ "${#FAILED_TESTS[@]:-0}" -gt 0 ]; then
    echo "## Failures (open failures/<name>.log for the full chain)"
    for f in "${FAILED_TESTS[@]:-}"; do echo "- $f"; done
  fi
} > "$OUT/summary.md"
cat "$OUT/summary.md"

# --- Gates ---
GATE_FAIL=0
if [ "$TEST_STATUS" -ne 0 ]; then echo "✗ tests failed"; GATE_FAIL=1; fi
if [ "$COV_PCT" != "n/a" ]; then
  awk "BEGIN{exit !($COV_PCT < $COVERAGE_GATE)}" && { echo "✗ coverage $COV_PCT% < $COVERAGE_GATE%"; GATE_FAIL=1; }
fi
echo "Results: $OUT"
exit $GATE_FAIL
