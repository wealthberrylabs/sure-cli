# Pitfalls Research

**Domain:** First-party Ruby CLI for a self-hosted personal-finance server (Sure)
**Researched:** 2026-10-31
**Confidence:** HIGH — verified against the checked-in API, controllers, and guides, not only public docs.
**Severity:** Critical = wrong money, data loss, or credential compromise. High = broken automation or misleading output. Medium = friction.
**Phase key (recommended):** 1 Foundation/transport · 2 Read/report · 3 Write/destructive · 4 Imports/sync/exports · 5 Browser OAuth/credentials · 6 AI chat · 7 Platform handoff/deep links · 8 Contract hardening/release. Preserve the named capability if phases are renumbered.

## Critical Pitfalls

### Pitfall 1: Building a second financial engine in the CLI — CRITICAL

- **What goes wrong:** The CLI sums transactions or reconstructs cash flow/net worth. Results diverge because Sure excludes split parents, excludes `funds_movement`/`cc_payment`/`one_time`, counts `loan_payment` as an expense regardless of sign, honours `investment_contribution` settings, and applies sharing/report preferences. Local dates also pick the wrong family-time-zone period.
- **Why it happens:** Local aggregation feels cheaper than extra calls; rows look complete enough, and `Date.today` feels harmless.
- **How to avoid:** Treat `/cash_flow`, `/balance_sheet`, account balances, and report endpoints as authoritative. Format and filter server values; never re-derive totals. Use the family/server zone for “today” and month bounds, and send explicit ISO dates. If a grouping is not exposed, say so or label it an unverified ad-hoc sum.
- **Warning signs:** Any `sum`/`reduce` over transaction amounts; totals differ by transfer/split amounts; “this month” is empty on day one; report changes with `TZ`.
- **Phase to address:** Phase 2; regression-tested in Phase 8.

---

### Pitfall 2: Treating display strings, floats, or cents as exact money — CRITICAL

- **What goes wrong:** `amount` is localized and display-rounded; `amount_cents` is rounded and `signed_amount_cents` is derived from classification. Parsing either as exact breaks split sums and large values. Ruby `Float` adds binary drift, and minor units vary by currency (JPY 1, KWD 1000). Adding USD and EUR amounts either raises `Money::CurrencyMismatchError` or yields nonsense.
- **Why it happens:** `amount` is the obvious field and looks numeric; balance-sheet values are already in family currency, so every amount is assumed to be.
- **How to avoid:** Parse `amount_decimal` as a string into `BigDecimal`; keep it a string on output. Use `amount` only for display and `*_cents` only for explicit minor units. Carry currency with every value and refuse cross-currency arithmetic. If conversion is unavoidable, use the server’s dated rate and print the date.
- **Warning signs:** `to_f`, `Float`, `round(2)`, `* 100`; mixed-currency fixture passes only because it is USD; split rejected by the server.
- **Phase to address:** Phase 1 (money value object), used from Phase 2.

---

### Pitfall 3: Assuming one pagination envelope and stable page numbers — HIGH

- **What goes wrong:** Most collections return `pagination` (page-based, no `next_page`). `imports`/`rules`/`rule_runs` use `meta` with `current_page`/`next_page`; `syncs`/`family_exports` use `meta` with `page` and no `next_page`. Item keys differ (`transactions`, `accounts`, `data`). Page traversal duplicates or skips rows when data changes, and an oversized `per_page` may silently return 25.
- **Why it happens:** OpenAPI shows both shapes; the first endpoint tested looks representative.
- **How to avoid:** Build a per-collection normalizer with envelope, total, and item keys plus a contract test. Follow `next_page` when present, otherwise stop at `total_pages`; deduplicate by ID and warn if `total_count` changed. Never trust a requested page size.
- **Warning signs:** Nil errors on page 2; export row count differs from `total_count`; a complete list misses records edited mid-run.
- **Phase to address:** Phase 1 (HTTP layer), verified per endpoint in Phase 2.

---

### Pitfall 4: Scraping thousands of rows instead of using the export contract — HIGH

