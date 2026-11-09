#!/usr/bin/env bash
# Publish build diagnostics to the workflow summary; do not pass secrets as args.
set -euo pipefail
label="$1"
shift
log_file="$(mktemp)"
trap 'rm -f "$log_file"' EXIT
if "$@" >"$log_file" 2>&1; then
  result=0
else
  result=$?
fi
cat "$log_file"
if [[ -n "${GITHUB_STEP_SUMMARY:-}" ]]; then
  {
    echo "### $label — exit $result"
    echo '<pre>'
    python3 - "$log_file" <<'PY'
import html, pathlib, sys
text = pathlib.Path(sys.argv[1]).read_text(errors='replace')
print(html.escape(text[-50000:]))
PY
    echo '</pre>'
  } >> "$GITHUB_STEP_SUMMARY"
fi
exit "$result"
