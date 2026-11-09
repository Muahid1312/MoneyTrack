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
if [[ "$result" -ne 0 && "${GITHUB_ACTIONS:-}" == "true" ]]; then
  python3 - "$log_file" "$label" <<'PYANNOTATION'
import pathlib, sys
text = pathlib.Path(sys.argv[1]).read_text(errors='replace')
lines = [line for line in text.splitlines() if 'error' in line.lower() or line.lstrip().startswith(('e:', '> '))]
messages = text.split('\nFAILED:')[1:] if sys.argv[2] == 'Automated tests' else []
if messages:
    messages = ['FAILED:' + '\n'.join(line[:350] for line in part.splitlines())[:3500] for part in messages]
else:
    messages = ['\n'.join(lines)[-3500:] if lines else text[-3500:]]
for message in messages:
    message = message.replace('%', '%25').replace('\r', '%0D').replace('\n', '%0A')
    print('::error title=CI diagnostics::' + message)
PYANNOTATION
fi
exit "$result"