- **What goes wrong:** Full-history commands page transactions at 100 rows/request. Managed API keys are limited to 100 requests/hour (standard tier), so only ~10,000 rows/hour are reachable before `429`. Rows are heavy (embedded account, category, merchant, tags, split, transfer).
- **Why it happens:** Pagination is the obvious primitive; async family export looks like more work.
- **How to avoid:** Use `POST /family_exports` (admin-only, `202`), status polling, and the streaming download for bulk. Require date/account filters and print an estimate before large reads; offer `--limit` and explicit `--all`. Respect `X-RateLimit-*`/`Retry-After` and never retry `429` immediately.
- **Warning signs:** Dozens of page requests before any output; rate-limit headers vanish from logs; whole ZIP loaded into memory.
- **Phase to address:** Phase 4; read limits enforced in Phase 2.

---

### Pitfall 5: Retrying writes without idempotency, or after a timeout — CRITICAL

- **What goes wrong:** A create times out after commit; retry duplicates a transaction, trade, valuation, import, or sync. Only transaction create has built-in idempotency (`source` + `external_id`); there is no generic `Idempotency-Key` header.
- **Why it happens:** Generic HTTP clients retry timeouts/5xx by default; “retry three times” sounds robust.
- **How to avoid:** Retry only GET/HEAD automatically. For transaction create, always send stable `source` + `external_id` and accept the existing-record response (HTTP 200, not 201) as success. Import sessions use `client_session_id`/`client_chunk_id`; ordinary imports and most other creates are not idempotent. For those writes, report “outcome unknown” with a safe inspection command. Use bounded backoff with jitter and honour `Retry-After`.
- **Warning signs:** Duplicate transactions after flaky networks; retry logic in the generic request method; only `201` accepted; three POSTs for one intent.
- **Phase to address:** Phase 1 (policy), applied to every write in Phase 3.

---

### Pitfall 6: Destructive or bulk commands without real preview and partial-failure handling — CRITICAL

- **What goes wrong:** Transaction delete is permanent and triggers a sync; deleting a split destroys children; `users/reset` queues an async family-wide financial wipe. A `--dry-run` that only prints “would delete” is not a preview. A batch loop prints “done” and exits 0 after 17 `422`/`403` failures.
- **Why it happens:** CRUD symmetry makes delete look ordinary; batch support starts as `each`.
- **How to avoid:** Resolve exact resources and show ID, date, amount, account, currency, and count (for reset, per-entity counts). Require `--yes` and, for reset/account deletion, a typed phrase; never prompt when stdin is not a TTY. Dry-run must send no writes. Emit per-item results and a summary, exit nonzero on any failure, stop-on-error for destructive batches, and write a resumable manifest.
- **Warning signs:** Confirmation only asks “Are you sure?”; `--force` skips preview; exit 0 with failures in output; reset command is easy to find but hard to abort.
- **Phase to address:** Phase 3.

---

### Pitfall 7: Treating `202`, `pending`, or `syncing` as completion — HIGH

- **What goes wrong:** Imports, import-session publish, family exports, sync, and chat are asynchronous. Import statuses include `pending`/`importing`/`complete`/`failed`/`reverting`/`revert_failed`; exports use `pending`/`processing`/`completed`/`failed`; syncs expose `in_progress`/`terminal`; export download returns `409` until ready. The CLI reports success too early or polls forever.
- **Why it happens:** A `2xx` feels finished and often contains a plausible object.
- **How to avoid:** Model accepted → poll with backoff → terminal status; surface ID/status URL, enforce a timeout, and explain resume. Never poll faster than a few seconds. On `failed`, print the sanitized error and next step. Note that `POST /sync` triggers a family-wide sync, not one account.
- **Warning signs:** “Import complete” before rows exist; spinner with no timeout; repeated polls hit `429`; two syncs overlap.
- **Phase to address:** Phase 4; chat polling in Phase 6.

---

### Pitfall 8: Leaking API keys through argv, environment, logs, or config — CRITICAL

- **What goes wrong:** A key flag lands in shell history and `ps`; debug output dumps `X-Api-Key`; crash reports echo headers; config is world-readable or committed; a copied `curl` example contains a live key. Keys are opaque, long-lived, and `read_write` keys can alter financial data.
- **Why it happens:** A flag is the fastest login UX; HTTP libraries log requests at debug level.
- **How to avoid:** Prefer an interactive no-echo prompt, stdin, or a credential helper; omit a key flag or warn loudly. Store only the secret in the OS keychain keyed by service + canonical origin + profile + user. Fall back to a `0600` file outside the repo with a warning on headless Linux. Redact `Authorization`, `X-Api-Key`, cookies, and token-shaped strings in all output, including `--debug`.
- **Warning signs:** Keys visible in `ps`/history; config mode `0644`; debug logs contain header values; docs show a real-looking key.
- **Phase to address:** Phase 1 (redaction/config), hardened in Phase 5.

