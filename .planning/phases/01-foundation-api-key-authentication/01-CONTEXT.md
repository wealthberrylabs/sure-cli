# Phase 1: Foundation & API-Key Authentication - Context

**Gathered:** 2026-10-31
**Status:** Ready for planning

<domain>
## Phase Boundary

Deliver an installable Ruby gem that can target a Sure server, authenticate with
an API key, store the credential safely, and prove the shared request pipeline
through `sure doctor` and a raw `sure api` escape hatch. This phase establishes
the command grammar, output contract, exit codes, and configuration foundation
that every later phase inherits.

It does not add read/reporting commands, write commands, imports, sync, exports,
OAuth, AI chats, or platform handoff. Those belong to Phases 2–7.

</domain>

<decisions>
## Implementation Decisions

### Command Grammar & Naming

- **D-01:** Commands are **noun-first plural**: `sure accounts list`, `sure transactions add`, `sure budgets show`. Every domain gets a plural noun command group with verbs underneath.
- **D-02:** Ship a **small, documented set of high-frequency aliases**: `tx` → `transactions`, `acct` → `accounts`, `cf` → `cashflow`. Aliases are discoverable in help, not hidden. Generated copy-commands should prefer canonical full names to keep shared commands unambiguous.
- **D-03:** Reporting commands live at the top level (`sure cashflow`, `sure balance-sheet`, `sure budgets`) and are also reachable through a `sure reports <name>` alias group.
- **D-04:** Destructive commands use **`delete` only**. Do not add an `rm` alias. `delete` always goes through the Phase 3 preview/confirmation framework; Phase 1 only establishes the naming convention.

### Credential Storage & Login UX

- **D-05:** Credentials are **keychain-first**: macOS Keychain via `security`, Linux Secret Service via `secret-tool`. When no keychain is available, fall back to an atomic **0600** file in a **0700** directory.
- **D-06:** The plaintext fallback is **automatic with a one-time warning per profile**, and `sure doctor` reports the active storage mode. Do not require a separate opt-in flag.
- **D-07:** `sure auth login` accepts a key through a **hidden prompt** by default, plus `--api-key-file`, `--api-key-stdin`, and `SURE_API_KEY`. Do **not** provide a `--api-key` argv flag, so keys never appear in process lists or shell history.
- **D-08:** `sure auth logout` deletes the credential locally and explains that the API key must be revoked in **Sure Settings → API Keys**. The public API has no API-key revocation endpoint, so do not pretend logout revokes it.
- **D-09:** `sure auth status` reports the active profile, server URL, user, key name, scopes, authentication method, and rate-limit tier. It must never print the key itself.
- **D-10:** API keys use Sure's existing `read` and `read_write` scopes. The CLI preflights the scope before any write command and fails with an actionable message instead of sending a request that will 403.

### Output Contract & Exit Codes

- **D-11:** Default output is **a table on a TTY and JSON when stdout is piped**. `--table`, `--json`, `--csv`, and `--ndjson` override the default explicitly.
- **D-12:** JSON output uses a stable envelope:
  ```json
  {
    "data": …,
    "meta": {
      "schema_version": 1,
      "pagination": { … },
      "as_of": "…",
      "rate_limit": { … },
      "warnings": [ … ]
    }
  }
  ```
  Raw server payloads are available only when explicitly requested (for example `--raw`), never as the default contract.
- **D-13:** Exit codes are semantic and stable:
  - `0` success
  - `1` general error
  - `2` usage/option error
  - `3` authentication or insufficient scope
  - `4` not found
  - `5` validation/conflict
  - `6` rate limited
  - `7` partial batch failure
  - `8` network/TLS/server unavailable
  - `9` timeout
- **D-14:** Data goes to **stdout**; errors, warnings, and progress go to **stderr**. Color is enabled only on a TTY, honors `NO_COLOR` and `--no-color`, and is disabled when piped. `--quiet` suppresses non-error output; `--verbose` adds request IDs and timings.
- **D-15:** The CLI never prompts when stdin is not a TTY. It exits nonzero with an actionable message directing the user to the relevant flag or environment variable.
- **D-16:** Field selection (`--fields`) and machine formats apply to every command group from the start, so later commands do not need a second output layer.

### the agent's Discretion

The planner may decide these without another user round-trip:

- Exact YAML config schema and key names; profile precedence should be flag > environment > profile > defaults.
- HTTP timeout defaults and retry policy. Recommended starting point: 5s open, 30s read; retry only idempotent `GET`/`HEAD`; bounded backoff with jitter; honor `Retry-After` and `X-RateLimit-*`.
- Keychain service/account naming and the precise atomic-write implementation.
- Table columns and help text wording, as long as they follow the output contract.
- The order and exact checks in `sure doctor` (connectivity, auth, scope, TLS, clock skew, config permissions, server capability).
- Whether aliases appear in generated copy-commands; D-02 recommends canonical names.
- Raw `sure api` safety: at minimum require confirmation for `DELETE`/`PATCH`/`POST` on a TTY, support `--dry-run`, and redact auth headers. Do not build a server-side allowlist in Phase 1.

