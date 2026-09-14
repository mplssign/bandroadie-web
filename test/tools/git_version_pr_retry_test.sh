#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/../.." && pwd)"
TEMP_DIR="$(mktemp -d "${TMPDIR:-/tmp}/git-version-pr-test.XXXXXX")"
trap 'rm -rf "$TEMP_DIR"' EXIT

RESPONSES_FILE="$TEMP_DIR/responses"
MERGE_CALLS_FILE="$TEMP_DIR/merge_calls"
OUTPUT_FILE="$TEMP_DIR/output"

cat >"$TEMP_DIR/gh" <<'STUB'
#!/usr/bin/env bash
set -euo pipefail

if [[ "$1" == "pr" && "$2" == "view" ]]; then
  echo "CLEAN"
  exit 0
fi

if [[ "$1" != "pr" || "$2" != "merge" ]]; then
  echo "Unexpected gh invocation: $*" >&2
  exit 64
fi

echo "merge" >>"$GH_MERGE_CALLS_FILE"
CALL_NUMBER="$(wc -l <"$GH_MERGE_CALLS_FILE" | tr -d ' ')"
RESPONSE="$(sed -n "${CALL_NUMBER}p" "$GH_RESPONSES_FILE")"

case "$RESPONSE" in
  success)
    exit 0
    ;;
  transient)
    echo "GraphQL: Pull request is in unstable status" >&2
    exit 1
    ;;
  fatal)
    echo "GraphQL: permission denied" >&2
    exit 1
    ;;
  *)
    echo "Missing scripted response for call $CALL_NUMBER" >&2
    exit 65
    ;;
esac
STUB
chmod +x "$TEMP_DIR/gh"

export PATH="$TEMP_DIR:$PATH"
export GH_RESPONSES_FILE="$RESPONSES_FILE"
export GH_MERGE_CALLS_FILE="$MERGE_CALLS_FILE"
VERSION_PR_SOURCE_ONLY=1 source "$ROOT_DIR/tools/git_version_pr.sh"

sleep() {
  :
}

merge_call_count() {
  wc -l <"$MERGE_CALLS_FILE" | tr -d ' '
}
FAKE_PR_URL="https://example.test/pull/123"

printf '%s\n' transient transient success >"$RESPONSES_FILE"
: >"$MERGE_CALLS_FILE"
if ! (enable_auto_merge_with_retry 123 "$FAKE_PR_URL") >"$OUTPUT_FILE" 2>&1; then
  echo "FAIL transient-twice-then-success" >&2
  exit 1
fi
[[ "$(merge_call_count)" == "3" ]] || exit 1
echo "PASS transient-twice-then-success"

printf '%s\n' fatal >"$RESPONSES_FILE"
: >"$MERGE_CALLS_FILE"
if (enable_auto_merge_with_retry 123 "$FAKE_PR_URL") >"$OUTPUT_FILE" 2>&1; then
  echo "FAIL non-transient-first-attempt" >&2
  exit 1
fi
[[ "$(merge_call_count)" == "1" ]] || exit 1
echo "PASS non-transient-first-attempt"

printf '%s\n' transient transient transient transient transient >"$RESPONSES_FILE"
: >"$MERGE_CALLS_FILE"
if (enable_auto_merge_with_retry 123 "$FAKE_PR_URL") >"$OUTPUT_FILE" 2>&1; then
  echo "FAIL transient-past-budget" >&2
  exit 1
fi
[[ "$(merge_call_count)" == "5" ]] || exit 1
grep -qF "$FAKE_PR_URL" "$OUTPUT_FILE" || exit 1
echo "PASS transient-past-budget"