---

### Pitfall 9: Inferring authorization from scope, family role, or cached accounts — CRITICAL

- **What goes wrong:** A `read_write` key is assumed to permit every write. Scope says what the key may do; sharing says what its owner may do. Listing uses `accessible_by` (includes read-only shares); transaction create uses `writable_by` (owner or `full_control`); annotation has a separate permission set. Admins are not exempt. Guests are read-only for family configuration, but not every endpoint rejects guest writes identically. Caches/suggestions can leak inaccessible account names or balances.
- **Why it happens:** One user, one family, so membership feels sufficient. `403` is treated as a bug.
- **How to avoid:** Treat the server as authority; distinguish `401` (credential), `403` (scope/resource permission), and `404` (hidden resource). Do not pre-filter writes from a cached list or retry with broader scope. Key every cache/completion by server + user + profile; clear on switch/logout. Test owner, full-control, read-only, guest, and admin fixtures.
- **Warning signs:** Read-only shared account appears writable; writes fail only on shared accounts; code branches on `admin?`; switching servers shows stale data.
- **Phase to address:** Phase 2 (reads), Phase 3 (writes), re-tested in Phase 8.

---

### Pitfall 10: A brittle OAuth loopback flow (PKCE, DCR, refresh, ports) — CRITICAL

- **What goes wrong:** Registering “Sure CLI” fails because names containing “Sure” as a word are reserved. DCR returns a public client with no secret (`token_endpoint_auth_method: none`), yet the CLI expects one. PKCE is omitted although the server forces it. The CLI registers one port and listens on another, treats the one-year access token as permanent, never refreshes, or uses `/api/v1/auth/refresh` (mobile/device-specific, rotating) instead of `/oauth/token`.
- **Why it happens:** OAuth tutorials assume a fixed web callback and confidential client; Sure’s DCR endpoint is non-standard (`/register`).
- **How to avoid:** Authorization code + PKCE S256 + `state`; listen only on `127.0.0.1`/`::1`. Bind the port first, then register that exact redirect URI (or a small fixed port set). Send client ID only; exchange at `/oauth/token`. Store tokens atomically, refresh proactively, and handle rotation/revocation by re-authenticating. Support manual code paste for headless/SSH. Choose a client name without the word “Sure”.
- **Warning signs:** `invalid_client_metadata` at registration; `invalid_grant` at exchange; port-in-use after registration; silent logout at expiry.
- **Phase to address:** Phase 5; do not block the API-key MVP on it.

---

### Pitfall 11: Assuming the docs, version, and deployment mode match the server — HIGH

- **What goes wrong:** The CLI targets current `openapi.yaml`, but self-hosted instances can lag a minor version. Undocumented routes exist (`POST /api/v1/sync` is routed but absent from OpenAPI), some documented operations do not exist (rules/budgets are read-only; imports have no revert endpoint), and managed/self-hosted differ: self-hosted disables API-key rate limiting, and provider/AI/registration availability varies. A feature works in CI and 404s for a user.
- **Why it happens:** OpenAPI is generated from current specs, not every deployed version; “full parity” is read as “every web action has an endpoint”.
- **How to avoid:** Maintain a capability matrix and detect at runtime; turn `404`/`403`/`422` into “unsupported on this server” with version and upgrade hint. Pin contract tests to current and previous minor. Do not code-generate the CLI blindly. Treat managed vs self-hosted as first-class config.
- **Warning signs:** New commands 404 on a supported release; docs advertise edits the API lacks; rate-limit assumptions differ by mode; errors omit version.
- **Phase to address:** Phase 1 (capability/version), Phase 8 (compatibility matrix).

---

### Pitfall 12: Interpolating server data into copyable commands and deep links — CRITICAL

