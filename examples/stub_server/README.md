# stub_server

A contract-conformant stub of the stratastax platform API for `examples/match_tracker`.

It is built on the code `stx_compiler` generates from the same contract (`lib/gen/contract`, from
`stx.yaml`): requests are decoded and responses encoded with the generated models, and bodies are
checked with the same `*Validation` constants the app uses. A drift between stub and contract is
a compile error or a failing test, not a surprise at runtime.

```sh
dart run stub_server            # http://localhost:9000
dart run stub_server --port 9100
```

Then run the app against it:

```sh
cd ../match_tracker
flutter run -d chrome --dart-define=STX_PLATFORM_BASE_URL=http://localhost:9000
```

| Endpoint                                          | Behaviour                                                                                  |
|---------------------------------------------------|--------------------------------------------------------------------------------------------|
| `GET /api/v1/games/suggestions?query=`            | Seeded games matching the query (`GameRefV1`)                                              |
| `GET /api/v1/games`, `GET /api/v1/games/{id}`     | List / one game                                                                            |
| `POST /api/v1/games`                              | Contract validation, `maxPlayers ≥ minPlayers` (400 with violations), duplicate name (409) |
| `GET /api/v1/ghost-players/suggestions?query=`    | Seeded ghost players (Alice, Bob, Charlie, Charlotte, Diana, Eve)                          |
| `GET /api/v1/matches`, `GET /api/v1/matches/{id}` | Recorded matches                                                                           |
| `POST /api/v1/matches`                            | Validates participants, game and ghost players; `Idempotency-Key` replays                  |
| anything else                                     | `404` problem document naming the missing route                                            |

Errors are RFC 9457 problem documents (`problem_detail.yaml` / `validation_problem_detail.yaml`).
No authentication yet: that arrives with the Keycloak stub endpoints in M4.

## Login

OIDC endpoints like Keycloak's under `/realms/stratastax/protocol/openid-connect/` (`auth`, `token`,
`logout`): Authorization Code with PKCE (S256 only), refresh-token rotation. The login page offers
three users; `kc_idp_hint=google` signs in as `player`, `github` as `admin`.

| User | Scopes |
|---|---|
| admin | every scope of the contract |
| player | every `*-read` scope plus `match-create` |
| viewer | every `*-read` scope |

Every API route checks the bearer token against the security of its contract operation: no or an
invalid token gives 401, a token without one of the scopes 403 (problem documents).

