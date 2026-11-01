# Requirements: Sure CLI

**Defined:** 2026-10-31
**Core Value:** Any Sure operation a user can perform in the platform can be performed from a terminal with the same permissions and accounting semantics — and any platform action can be reproduced as a copyable CLI command.

## v1 Requirements

Requirements for the first public release. Each maps to exactly one roadmap phase.

### Foundation

- [x] **FOUND-01**: User can install the CLI as a Ruby gem and run `sure` from any shell.
- [x] **FOUND-02**: User can run `sure --version`, `sure help`, and per-command help with examples.
- [x] **FOUND-03**: User can define named server profiles and switch with `--profile`, `SURE_PROFILE`, or a default.
- [x] **FOUND-04**: User can target a server URL with a path prefix, custom CA bundle, or explicit insecure opt-in.
- [x] **FOUND-05**: User sees readable tables on a TTY and stable JSON when stdout is piped.
- [x] **FOUND-06**: User can force `--json`, `--csv`, `--ndjson`, and `--fields` output for scripting.
- [x] **FOUND-07**: User gets deterministic exit codes, errors on stderr, and no Ruby backtraces for expected failures.
- [x] **FOUND-08**: User can run `sure doctor` to check connectivity, auth, scope, TLS, clock skew, config permissions, and server compatibility.
- [x] **FOUND-09**: User can call any endpoint through `sure api METHOD PATH` with normal auth, tenancy, and redaction.
- [x] **FOUND-10**: User can install bash, zsh, and fish completion generated from the command catalog.

### Authentication

- [x] **AUTH-01**: User can log in with an API key via hidden prompt, `--api-key-file`, or stdin, without editing files.
- [x] **AUTH-02**: User credentials are stored in the OS keychain when available, with a `0600` atomic file fallback and a one-time warning.
- [x] **AUTH-03**: User can inspect `sure auth status` to see server, profile, user, key name, scopes, and rate-limit tier.
- [ ] **AUTH-04**: User can log in through a browser using OAuth authorization code + PKCE with a loopback callback.
- [ ] **AUTH-05**: The CLI registers itself through dynamic client registration using an allowed, non-reserved client name.
- [ ] **AUTH-06**: OAuth access tokens refresh automatically before expiry, and failures produce a clear re-login instruction.
- [ ] **AUTH-07**: User can log out locally and, when supported, revoke the token or API key.
- [x] **AUTH-08**: CI and automation can supply a key through `SURE_API_KEY` without persisting it.
- [x] **AUTH-09**: The CLI never prints, logs, or includes API keys, bearer tokens, or refresh tokens in errors, debug output, or copyable commands.

### Read & Report

- [ ] **READ-01**: User can list and show accounts with type, currency, balance, institution, and owner.
- [ ] **READ-02**: User can list and show transactions filtered by account, category, merchant, tag, date, amount, type, and search text.
- [ ] **READ-03**: User can view server-calculated cash flow for a month or arbitrary range, optionally including the Sankey graph.
- [ ] **READ-04**: User can view the server-calculated balance sheet.
- [ ] **READ-05**: User can list budgets and budget categories without recomputing totals.
- [ ] **READ-06**: User can list holdings, securities, security prices, and valuations.
- [ ] **READ-07**: User can view insights and spending-versus-normal comparisons.
- [ ] **READ-08**: User can view API usage and rate-limit status.
- [ ] **READ-09**: User can page through collections with `--page`/`--per-page`, or stream all pages with `--all` and deduplication.
- [ ] **READ-10**: User can read full transaction history through the family export contract instead of page scraping.
- [ ] **READ-11**: All money is displayed from server values using exact decimal strings and explicit currencies; the CLI never recomputes financial totals.
- [ ] **READ-12**: User can list transfers and rejected transfers with their linked transactions.

### Safe Writes

- [ ] **WRITE-01**: User can create a transaction with account, date, amount, nature, name, category, merchant, tags, notes, and kind.
- [ ] **WRITE-02**: User can update a transaction without silently changing its split, transfer, or exclusion semantics.
- [ ] **WRITE-03**: User can delete a transaction only after a resolved preview and explicit confirmation.
- [ ] **WRITE-04**: User can split a transaction into children that sum exactly to the parent, using exact decimal amounts.
- [ ] **WRITE-05**: User can list, create, update, and delete tags.
- [ ] **WRITE-06**: User can create categories and read category details.
- [ ] **WRITE-07**: User can list, create, update, and delete recurring transactions.
- [ ] **WRITE-08**: User can create, update, and delete valuations.
- [ ] **WRITE-09**: User can create, update, and delete trades.
- [ ] **SAFE-01**: Every destructive command supports `--dry-run`, which performs no writes and shows the resolved targets.
- [ ] **SAFE-02**: Destructive commands require `--yes`; severe operations (family reset, user delete) require a typed confirmation phrase.
- [ ] **SAFE-03**: Transaction creates use `source` + `external_id` for idempotency, and unknown write outcomes are reported as unknown with an inspection command.
- [ ] **SAFE-04**: Batch writes show per-item results, stop on destructive failures, summarize counts, and exit nonzero if any item failed.
- [x] **SAFE-05**: The CLI never prompts when stdin is not a TTY; it fails with an actionable message instead.
- [x] **SAFE-06**: Write commands preflight the credential scope and refuse `read`-only keys before starting.