- **What goes wrong:** A copied command includes an account name like `$(rm -rf ~)` or a newline; a `sure://` link embeds unencoded names/IDs or a token. The CLI shells out with an unescaped value.
- **Why it happens:** Templates treat account names as trusted labels; links are built by concatenation.
- **How to avoid:** Build commands from IDs, never names, and escape every dynamic value with `Shellwords.escape`. Reject control characters/newlines. Percent-encode `sure://` segments and validate UUIDs. Never put credentials or full notes in a link. The platform displays commands but never executes them. Test quotes, spaces, `$()`, backticks, newlines, and Unicode.
- **Warning signs:** Copied command breaks on an apostrophe; `eval`/backticks/`system` with interpolation; token in a URL.
- **Phase to address:** Phase 7; escaping helper in Phase 1.

---

### Pitfall 13: Mixing human and machine output, or inventing exit codes per command — HIGH

- **What goes wrong:** JSON is polluted by progress dots, warnings, colors, or “Success!”; a piped command blocks on a prompt; scripts cannot distinguish auth failure from not-found because everything exits 1; tables misalign on CJK/emoji or crash under `LC_ALL=C`.
- **Why it happens:** Output is written with `puts` wherever convenient; exit codes are an afterthought.
- **How to avoid:** Stdout carries only the requested payload; progress/warnings/prompts go to stderr. Choose format explicitly (`--json`, `--csv`, `--table`); non-TTY defaults to JSON but `--table` remains available. Define stable exit codes (success, usage, auth, not-found, conflict/partial, rate-limit, network, unsupported, interrupted). Never prompt when stdin is not a TTY; support `--yes`. Honour `NO_COLOR`/`FORCE_COLOR`, disable color in JSON, compute Unicode width, degrade to ASCII, and handle `EPIPE` quietly.
- **Warning signs:** `--json | jq` fails; Ctrl-C prints a stack trace; same failure exits 0 in one command and 1 in another; wide characters break tables.
- **Phase to address:** Phase 1 (output/exit contract), audited in Phase 8.

---

### Pitfall 14: Turning AI chat into a local agent runtime — HIGH

- **What goes wrong:** The CLI invents streaming the API does not provide, executes `tool_calls` locally, auto-approves model-suggested writes, or treats chat output as authoritative financial data. Chat is async: POST returns a user message; the answer appears only after polling `GET /chats/{id}`. Tool calls are already executed server-side with results.
- **Why it happens:** “AI chat” implies streaming and tools, and responses contain actionable-looking function names/arguments.
- **How to avoid:** Poll with backoff until an assistant message appears; do not add SSE. Render tool calls as provenance (“read accounts”, “ran cash-flow”), never re-execute. Require explicit confirmation before converting any suggestion into a write command. Keep AI separate from MCP and deterministic reports. Respect `ai_enabled`/feature-disabled errors; avoid secrets and unnecessary PII in prompts.
- **Warning signs:** A local tool dispatcher appears; writes after a model message without confirmation; fake streaming by 100 ms polling; chat answers used as totals.
- **Phase to address:** Phase 6.

---

### Pitfall 15: A test suite that depends on a live, moving server — HIGH

- **What goes wrong:** CI hits a real instance, fails on weekends/month-end, burns the 100/hour key budget, depends on async jobs, or breaks when fixtures change. VCR cassettes encode yesterday’s pagination envelope and hide contract drift. “Green” means the server was up, not that the CLI is correct.
- **Why it happens:** The API is the only truth, so integration tests are easy; mocking feels like testing the mock.
- **How to avoid:** Use a deterministic fixture server/recorded contracts for unit/contract tests plus a small, tagged integration suite against a seeded Docker instance. Freeze time/FX, pin server version, reset state per run. Snapshot each collection envelope and required field. Test `401`/`403`/`404`/`409`/`422`/`429`/`5xx`, timeouts, partial batches, `EPIPE`, SIGINT, and one test per supported minor.
- **Warning signs:** Tests fail near midnight/month-end; retries mask flakiness; hand-edited cassettes; no exit-code/stderr assertions; CI needs a human-started server.
- **Phase to address:** Phase 8; harness seeds in Phase 1.

---

## Technical Debt Patterns

