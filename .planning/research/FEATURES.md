# Feature Research

**Domain:** First-party personal-finance CLI over the Sure `/api/v1` HTTP API
**Researched:** 2026-10-31
**Confidence:** HIGH

## Scope Anchors

- 110 documented operations across 85 paths, plus implemented-but-undocumented `POST /api/v1/sync` and `GET /api/v1/usage` (confirmed in `config/routes.rb`).
- API-key (`X-Api-Key`, `read` / `read_write`) is the only universally available auth today; OAuth authorization-code + dynamic registration + loopback is feasible later, no device grant.
- Money is server-formatted. Use `amount_decimal` for exactness and `amount_cents` / `signed_amount_cents` for integers; never parse `amount`. Positive is outflow, negative inflow; create uses `nature`.
- Reporting is server-calculated (`/cash_flow`, `/balance_sheet`, `/spending_vs_normal`). The CLI formats; it must not recompute financial rules.
- Write coverage is uneven: transactions, splits, tags, categories (create only), merchants (CSV import only), trades, recurring, valuations, chats, exports, imports, sync, user reset/delete. Accounts, rules, budgets, providers, transfers, holdings, securities are read-only via API.
- Managed API keys are limited to 100 req/hour (standard tier); self-hosted is unlimited. Honor `X-RateLimit-*` and `429` with `Retry-After`. Prioritization below is provisional pending user interviews.

## Feature Landscape

### Table Stakes (Users Expect These)

| Feature | Why Expected | Complexity | Notes / Dependencies |
|---------|--------------|------------|----------------------|
| Install, `sure --version`, self-check | A CLI that cannot prove it is installed and current feels unfinished | LOW | Gem + container; version check cached 24h, never blocks |
| Server targeting (URL, path prefix, TLS CA, insecure opt-in) | Self-hosters use subpaths and self-signed certs | MEDIUM | HTTP client + config; default verify TLS, `--ca-bundle`, `--insecure --yes` |
| API-key login without hand-editing files | Documented onboarding path; keys are created only in Settings → API Keys | MEDIUM | Hidden prompt, `--api-key-file`, `--api-key-stdin`; store in OS keychain, not config |
| Auth status and scope introspection | Users need to know which server/family/key and whether writes are allowed | LOW | `GET /usage` returns key name/scopes/rate limit; OAuth needs a probe |
| Named profiles and precedence | People run personal + family/test servers | MEDIUM | flags > env > profile > defaults; `--profile` global |
| Accounts and balances read | The first question every user asks | LOW | `accounts` returns `accounts` + `pagination`; balances separate history |
| Transaction list/show with filters | Core daily workflow | MEDIUM | account/category/merchant/tag/date/amount/type/search; page max 100 |
| Transaction create/edit/delete | Core write workflow | HIGH | `nature`, `kind`, `excluded`, `tag_ids`; sign and split semantics |
| Tags and splits | Users organize and reconcile transactions | MEDIUM | Split children must sum exactly to parent; parent becomes excluded |
| Categories/merchants read + basic create/import | Classification and cleanup | LOW–MEDIUM | Category create; merchant CSV import only; no edit/delete endpoints |
| Reports: cash flow, balance sheet, budgets | The product's authoritative numbers | MEDIUM | Cash flow `include` vs `view` mutually exclusive; default current month |
| CSV import with preflight | A finance CLI without import is a viewer | HIGH | `POST /imports/preflight`, `POST /imports`, row diagnostics, 10 MB cap |
| Sync status and trigger | Connected accounts change outside the terminal | MEDIUM | `POST /sync` undocumented; poll `GET /syncs/{id}` or `latest` |
| Human table on TTY, JSON when piped | Both interactive and script use | MEDIUM | Explicit `--json`/`--csv`; stable columns; pager only on TTY |
| Scripting discipline: stdout/stderr, exit codes, no prompts on pipe | Automation is a stated goal | MEDIUM | `--no-input`; distinct codes; errors on stderr; no ANSI when piped |
| Destructive-action safety | Financial data is high-consequence | MEDIUM | `--dry-run`, confirmation, typed confirm for severe deletes |
| Help, examples, shell completion | Discoverability is the CLI's UI | LOW | Examples first; bash/zsh/fish/PowerShell; generated from command metadata |
| Doctor and version compatibility | Self-hosted servers drift | MEDIUM | Health, auth, scope, TLS, clock skew, API version, config perms |
| Raw API escape hatch | Parity for undocumented/new endpoints | LOW | `sure api METHOD PATH`, inherits auth/tenant/scope, never bypasses API |

