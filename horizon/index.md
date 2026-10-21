stratastax-flutter generates the boilerplate of a Flutter app from the same contract the services
implement: models, validation, endpoints, scopes, forms, pages, routes, dependency wiring and
guards. The runtime packages build only on `flutter/widgets.dart`, so there is no Material or
Cupertino, and everything is styled through design tokens.

Repository: [stratastax-flutter](https://github.com/buijs-dev/stratastax-flutter) · Design:
[ARCHITECTURE.md](https://github.com/buijs-dev/stratastax-flutter/blob/main/docs/ARCHITECTURE.md) · Example:
[match_tracker](https://github.com/buijs-dev/stratastax-flutter/tree/main/examples/match_tracker).

## Inputs

| Input                                                                                           | Provides                                          |
|-------------------------------------------------------------------------------------------------|---------------------------------------------------|
| OpenAPI specs, local or from this site (pinned in `stx.lock`)                                   | Models, validation, endpoints, scopes             |
| `stx.tokens.yaml`, optionally on the brand layer of the [design system](/design/design-system/) | Design tokens                                     |
| `i18n/*.yaml`, optionally overlaid by the [i18n backend](/technical/components/i18n/)           | All texts                                         |
| Annotated Dart classes in `lib/`                                                                | Forms, pages, routes, data sources, custom fields |
| `stx.yaml`                                                                                      | Backends, contracts, security, sources, output    |

```yaml
sources:
  stratastax: https://docs.stratastax.dev/
backends:
  platform: { baseUrl: http://localhost:9000, auth: oidc }
contracts:
  platformV1: { spec: stratastax:openapi/stratastax.platform.api-v1.yaml, modelSuffix: V1, apiSuffix: ApiV1 }
tokens:
  base: stratastax:design/stratastax.tokens.yaml
  file: stx.tokens.yaml
```

## The compiler
`stx build` runs in two phases. Phase 1 turns the YAML inputs into `lib/gen/{contract,style,i18n}`;
phase 2 reads the annotated Dart sources with the analyzer, resolved against phase 1, merges them
with the contract and generates `lib/gen/app`. Every finding is a diagnostic with a stable code
(`STX-C001` an operation without security, `STX-U001` a required property without a field, ...).

| Command              | Does                                                                                                           |
|----------------------|----------------------------------------------------------------------------------------------------------------|
| `stx build`          | Both phases                                                                                                    |
| `stx watch`          | Builds again on every relevant change; only changed files are written, so hot reload sees exactly what changed |
| `stx scan`           | The merged IR as YAML: per form the operation, backend, scopes, fields and rules                               |
| `stx i18n sync`      | Adds the translation keys generated pages need                                                                 |
| `stx sources update` | Fetches new versions of the remote specs and tokens, shows what changed, updates `stx.lock`                    |

## Runtime packages

| Package               | Role                                                                                        |
|-----------------------|---------------------------------------------------------------------------------------------|
| `stx_core`            | `Result`, `Problem` (RFC 9457), validation, `Endpoint`, scopes                              |
| `stx_http`            | `StxClient` with interceptors: bearer auth, idempotency keys, retry, logging                |
| `stx_security`        | OIDC with PKCE against Keycloak, the session, refresh, scopes from claims; service accounts |
| `stx_style`           | Fixed token slots, `StxTheme`, breakpoints                                                  |
| `stx_i18n`, `stx_icu` | Compiled messages with CLDR plural rules and formats, and translations from a backend       |
| `stx_ui`              | Widgets, fields, forms, pages, the router and guards                                        |
| `stx_lints`           | Analyzer rules: no Material, no raw colours or insets, no string literals as UI text        |

Every generated page is guarded by the scopes of the operations it uses, taken from the contract:
a user without them never sees the page or its navigation item, and the API agrees.
