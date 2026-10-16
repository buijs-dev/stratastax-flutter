#!/usr/bin/env bash
# The runtime UI packages may only depend on package:flutter/widgets.dart (docs/ARCHITECTURE.md §2).
set -euo pipefail
cd "$(dirname "$0")/.."

packages=(packages/stx_style packages/stx_i18n packages/stx_ui)
pattern="package:flutter/(material|cupertino)\.dart"

if grep -rnE "$pattern" "${packages[@]}" --include='*.dart'; then
  echo "error: material/cupertino import found in a widgets-only package" >&2
  exit 1
fi
echo "ok: ${packages[*]} only use flutter/widgets"