### Differentiators (Competitive Advantage)

| Feature | Value Proposition | Complexity | Notes / Dependencies |
|---------|-------------------|------------|----------------------|
| Server-truth reporting, including ASCII Sankey | Users get the same numbers as the dashboard without a browser | MEDIUM | Cash flow summary + `include=sankey` / `view=sankey`; layout is local, values server-owned |
| Machine-readable command catalog (`sure commands --json`) | Web, docs, agents, and completion share one grammar; prevents drift | MEDIUM | Command metadata is the source for help/completion/copy-command |
| Canonical copyable command (`sure command … --copy`) | Makes every web action reproducible off-platform | MEDIUM | POSIX/PowerShell quoting; redact secrets; stable flag names |
| `sure open` deep links paired with commands | Jumps from terminal to the exact web record and back | LOW | `sure://host[:port]/path`; transactions use `entry_id`, not `id` |
| Field selection and `--jq` / `--template` | Turns the CLI into a composable data tool, not a pretty printer | MEDIUM | `--fields`, `--jq` (embedded or jq binary), `--template`; JSON envelope |
| Safe bulk edit with selector preview | High-leverage cleanup scripts without mass-accident risk | HIGH | `--where`/`--ids-from`, count preview, `--max`, `--confirm-count` |
| Resumable, chunked imports with diagnostics | Handles large Sure NDJSON and messy bank CSVs | HIGH | `import_sessions` idempotent chunks; `imports/{id}/rows`; preflight warnings |
| Import reconciliation diff | Shows duplicates/conflicts before publishing | MEDIUM–HIGH | Preflight + existing transaction lookup; never auto-merge |
| Scope-aware preflight before writes | Fails before a half-completed mutation | LOW | Check key scopes; `read_only` profile flag; warn on read-only key |
| Async watch with backoff and progress | Sync/import/export/chat feel like jobs, not hangs | MEDIUM | `--wait`, `--timeout`, poll interval; Ctrl-C stops waiting, not the server job |
| Agent-friendly stable envelope | One parse target for scripts and LLM agents | LOW–MEDIUM | `data`/`meta`/`warnings`; no prompts; command catalog; `--raw` escape |
| Semantic guardrails | Prevents accounting mistakes the API accepts but reporting punishes | MEDIUM | Warn on categorizing `funds_movement`/`cc_payment`, editing split parents, excluding income |
| Redacted support bundle | Faster self-hosted support without leaking finances | LOW | `sure doctor --bundle`; hashes bodies, never transaction content |

### Anti-Features (Commonly Requested, Often Problematic)

| Feature | Why Requested | Why Problematic | Alternative |
|---------|---------------|-----------------|-------------|
| Local ledger / SQLite mirror / offline editing | “Fast queries like hledger” | Becomes a second financial engine; stale balances; sync conflicts; violates server-truth core value | Server API plus `--json` piped to `jq`; cache only completions/metadata |
| TUI dashboard or full-screen app | “Make it feel like a finance app” | Second UI, keybindings/terminal complexity, poor scripting; explicitly out of scope | Tables, `--watch` for jobs, and `sure open` for visual views |
| Direct DB or Rails-console access | “Faster and simpler than HTTP” | Bypasses auth, family tenancy, scopes, and API contract; unsafe multi-tenant blast radius | `sure api` against `/api/v1` only |
| Provider/bank connect/disconnect and credential entry | “Full parity with Settings” | Bank consent, MFA, secrets, and provider SDKs are web/OAuth concerns; API is read-only | `sure providers list`; deep-link to web settings |
| Password/SSO signup or login in the CLI | “One command to get started” | Device metadata, MFA, SSO redirects, account lockout, secret handling; no device grant | API key now; OAuth loopback with PKCE later |
| Push/APNs and FinanceKit device management | “Complete API parity” | Device-bound credentials; no human terminal value; high secret-handling risk | Exclude from CLI; keep in mobile/desktop |
| Account, rule, budget, category-edit, merchant-edit writes | “The dashboard can do it” | Endpoints do not exist; faking them with multi-step writes creates drift and partial state | Read-only commands + explicit “use web” message with deep link |
| Attachments/receipts upload | “Transactions have receipts” | No API surface; binary storage and virus-scanning concerns | Deep-link to transaction in web |
| Auto-sync before every read | “Always fresh data” | Surprise writes, rate-limit burn, slow commands, non-deterministic scripts | Explicit `sure sync run --wait`; show `as_of` in output |
| Undo/rollback command | “Deletes are scary” | No server undo; snapshots/ledger reconstruction would be a second engine | `--dry-run`, export before bulk changes, typed confirmation |
| Generic local query language (ActualQL-like) | “Power users want SQL” | Duplicates server filters, drifts from API semantics, invites local recomputation | Rich API filters + `--jq` over returned JSON |
| Default telemetry/analytics | “Improve the product” | Self-hosted finance data is sensitive; trust is the product | No telemetry; opt-in redacted crash reports only |
| Secrets in project config or `--api-key` flag | “Convenient CI setup” | Leaks via git, `ps`, shell history, logs | Keychain, `SURE_API_KEY`, `--api-key-file`/stdin, 0600 fallback |

