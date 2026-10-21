#!/usr/bin/env bash
# The match_tracker demo: stub server (OIDC + API) on :9000, `stx watch`, and the app in Chrome on
# :8085. Edit stx.yaml, a translation or an annotated class and press `r` in this terminal (hot
# reload) to see the regenerated code. Ctrl-C (or `q`) stops everything.
set -euo pipefail
root="$(cd "$(dirname "$0")/.." && pwd)"
pids=()
cleanup() { for pid in "${pids[@]}"; do kill "$pid" 2>/dev/null || true; done; }
trap cleanup EXIT

(cd "$root/examples/stub_server" && dart run stub_server --port 9000) &
pids+=($!)
(cd "$root/examples/match_tracker" && dart run stx_compiler:stx watch) &
pids+=($!)

cd "$root/examples/match_tracker"
flutter run -d chrome --web-port 8085 --dart-define=STX_PLATFORM_BASE_URL=http://localhost:9000 \
  --dart-define=STX_I18N_CLIENT_SECRET=stub-secret  # the stub's i18n service account