| Shortcut | Immediate Benefit | Long-term Cost | When Acceptable |
|----------|-------------------|----------------|-----------------|
| Parse display `amount` strings | No money type | Locale/rounding bugs, failed splits | Never |
| One retry policy for all verbs | Simple resilience | Duplicate writes/imports | Never for non-idempotent writes |
| Hand-maintained response structs per command | Fast first command | Envelope/field drift, silent nils | Only behind a tested normalizer |
| Global config with one key | Easy demo | Cross-profile leakage, key sprawl | Prototype only |
| Codegen the whole CLI from OpenAPI | Broad coverage | Commands the server lacks; poor UX | Never as the only strategy |
| Live-server test suite | Realism | Flaky, rate-limited, non-hermetic | Tagged integration subset only |

## Integration Gotchas

| Integration | Common Mistake | Correct Approach |
|-------------|----------------|------------------|
| API-key auth | Key in query/logs | `X-Api-Key` header only; redact everywhere |
| Scope errors | Treating `403 insufficient_scope` as retryable | Report it; suggest `read_write` or owner action |
| Pagination | Assuming `meta`/`next_page` everywhere | Per-collection normalizer |
| Family exports | Downloading before `completed` | Poll; expect `409`; stream ZIP; admin only |
| Import sessions | Re-uploading a chunk after timeout | Stable `client_chunk_id`; `409` is a conflict |
| Sync | Retrying because the first looks stuck | One family-wide sync; poll to terminal |
| Trades | Assuming response is always a trade | Create may return transaction or transfer |
| Cash flow | Sending `month` with a date range | Ranges require `view=sankey`; no `month` |
| Chats | Expecting the answer in the POST response | Poll for a new `assistant_message` |

## Performance Traps

| Trap | Symptoms | Prevention | When It Breaks |
|------|----------|------------|----------------|
| Full-history page scraping | 25+ requests, then `429` | Filters; family export for bulk | >~10k rows managed |
| Per-row account/category lookups | N+1 HTTP calls | Embedded objects; batch IDs | >100 rows |
| Whole export ZIP in memory | High RSS/OOM | Stream to disk, atomic rename | Hundreds of MB |
| Tight async polling | `429`, duplicate jobs | Backoff 2s→30s; terminal stop | Any import/sync/chat |
| Refetching accounts every command | Slow startup/stale cache | Short TTL keyed by server+user | Slow self-hosted server |
| Unbounded `--all` | Surprise long runs | Print count/estimate; require `--yes` | >1 page |

## Security Mistakes

| Mistake | Risk | Prevention |
|---------|------|------------|
| API key in argv/history | Account compromise | Prompt/stdin/keychain; no key flag |
| Debug logs include headers | Leakage in bug reports | Central redaction; fake-key test |
| World-readable/committed config | Local theft | `0600`, outside repo, keychain default |
| Cache not keyed by server/user | Cross-tenant exposure | Origin + user + profile in every key |
| OAuth name impersonates “Sure” | Phishing/consent confusion | Name without reserved word; show origin |
| Token in `sure://` link | Leak via history/screenshots | IDs only; never credentials/notes |
| Command built from names | Shell injection | IDs + `Shellwords.escape`; reject control chars |

## UX Pitfalls

| Pitfall | User Impact | Better Approach |
|---------|-------------|-----------------|
| Rounded totals shown as exact | Reconciliation fails | Show `amount_decimal` on request; label rounding |
| Silent auto-JSON to a pager | Raw JSON in `less` | Explicit `--json`/`--table`; document default |
| “Are you sure?” only | Confirms wrong object | Show ID, date, amount, account, currency, count |
| Treating `202` as done | Acts on missing data | Show status and follow-up command |
| Generic “request failed” | No recovery path | Map auth/scope/not-found/conflict/rate-limit/network |

## "Looks Done But Isn't" Checklist

- [ ] **Money:** Every amount carries currency; no floats; `amount_decimal` used — verify with multi-currency and 4-decimal split fixtures.
- [ ] **Totals:** Come from server reports — compare with `/cash_flow` and `/balance_sheet`.
- [ ] **Pagination:** Both `pagination` and `meta` handled; drift detected — test transactions, imports, syncs, exports.
- [ ] **Auth:** Key absent from argv/logs; keychain keyed by origin+profile — check `ps`, debug output, read-only key.
- [ ] **OAuth:** PKCE S256, state, exact redirect, refresh/rotation — test on a fresh server.
- [ ] **Destructive:** Dry-run resolves objects; typed confirmation; nonzero on partial failure — include one forbidden ID.
- [ ] **Async:** Import/sync/export/chat reach terminal state with timeout/resume — kill CLI mid-poll.
- [ ] **Shell:** Commands are built from IDs and every dynamic value is quoted; links encoded; no secrets — test quotes, `$()`, newlines, Unicode.
- [ ] **Streams:** Clean JSON stdout; TTY-only prompts; documented exit codes — test pipes, `jq`, Ctrl-C.
- [ ] **Compatibility:** Current and previous minor tested; unsupported endpoints explain upgrade — use an older container.
- [ ] **AI:** Tool calls rendered, not executed; writes confirmed — test a response with tool calls.
- [ ] **Tests:** Deterministic contracts + tagged live suite — run twice at month-end.