### Folded Todos

None — no pending todos matched this phase.

</decisions>

<canonical_refs>
## Canonical References

**Downstream agents MUST read these before planning or implementing.**

### Planning
- `.planning/PROJECT.md` — product context, core value, constraints, key decisions
- `.planning/REQUIREMENTS.md` — FOUND-01…10, AUTH-01…03/08/09, SAFE-05/06
- `.planning/ROADMAP.md` § Phase 1 — goal, success criteria, plan breakdown
- `.planning/research/STACK.md` — Thor, Faraday, keychain, testing, packaging choices
- `.planning/research/ARCHITECTURE.md` — layered design and proposed `cli/` tree
- `.planning/research/FEATURES.md` — command taxonomy, output and scripting contracts
- `.planning/research/PITFALLS.md` — credential, money, pagination, and retry pitfalls

### API Contract & Authentication
- `docs/api/openapi.yaml` — `securitySchemes` (`apiKeyAuth`, `oauth2`), paths, error shapes
- `docs/clients.md` — client overview and custom API client guidance
- `docs/llm-guides/architecture.md` — API auth, tenancy, and provider conventions
- `app/controllers/api/v1/base_controller.rb` — OAuth/API-key auth, scope checks, rate-limit headers, error JSON
- `app/controllers/api/v1/usage_controller.rb` — `GET /api/v1/usage` response for `auth status`
- `app/models/api_key.rb` — key scopes, active/revoked states, key format
- `app/controllers/settings/api_keys_controller.rb` — key creation and revocation flow referenced by logout guidance
- `config/initializers/doorkeeper.rb` — OAuth scopes and PKCE configuration (Phase 5 dependency)
- `config/routes.rb` — `/api/v1` namespace and undocumented `POST /sync`, `GET /usage` routes

### Repository Conventions
- `AGENTS.md` — mandatory repository guidance, testing, API consistency rules
- `docs/llm-guides/development.md` — test, lint, and pre-PR checklist
- `.ruby-version`, `Gemfile`, `Gemfile.lock` — Ruby 3.4.9 and server dependencies
- `bin/sure-backup` — existing operator-script conventions for usage text and safe defaults

</canonical_refs>

<code_context>
## Existing Code Insights

### Reusable Assets
- **`Api::V1::BaseController`** — already implements dual auth, scope hierarchy (`read_write` includes `read`), rate-limit headers, and consistent JSON error shapes. The CLI should mirror these semantics, not invent parallel ones.
- **`ApiKey` model** — defines key scopes (`read`, `read_write`), active/revoked/expired states, and the opaque 64-hex key format.
- **`GET /api/v1/usage`** — returns key name, scopes, last used, tier, limit, remaining, and reset time; this is the data source for `sure auth status`.
- **`bin/sure-backup`** — a mature shell CLI in the repo with usage text, `log`/`warn`/`die` conventions, and safe defaults; useful prior art for `doctor` and destructive confirmations.
- **`docs/api/openapi.yaml`** — pinned contract for the HTTP layer and future contract tests.

### Established Patterns
- API auth is header-based: `X-Api-Key` or `Authorization: Bearer`; never query parameters.
- Family context is derived server-side from the credential; the CLI must not send or assume a family ID.
- Errors are JSON with `error` and `message`; rate limits add `X-RateLimit-Limit`, `X-RateLimit-Remaining`, `X-RateLimit-Reset`, and `Retry-After` (seconds remaining, not an epoch).
- The repo uses Minitest, RuboCop Omakase, Brakeman, and a full pre-PR checklist; the CLI gem should have its own isolated test and lint tasks.
- Existing clients are separate packages (`desktop/`, `mobile/`); a new `cli/` directory matches that pattern.

### Integration Points
- New gem at `cli/` with `exe/sure`; do not add runtime dependencies to the root Rails bundle.
- Root CI may add a `cli` job later; Phase 1 should make `cd cli && bundle exec rake test` self-contained.
- `sure doctor` and `sure auth status` consume `GET /api/v1/usage` and a minimal accounts probe; no new server endpoint is required.
- Phase 7 will consume the command catalog generated here; keep command metadata machine-readable from day one.

</code_context>

<specifics>
## Specific Ideas

- Use `sure accounts list` and `sure transactions add` as the reference examples in help and tests.
- The `--api-key-stdin` path should work as `printf '%s' "$SURE_API_KEY" | sure auth login --api-key-stdin`.
- `sure doctor` should print a compact checklist with pass/fail and a suggested fix for each failure, not a raw stack trace.
- `sure api GET /api/v1/accounts` is the smoke test for the entire pipeline.
- Generated commands should always use full canonical names even when aliases exist.

</specifics>

<deferred>
## Deferred Ideas

None — discussion stayed within phase scope.

</deferred>

---

*Phase: 1-Foundation & API-Key Authentication*
*Context gathered: 2026-10-31*
