# stx_lints

Analyzer rules that keep stratastax-flutter apps token-only, string-free and on flutter/widgets.

| Rule | Flags |
|---|---|
| `stx_no_material_import` | `import 'package:flutter/material.dart'` / `cupertino.dart` |
| `stx_no_raw_color` | `Color(…)` — use a `ColorToken` (or `color.extend` in stx.tokens.yaml) |
| `stx_no_raw_insets` | `EdgeInsets…(…)` — use `StxInsets`, a `gap:` or `Pad`/`Gaps` |
| `stx_no_string_in_ui` | a string literal in `Msg.data(…)` or `Text(…)` — add a key to i18n/*.yaml |
| `stx_no_generated_tokens` | `ColorToken.generated` / `ButtonVariant.generated` — declare the token under `extend` |

The rules apply to `lib/` of apps: generated code (`lib/gen/`), the stx packages, tests and tools
are exempt. Enable the plugin in the `analysis_options.yaml` at the root of the workspace (or of
the app when it is not in a workspace):

```yaml
plugins:
  stx_lints:
    path: packages/stx_lints   # or a version once published
```
