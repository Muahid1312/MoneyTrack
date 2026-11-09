#!/usr/bin/env bash
# Run from a Flutter-enabled workstation or CI executor; no user data is opened.
set -euo pipefail
cd "$(dirname "$0")/.."
command -v flutter >/dev/null || { echo 'Flutter SDK is required.' >&2; exit 127; }
command -v dart >/dev/null || { echo 'Dart SDK is required.' >&2; exit 127; }
flutter pub get --enforce-lockfile
dart format lib test
flutter analyze
flutter test
flutter build apk --release
if [[ -n "${MONEYTRACK_RELEASE_STORE_FILE:-}" ]]; then
  echo 'Release signing was requested; verify the APK certificate before distribution.'
else
  echo 'No release credentials supplied. Artifact is unsigned; not for public distribution.'
fi
for apk in build/app/outputs/flutter-apk/*.apk build/app/outputs/apk/release/*.apk; do
  [[ -f "$apk" ]] || continue
  wc -c "$apk"
  sha256sum "$apk"
done