## Proposed Command Taxonomy

Legend: **R** read-only · **W** write/non-destructive · **D** destructive · **A** async (returns job id) · **L** long-running/poll/wait · **LCL** local-only.
Global: `--profile`, `--server`, `--json|--format`, `--no-input`, `--yes`, `--dry-run`, `--verbose`, `--no-color`.

```text
sure auth login [--server URL] [--api-key-file F|--api-key-stdin] [--oauth] [--profile P]  W LCL
sure auth logout [--all] | status [--json] | switch <profile>                              W/R LCL
sure config init|get|set|unset|list|use|path                                               W/R LCL
sure doctor [--json] [--bundle PATH]                                                       R
sure version [--json] | completion <bash|zsh|fish|powershell> | help [cmd]                 R
sure commands [--json]                                                                     R

sure accounts list [--type --status --all] | show <id|name> | balance [<id>] [--at DATE]    R
sure balances list --account <id> [--from --to --currency] | show <id>                     R

sure txns list [filters] [--all --limit --sort] | show <id|entry_id>                       R
sure txns add --account --date --amount --name [--nature --kind --category --merchant --tags --excluded]  W
sure txns edit <id> [same flags] [--clear-*]                                               W
sure txns rm <id>... [--yes]                                                               D
sure txns split get <id> | set <id> --part ... | clear <id>                                W/D
sure txns categorize <id>... --category <id> [--dry-run]                                   W (bulk)

sure transfers list|show <id>                                                              R
sure rejected-transfers list|show <id>                                                     R

sure categories list [--roots --parent --classification] | show <id> | add ...              R/W
sure merchants list|show <id> | import <file.csv> [--dry-run]                              R/W (bulk)
sure tags list|show|add|edit|rm                                                            R/W/D
sure rules list|show <id> | runs [--rule --status]                                         R
sure budgets list|show <id> | categories [--budget] | category <id>                        R

sure reports cashflow [--month|--from/--to] [--sankey] [--group-by category|account]       R
sure reports balance-sheet | spending-vs-normal [--from --to]                             R

sure holdings list|show <id>                                                               R
sure trades list|show|add|edit|rm                                                          R/W/D
sure securities list|show <id> | prices list|show [--security]                             R
sure valuations list|show|add|edit                                                         R/W

sure recurring list|show|add|edit|rm                                                       R/W/D
sure imports list|show|rows|preflight|create [--publish]|watch <id>                         R/W/A/L
sure imports sessions create|status|upload|publish|watch                                   W/A/L
sure imports types                                                                         R

sure sync run [--wait] [--timeout] | watch <id> | history | latest | show <id>             W/A/L/R
sure providers list                                                                        R

sure chats list|show|new|rename|rm|send|retry|watch                                        R/W/D/A/L
sure insights list [--status --priority]                                                   R

sure exports list|show|create|watch|download <id> [--output PATH]                          R/W/A/L
sure settings show | usage | ai enable                                                     R/W
sure user reset [--yes --confirm] | delete [--yes --confirm=<email>]                       D/A

sure api <METHOD> <PATH> [-d key=value] [--raw]                                            R/W/D
sure open <resource> [id] [--print|--copy]                                                 R LCL
sure command <cmd ...> [--copy] [--shell posix|powershell]                                 R LCL
```

Not exposed because no API: account create/edit/delete, rule write, budget write, category/merchant edit/delete, provider connection changes, attachment upload. Those commands should fail with a clear “API does not support this; open <web URL>” message, not a fake local implementation.

Domain complexity: read-only nouns LOW; transaction/trade/valuation writes MEDIUM; imports/chats/exports HIGH (async polling, partial failure); auth/config MEDIUM; copy-command/catalog MEDIUM. The highest-risk areas are bulk transaction writes and import publish, which need preview, limits, and resumability.