### Imports, Sync & Exports

- [ ] **DATA-01**: User can preflight a CSV and see detected columns, warnings, and row counts before importing.
- [ ] **DATA-02**: User can import a CSV into an account with explicit column mappings and signage configuration.
- [ ] **DATA-03**: User can list and show imports and inspect per-row diagnostics for failures.
- [ ] **DATA-04**: User can run resumable, chunked import sessions with stable client session and chunk IDs.
- [ ] **DATA-05**: User can trigger a family sync and inspect sync status, progress, errors, and the latest sync.
- [ ] **DATA-06**: User can request a family export, poll its status, and download the completed archive.
- [ ] **DATA-07**: Every async command supports `--wait`, a timeout, backoff polling, and a resume hint; `202` or `pending` is never reported as complete.
- [ ] **DATA-08**: The CLI honors `Retry-After` and `X-RateLimit-*`, caps waits, and refuses unbounded page scraping that would exceed the managed rate limit.

### AI Chats & Insights

- [ ] **AI-01**: User can list and show chats with messages and citations.
- [ ] **AI-02**: User can create, rename, and delete chats.
- [ ] **AI-03**: User can send a message and receive the assistant response, including streaming output on a TTY.
- [ ] **AI-04**: User can retry the last assistant response.
- [ ] **AI-05**: Chat commands work non-interactively with JSON output and never require a TTY.
- [ ] **AI-06**: Chat output preserves server citations and never presents an unverified local calculation as an answer.

### Platform Handoff

- [ ] **PLAT-01**: User can export the full command catalog as JSON with names, arguments, flags, risk level, and examples.
- [ ] **PLAT-02**: The CLI can generate a canonical, shell-escaped command for any supported platform action.
- [ ] **PLAT-03**: User can run `sure open <resource>` to open the matching Sure web page through a `sure://` deep link.
- [ ] **PLAT-04**: The Sure web platform shows a "Copy CLI command" action for key record and report pages.
- [ ] **PLAT-05**: The Sure web platform exposes a command palette listing supported CLI commands without executing them server-side.
- [ ] **PLAT-06**: Generated commands and deep links use stable identifiers (`entry_id` where the web route requires it) and never include secrets.
- [ ] **PLAT-07**: Generated commands are protected against shell injection, including account names, notes, and search terms.

### Full Parity

- [ ] **PARITY-01**: User can read family settings and user profile data.
- [ ] **PARITY-02**: User can list provider connections and deep-link to provider setup in the web app.
- [ ] **PARITY-03**: User can list and show rules, rule runs, and rejected transfers.
- [ ] **PARITY-04**: User can read FinanceKit capability metadata, while device credential management stays in the mobile app.
- [ ] **PARITY-05**: User can delete their own account and request a family financial reset only through typed, irreversible confirmation.
- [ ] **PARITY-06**: Every documented `/api/v1` operation has a CLI command, a documented web fallback, or a recorded exclusion with a reason.
- [ ] **PARITY-07**: High-value server-side write gaps (accounts, budgets, rules, transfers) are either closed with API-consistent endpoints or explicitly deferred with deep links.

### Quality & Release

- [ ] **QUAL-01**: Unit tests cover option parsing, money handling, pagination envelopes, error mapping, and redaction.
- [ ] **QUAL-02**: Contract tests validate requests and responses against a pinned OpenAPI snapshot and fail on drift.
- [ ] **QUAL-03**: Integration tests run the built gem against a live Sure instance in CI.
- [ ] **QUAL-04**: Tests use sanitized fixtures and never contain real financial data or credentials.
- [ ] **QUAL-05**: CI tests the current and previous minor Sure server versions, or a documented capability probe covers differences.
- [ ] **QUAL-06**: Ruby lint, dependency audit, and secret scanning pass in CI.
- [ ] **QUAL-07**: Releases publish the gem, a slim container image, shell completions, and an optional Homebrew formula from `cli-v*` tags.
- [ ] **QUAL-08**: User-facing docs cover install, auth, profiles, every command group, scripting, safety, and platform handoff.
- [ ] **QUAL-09**: A cached, non-blocking update check informs interactive users of a newer release and can be disabled.
- [ ] **QUAL-10**: Large exports and `--all` streams are bounded in memory and tested against a large fixture.
- [ ] **QUAL-11**: The CLI is AGPLv3 and documents its relationship to the Sure server and the Maybe/Sure trademarks.

