#!/usr/bin/env bash
# Keep failure diagnostics readable in CI summaries without discarding test status.
set -euo pipefail
test_log="$(mktemp)"
trap 'rm -f "$test_log"' EXIT
if flutter test --reporter json >"$test_log" 2>&1; then
  result=0
else
  result=$?
fi
python3 - "$test_log" <<'PY'
import json, pathlib, sys
raw = pathlib.Path(sys.argv[1]).read_text(errors='replace')
names, errors, done = {}, {}, {}
for line in raw.splitlines():
    try:
        event = json.loads(line)
    except (ValueError, TypeError):
        continue
    if not isinstance(event, dict):
        continue
    if event.get('type') == 'testStart':
        names[event['test']['id']] = event['test']['name']
    elif event.get('type') == 'error':
        errors.setdefault(event.get('testID'), []).append(event)
    elif event.get('type') == 'testDone':
        done[event['testID']] = event
passed = sum(e.get('result') == 'success' and not e.get('skipped') for e in done.values())
failed = [i for i, e in done.items() if e.get('result') in ('error', 'failure')]
print(f'{passed} tests passed; {len(failed)} failed.')
for i in failed:
    print('\nFAILED:', names.get(i, str(i)))
    for error in errors.get(i, []):
        print(error.get('error', 'Unknown error'))
        print(error.get('stackTrace', '')[:4000])
if not done:
    print(raw[-30000:])
PY
exit "$result"