## Output and Formatting Contract

- Default: aligned, colored table on TTY; compact JSON when stdout is not a TTY. `--format table|json|csv|ndjson`, `--json`, `--csv` override. `--raw` returns the unmodified API body.
- JSON envelope: `{"data": …, "meta": {"profile","server","as_of","pagination","warnings":[]}}`; one document per invocation. Lists always put an array in `data`. This normalizes the API's mixed `accounts`/`transactions`/`data` keys.
- Money: tables and CSV use exact decimal strings with an ISO currency column; JSON preserves API strings/integers. Never parse the display-only `amount`. Show sign convention in help (`+ outflow / − inflow`).
- Dates: ISO-8601 by default; family locale/date format only in human tables. Cash flow `month` must be `YYYY-MM-01`; `include` and `view` cannot be combined.
- Tables: fixed default columns per command, `--wide`, `--no-truncate`, `--plain` (one record per line), `--no-header` for CSV. Pager only when TTY and output exceeds one screen.
- Progress, warnings, and diagnostics go to stderr; data only to stdout. `--quiet` suppresses non-essential output. `--verbose`/`--debug` redact `Authorization`, `X-Api-Key`, tokens, and financial request bodies.
- Pagination: `--page`, `--per-page` (1–100), `--limit`, `--all` (capped, warns when truncated); expose `meta.pagination`. Never silently fetch unbounded lists.

## Auth, Profiles, and Onboarding

- `sure auth login` validates the server (health, API version, managed/self-hosted), prints the exact key page (`/settings/api_keys`), reads the key without echo, probes scope via `/usage`, and stores it in the OS keychain (`keyring`), with a 0600 credential-file fallback.
- Never accept `--api-key` on the command line (leaks via `ps`/history). Support `SURE_API_KEY`, `--api-key-file`, `--api-key-stdin`. `sure auth status` shows server, family, mode, key name, scope, rate limit, and credential location; never the secret.
- Profiles in `~/.config/sure/config.toml` (respect `XDG_CONFIG_HOME`), 0600, secrets referenced by keychain key only: `server_url`, `key_ref`, `family`, `default_account`, `output`, `ca_bundle`, `timeout`, `read_only`. Env: `SURE_SERVER`, `SURE_API_KEY`, `SURE_PROFILE`, `SURE_OUTPUT`, `SURE_NO_COLOR`, `SURE_INSECURE`.
- `read_only = true` profile refuses all writes even when the key is `read_write`. This is a safety feature, not a scope substitute.
- OAuth (later): authorization code + PKCE + dynamic client registration + `127.0.0.1` loopback callback + state; refresh token in keychain. No device grant; no password/SSO login in the CLI.

## Scripting, Async, and Safety

- Exit codes: `0` success, `1` generic, `2` usage, `3` auth, `4` not found, `5` validation, `6` forbidden/insufficient scope, `7` rate limited, `8` conflict/not ready, `9` network/TLS, `10` cancelled, `11` timeout, `12` server error.
- `--no-input` and non-TTY stdin disable prompts. Destructive commands require `--yes` when non-interactive; severe operations (account reset/delete, bulk > `--max`) also require `--confirm=<email|count>`.
- `--dry-run` on every write prints method/path/body and a resolved human summary (account name, amount, target count) without mutating; name/ID resolution may still use GETs.
- Retry only idempotent GETs, with jittered backoff; never blind-retry POST/PATCH/DELETE. On `429`, print reset seconds and suggest `sure usage`. Bulk writes are client-driven and throttled; surface partial failure with a resumable list.
- Async commands return an ID and support `--no-wait`, `--wait`, `--timeout` (default 10m), `--interval` (2s exponential to 30s). Ctrl-C stops waiting but prints how to resume (`sure sync watch <id>`). Export download returns `409` until status is `completed`; watch first. Import sessions require all `expected_chunks` before publish.
- TLS verifies by default; `--insecure` warns and requires `--yes`. Warn on clock skew > 5 minutes. Support servers mounted under a URL prefix.
- Input: `--file -` / `-` reads stdin; NDJSON accepted for bulk transaction input (`sure txns add --from -`), validated client-side before any write. Output `-` writes to stdout.

## Platform Copy-Command and Deep Links