## v2 Requirements

Deferred to a future release. Tracked but not in the current roadmap.

### Experience

- **EXP-01**: Interactive TUI dashboard for balances, cash flow, and recent activity.
- **EXP-02**: Standalone signed binaries for macOS, Linux, and Windows.
- **EXP-03**: Shell prompt integration showing sync status or monthly spending.
- **EXP-04**: Plugin system for custom commands and formatters.
- **EXP-05**: Local read cache for faster repeated queries, never used for writes.
- **EXP-06**: Windows DPAPI credential encryption.
- **EXP-07**: Webhook or notification subscriptions for sync completion.

### Platform

- **PLAT-V2-01**: Provider connect/disconnect from the CLI.
- **PLAT-V2-02**: Push/APNs and FinanceKit device management.
- **PLAT-V2-03**: Attachment and receipt upload.
- **PLAT-V2-04**: Multi-family switching within one server profile.
- **PLAT-V2-05**: A local query language for power users.
- **PLAT-V2-06**: Undo/rollback for destructive commands.

## Out of Scope

Explicitly excluded. Documented to prevent scope creep.

| Feature | Reason |
|---------|--------|
| Server-side command execution from the web UI | Remote code execution and multi-tenant blast radius; platform may only copy or deep-link commands |
| Embedded web terminal | A second UI and security boundary that does not prove the CLI |
| Direct database or Rails console access | Bypasses authorization, family tenancy, scopes, and the API contract |
| A second financial engine | Reports, balances, and classification stay server-calculated |
| Replacing the web app | The CLI is an additional client, not a migration path |
| Password/SSO account creation or login | No device grant; MFA/SSO and lockout behavior belong to the browser |
| Bank/provider credential entry | Consent, MFA, and provider SDKs are web/OAuth concerns |
| Local ledger or offline editing | Creates stale balances and sync conflicts |
| Undo/rollback | No server primitive; safety comes from preview, confirmation, and exports |
| Default telemetry or analytics | Self-hosted financial data is sensitive; trust is the product |
| Secrets in project config or `--api-key` argv | Leaks through git, process lists, shell history, and logs |
| Faking missing writes with multi-step local patches | Creates drift and partial state; use server endpoints or deep links |

## Traceability

| Requirement | Phase | Status |
|-------------|-------|--------|
| FOUND-01, FOUND-02, FOUND-03, FOUND-04, FOUND-05, FOUND-06, FOUND-07, FOUND-08, FOUND-09, FOUND-10 | Phase 1 | Pending |
| AUTH-01, AUTH-02, AUTH-03, AUTH-08, AUTH-09 | Phase 1 | Pending |
| SAFE-05, SAFE-06 | Phase 1 | Pending |
| READ-01, READ-02, READ-03, READ-04, READ-05, READ-06, READ-07, READ-08, READ-09, READ-11, READ-12 | Phase 2 | Pending |
| WRITE-01, WRITE-02, WRITE-03, WRITE-04, WRITE-05, WRITE-06, WRITE-07, WRITE-08, WRITE-09 | Phase 3 | Pending |
| SAFE-01, SAFE-02, SAFE-03, SAFE-04 | Phase 3 | Pending |
| DATA-01, DATA-02, DATA-03, DATA-04, DATA-05, DATA-06, DATA-07, DATA-08, READ-10 | Phase 4 | Pending |
| AUTH-04, AUTH-05, AUTH-06, AUTH-07 | Phase 5 | Pending |
| AI-01, AI-02, AI-03, AI-04, AI-05, AI-06 | Phase 6 | Pending |
| PLAT-01, PLAT-02, PLAT-03, PLAT-04, PLAT-05, PLAT-06, PLAT-07 | Phase 7 | Pending |
| PARITY-01, PARITY-02, PARITY-03, PARITY-04, PARITY-05, PARITY-06, PARITY-07 | Phase 8 | Pending |
| QUAL-01, QUAL-02, QUAL-03, QUAL-04, QUAL-05, QUAL-06, QUAL-07, QUAL-08, QUAL-09, QUAL-10, QUAL-11 | Phase 8 | Pending |

**Coverage:**
- v1 requirements: 85 total
- Mapped to phases: 85
- Unmapped: 0 ✓

---
*Requirements defined: 2026-10-31*
*Last updated: 2026-10-31 after initial definition*