## Recovery Strategies

| Pitfall | Recovery Cost | Recovery Steps |
|---------|---------------|----------------|
| Wrong total shipped | HIGH | Identify affected reports; correct via server endpoints; add regression fixture |
| Duplicate writes | MEDIUM | Find by `external_id`/timestamp; preview/delete extras; disable auto-retry |
| Key leaked | HIGH | Revoke in Settings → API Keys; issue new key; purge logs/history |
| Family reset triggered | HIGH | Stop writes; inspect reset counts; restore backup; add typed confirmation |
| Broken OAuth client | LOW | Re-register valid name/redirect; delete stale app; re-authenticate |
| Partial batch | MEDIUM | Read manifest; retry failed IDs only; verify by read |

## Pitfall-to-Phase Mapping

| Pitfall | Prevention Phase | Verification |
|---------|------------------|--------------|
| Client-side financial engine | Phase 2 | CLI totals equal `/cash_flow` and `/balance_sheet` |
| Float/display money + FX | Phase 1/2 | 4-decimal split round-trip; mismatch raises |
| Pagination envelopes | Phase 1 | Per-collection contract tests, two pages |
| Page-scrape exports | Phase 4 | Bulk path uses family export; 429 backoff |
| Retry/idempotency | Phase 1/3 | Timeout-then-retry creates one record |
| Destructive/batch safety | Phase 3 | Dry-run writes nothing; one failure exits nonzero |
| Async state confusion | Phase 4 | Kill/resume poll; terminal-state tests |
| API-key leakage | Phase 1/5 | `ps`/log/history scans; redaction test |
| Authorization assumptions | Phase 2/3 | Owner/full/read-only/guest fixtures |
| OAuth loopback | Phase 5 | Fresh DCR + PKCE + refresh end-to-end |
| Version/OpenAPI drift | Phase 1/8 | Current+previous minor containers |
| Shell injection/deep links | Phase 7 | Adversarial names, quotes, newlines |
| Output/exit-code contract | Phase 1/8 | Pipe/jq/EPIPE/SIGINT matrix |
| AI agent runtime | Phase 6 | Tool calls rendered only; writes confirmed |
| Flaky/contract tests | Phase 8 | Two runs at month-end, no live drift |

## Sources

- `docs/llm-guides/architecture.md` — money, currencies, sharing, transfers, sync/import semantics.
- `docs/api/transactions.md`, `docs/api/openapi.yaml`, `docs/api/imports.md`, `docs/api/chats.md` — amount fields, envelopes, async states, coverage.
- `app/controllers/api/v1/base_controller.rb`, `app/services/api_rate_limiter.rb` — auth precedence, scopes, 100/hour managed tier, redaction targets.
- `app/controllers/api/v1/transactions_controller.rb`, `splits_controller.rb`, `family_exports_controller.rb`, `imports_controller.rb`, `sync_controller.rb` — write, destructive, and async behavior.
- `app/models/account.rb` (`accessible_by`/`writable_by`), `app/models/income_statement/cash_flow.rb`, `lib/money.rb` — tenancy and authoritative reporting.
- `config/initializers/doorkeeper.rb`, `app/controllers/oauth_registration_controller.rb`, `oauth_metadata_controller.rb` — PKCE, DCR, reserved names, redirect rules, token lifetimes.
- RFC 8252 §§7.3, 8.1, 8.3 — loopback redirects, ephemeral ports, PKCE for native apps.
- OWASP Secrets Management Cheat Sheet; CircleCI secure-secrets guidance — argv/history/environment leaks.

---
*Pitfalls research for: Sure CLI*
*Researched: 2026-10-31*