- `sure command … --copy` emits a canonical, shell-quoted command without executing it. `--shell powershell` switches quoting. Include `--profile` only when non-default; never include keys or secrets.
- `sure commands --json` is the contract the web platform uses to render “copy CLI command” without duplicating grammar: name, summary, args, flags, mode (R/W/D/A), API endpoint, examples, version added.
- `sure open tx <entry_id>` uses `entry_id` (web routes use entry IDs, API uses transaction `id`), `sure open account <id>`, `sure open budget <month>`. Emit `sure://host[:port]/path`; on platforms without a handler, print/copy the `https://` URL.
- Platform shows commands and deep links only. No server-side execution, no embedded terminal, no command strings containing credentials.

## Help, Completion, and Docs

- `sure`, `sure --help`, `sure help <cmd>`, `sure <cmd> --help` all work; help leads with 2–3 real examples, then flags, modes, exit codes, API endpoint, and “see also”.
- Completion is generated from command metadata for bash/zsh/fish/PowerShell, with optional cached ID completion (accounts/categories/tags); disable network completion with `SURE_NO_COMPLETION_NETWORK`.
- Man pages and web docs generate from the same metadata as `sure commands --json`; `sure docs [command]` opens the matching page. Keep `sure doctor` output copy-pasteable.

## Feature Dependencies

```
API client + auth + profiles
    └──requires──> error mapping + exit codes
                       └──requires──> non-interactive / no-prompt discipline

Command metadata
    ├──requires──> help + completion + man/docs
    ├──requires──> `sure commands --json`
    └──requires──> `sure command --copy` + web copy-command contract

Money/date/ID resolution
    └──requires──> every table/JSON/CSV renderer

`--dry-run` + confirmation
    └──requires──> destructive commands
                       └──enhances──> bulk edit + import publish

Import preflight ──requires──> import create ──requires──> session chunks ──requires──> watch/poll
Sync trigger ──requires──> sync status ──enhances──> providers list
Exports create ──requires──> export watch ──requires──> download
Chats send ──requires──> chat watch ──enhances──> insights
OAuth loopback ──requires──> PKCE + dynamic registration ──enhances──> profiles (later)
`--json` ──requires──> stable envelope ──enhances──> `--fields` / `--jq`
Deep-link registry ──requires──> `sure open` ──enhances──> `sure command --copy`
```

### Dependency Notes

- **Everything requires auth/profile resolution:** no command may embed its own credential logic or talk to a server before profile precedence is settled.
- **Command metadata must precede help/completion/copy-command:** otherwise the web platform and docs drift from the real grammar.
- **Dry-run before destructive writes:** deleting without preview is the highest-consequence failure mode; build the serializer once and reuse it for confirmation text.
- **Import preflight before publish:** avoids creating imports from invalid CSVs and gives users a reconciliation point.
- **Async watch depends on stable job IDs:** syncs, imports, exports, and chats all return IDs; implement one poller rather than four.
- **OAuth conflicts with password/SSO anti-features:** adding password login would fork the auth model and weaken the security story.

## MVP Definition

### Launch With (v1)

- [ ] `auth login` (API key + keychain), `auth status`, profiles, `doctor`, `version` — without this nothing else is trustworthy.
- [ ] `accounts list/show/balance`, `txns list/show/add/edit/rm`, `tags` CRUD — the daily loop.
- [ ] `reports cashflow`, `reports balance-sheet`, `budgets list/show` — truthful server numbers.
- [ ] `imports preflight/create/rows`, `sync run/status` — connected-account reality.
- [ ] Table/JSON/CSV, TTY detection, pagination, money/date formatting — dual human/script use.
- [ ] `--dry-run`, confirmation, non-interactive mode, exit codes, no-prompt-on-pipe — safety and automation.
- [ ] Help with examples + bash/zsh/fish completion — discoverability.
- [ ] Raw `sure api` — parity escape hatch while endpoint coverage grows.

### Add After Validation (v1.x)

- [ ] Splits, `txns categorize` bulk, merchant CSV import — cleanup workflows once core writes are stable.
- [ ] `trades`, `valuations`, `recurring`, `holdings`, `securities` — investment parity.
- [ ] `exports` create/watch/download and `chats` send/watch — async job ergonomics.
- [ ] `insights`, `spending-vs-normal`, Sankey output — reporting depth.
- [ ] `sure commands --json`, `sure command --copy`, `sure open` — platform integration.
- [ ] OAuth loopback login — removes manual key creation for hosted users.

### Future Consideration (v2+)

