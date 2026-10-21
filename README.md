# stratastax-flutter

Annotation- and contract-driven Flutter framework for stratastax. It is the frontend counterpart of
`stratastax-entity`, `stratastax-codegen` and `stratastax-contract`.

- **Contract first:** OpenAPI provides models, validation, endpoints and scopes.
- **Annotations → IR → codegen:** forms, pages, routes, DI and guards are generated.
- **`flutter/widgets` only:** no material or cupertino. Styling goes through design tokens
  (`stx.tokens.yaml`) and text through i18n keys (`i18n/*.yaml`).

The design is in [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md). Example inputs and generated output
are in [docs/examples](docs/examples).

## Packages

| Package | Role |
|---|---|
| `stx_annotations` | Annotations (pure Dart) |
| `stx_core` | Runtime types for generated code |
| `stx_icu` | ICU MessageFormat parser (pure Dart) |
| `stx_http` | HTTP client with interceptors |
| `stx_security` | OIDC/PKCE, session, scopes, service accounts |
| `stx_style` | Token schema and theme |
| `stx_i18n` | Compiled i18n runtime, overlaid by translations from a backend |
| `stx_ui` | Widgets (`flutter/widgets` only) |
| `stx_compiler` | The `stx` CLI |
| `stx_lints` | Analyzer rules for consumer apps |

## Development

```sh
dart pub get
dart analyze
dart run stx_compiler:stx --help
```

## Demo

```sh
tool/demo.sh   # stub server (OIDC + API) on :9000, stx watch, and the example app in Chrome on :8085
```

Sign in as `admin`, `player` or `viewer` and create a match; see
[`examples/match_tracker/README.md`](examples/match_tracker/README.md) for the walkthrough and
[`docs/ARCHITECTURE.md`](docs/ARCHITECTURE.md) for the design.

## Documentation

The Stratastax documentation is on [docs.stratastax.dev](https://docs.stratastax.dev/). Its page there is [Flutter](https://docs.stratastax.dev/technical/components/flutter/); see also the [design system](https://docs.stratastax.dev/design/design-system/).

## Related Stratastax projects

- [stratastax-contract](https://github.com/buijs-dev/stratastax-contract) - the OpenAPI specs the compiler generates clients, validation and forms from
- [stratastax-design](https://github.com/buijs-dev/stratastax-design) - the brand tokens (`tokens.base` in stx.yaml)
- [stratastax-docs](https://github.com/buijs-dev/stratastax-docs) - the documentation site that publishes the specs, tokens and this repository's `horizon/` pages
- [stratastax-engine](https://github.com/buijs-dev/stratastax-engine) - the platform API the example app talks to