- [ ] Advanced `--jq`/`--template`/field selection if user demand appears.
- [ ] Import reconciliation diff and resumable bulk operations for large datasets.
- [ ] Deeper agent integrations that call the existing MCP where it is the better contract (not a second MCP server).

## Feature Prioritization Matrix

| Feature | User Value | Implementation Cost | Priority |
|---------|------------|---------------------|----------|
| API-key auth + keychain + profiles | HIGH | MEDIUM | P1 |
| Accounts/transactions read + filters | HIGH | MEDIUM | P1 |
| Transaction create/edit/delete | HIGH | HIGH | P1 |
| Reports (cash flow, balance sheet, budgets) | HIGH | MEDIUM | P1 |
| Output formats + scripting contract | HIGH | MEDIUM | P1 |
| Dry-run + confirmation + exit codes | HIGH | MEDIUM | P1 |
| CSV import + preflight | HIGH | HIGH | P1 |
| Sync trigger/status | MEDIUM | MEDIUM | P1 |
| Help/completion/doctor | HIGH | LOW–MEDIUM | P1 |
| `sure api` escape hatch | MEDIUM | LOW | P1 |
| Splits + bulk categorize | MEDIUM | HIGH | P2 |
| Investments/valuations/trades/recurring | MEDIUM | MEDIUM–HIGH | P2 |
| Exports + chats + insights | MEDIUM | MEDIUM | P2 |
| `commands --json` + copy command + deep links | HIGH (platform goal) | MEDIUM | P2 |
| OAuth loopback | MEDIUM | HIGH | P2 |
| `--jq`/template/fields | LOW–MEDIUM | MEDIUM | P3 |
| Import reconciliation diff | MEDIUM | HIGH | P3 |

## Competitor Feature Analysis

| Feature | Stripe CLI | GitHub CLI | Plaid CLI | Actual Budget CLI | hledger | Our Approach |
|---------|------------|------------|-----------|-------------------|---------|--------------|
| Auth | Browser pairing + key; keychain | `gh auth login`, hosts, token scopes | Browser login + env keys | Env/config/session token | None (local files) | API key + keychain now; OAuth loopback later |
| Config | TOML, projects, `--project-name`, env > file | Hosts + per-repo config | Env > config, per-environment | cosmiconfig, env, flags | Journal files + options | Profiles + env/flag precedence; no secrets in file |
| Grammar | `resource operation`, `get/post` | `noun verb` | `product verb` | `noun verb` | Report commands + query | `noun verb`, API-shaped nouns, aliases (`txns`) |
| Output | JSON-first, `--format` | `--json --jq --template`, TTY-aware | `--json`, table default | json default, table/csv | txt/csv/json | Table on TTY, JSON piped, `--csv`, `--jq` later |
| Money | Integer minor units | n/a | Decimal display | Integer cents in JSON, decimals in tables | Decimal | Exact decimal + `_cents`; never parse `amount` |
| Safety | `--confirm`, idempotency keys | Prompts, `--yes` patterns | Minimal | `--dry-run` on import | Minimal | Dry-run + typed confirm + read-only profiles |
| Async | `listen`, `logs tail`, `trigger` | `run watch` | `transactions sync` | `bank-sync` | None | Unified `--wait/--watch`, backoff, resumable IDs |
| Escape hatch | `stripe get/post` | `gh api` | None | AQL query | Query language | `sure api` only; no local query engine |

## Sources

- Sure `docs/api/*.md`, `docs/api/openapi.yaml` (110 operations), `docs/clients.md`, `config/routes.rb`, `app/services/api_rate_limiter.rb`
- Stripe CLI reference: command taxonomy, config/profiles, `--confirm`, raw `get`/`post`, browser login (docs.stripe.com/cli)
- GitHub CLI: `--json`/`--jq`/`--template`, pagination, exit codes 0/1/2/4 (cli.github.com/manual)
- Plaid CLI: table vs `--json`, stdout/stderr split, `doctor`, config precedence, env credentials (plaid.com/docs/resources/cli)
- Actual Budget CLI: noun/verb commands, `--format json|table|csv`, `--dry-run`, integer cents, config/env/flag precedence (actualbudget.org/docs/api/cli)
- hledger: report commands and txt/csv/json output (hledger.org/MANUAL.html, hledger.org/export.html)
- CLI Guidelines (clig.dev): TTY detection, stdout/stderr, confirmations, `--no-input`, dry-run, help/examples

---
*Feature research for: Sure personal-finance CLI*
*Researched: 2026-10-31*
