# Project Research Summary

**Project:** Sure CLI
**Domain:** First-party Ruby command-line client for a self-hosted personal-finance server
**Researched:** 2026-10-31
**Confidence:** HIGH

## Executive Summary

Sure already exposes a broad, documented HTTP API (110 operations across 85 paths)
with API-key and OAuth authentication, family-scoped authorization, and
server-calculated financial reporting. The CLI should therefore be a thin,
well-behaved client — not a second ledger, not a database tool, and not a new
financial engine. Experts build this class of tool as a layered Ruby gem: Thor
for command dispatch, one Faraday pipeline for transport/auth/retry/redaction,
per-resource wrappers for API paths and pagination, and presenters that render
tables on a TTY or stable JSON/CSV on a pipe.

The recommended delivery order is a walking skeleton first: an installable gem
that authenticates with an API key, stores credentials safely, targets named
profiles, and exposes one raw `sure api` escape hatch. Read/reporting commands
follow, then guarded writes, then imports/sync/exports, browser OAuth, AI chats,
platform handoff (copyable commands and `sure://` deep links), and finally full
parity and release hardening.

The main risks are financial and security risks, not framework risks: recomputing
totals locally, treating display-rounded amounts as exact, retrying non-idempotent
writes, mishandling asynchronous jobs, scraping beyond the managed 100 req/hour
API-key limit, and leaking credentials or shell-escaping errors through copyable
commands. Each has a concrete prevention strategy and a phase that owns it.

## Key Findings

### Recommended Stack

Ruby 3.4.9 with Thor 1.5 for commands, Faraday 2.15 + faraday-retry for HTTP,
terminal-table/pastel for human output, csv/json for machine output, oauth2 +
WEBrick + Launchy for a loopback OAuth flow, and Minitest + WebMock/VCR +
faraday-openapi for tests. Credentials go to the OS keychain (`security` on
macOS, `secret-tool` on Linux) with a `0600` atomic file fallback. The CLI ships
as an independent gem under `cli/`, plus a slim container and an optional
Homebrew formula; releases use `cli-v*` tags and RubyGems trusted publishing.

**Core technologies:**
- **Thor** — command/subcommand dispatch, help, aliases — mature Rails lineage and pure Ruby
- **Faraday + faraday-retry** — one middleware pipeline — JSON, auth, retry, redaction in one place
- **terminal-table + pastel** — readable TTY output — maintained, Unicode-aware, no framework
- **Minitest + WebMock + faraday-openapi** — repo-consistent tests and contract drift detection
- **OS keychain with file fallback** — credential safety without a native-extension dependency

### Expected Features

Table stakes include install/version/doctor, server targeting (subpaths, TLS CA,
self-signed opt-in), API-key login, auth/scope status, named profiles, accounts
and balances, filtered transaction list/show, reporting (cash flow, balance
sheet, budgets), core transaction writes, CSV import with preflight, sync status
and trigger, TTY-aware output, scripting discipline, destructive-action safety,
help/completion, and a raw API escape hatch.

**Must have (table stakes):**
- API-key login, keychain storage, profiles, and `sure doctor`
- Accounts, balances, transactions, cash flow, balance sheet, budgets, holdings
- Transaction create/edit/delete/split with preview and confirmation
- CSV import preflight and run; sync trigger/status; export download
- Tables on TTY, JSON when piped, explicit `--json`/`--csv`, stable exit codes

**Should have (competitive):**
- Server-truth reporting including an ASCII Sankey
- Machine-readable command catalog shared by help, completion, docs, and web
- Copyable commands and `sure://` deep links from the platform
- `--fields` / `--jq` composition, safe bulk edits, resumable imports
- Async `--wait` with progress, agent-friendly JSON envelope, redacted support bundle

**Defer (v2+):**
- Interactive TUI or dashboard
- Local ledger/offline mode
- Provider connect/disconnect and bank credential entry
- Push/APNs and FinanceKit device management
- Undo/rollback and a local query language

### Architecture Approach

A four-layer gem: **interface** (Thor commands, options, risk policy, exit
codes), **core** (operations, resources, one HTTP pipeline, auth, config),
**presentation** (presenters, formatters, links), and **contract** (bundled
OpenAPI snapshot, operation catalog, contract tests). Dependencies point
downward only; commands are thin, formatters never call HTTP, and all financial
values pass through a money value object that preserves exact decimal strings.

**Major components:**
1. **Application / Command base** — parse, guard, perform, render, map errors
2. **HTTP::Client + RetryPolicy + Redactor** — one request path with safe retries and secret redaction
3. **Auth + CredentialStore** — API key now, OAuth loopback later, keychain/file adapters
4. **Resources + Operations** — per-API-group wrappers and compound workflows (imports, exports, OAuth)
5. **Presenters + Formatters** — stable table/JSON/CSV/NDJSON output; no financial math
6. **Catalog + Link builder** — copyable commands and `sure://` deep links; never executes

### Critical Pitfalls

1. **Second financial engine** — never sum transactions or rebuild reports; use `/cash_flow`, `/balance_sheet`, and server balances; use the family time zone.
2. **Inexact money** — parse `amount_decimal` as `BigDecimal`/string, use `amount` only for display, never mix currencies or use floats.
3. **Retrying writes** — auto-retry GET/HEAD only; use transaction `source` + `external_id`; treat unknown outcomes as unknown.
4. **Pagination and rate limits** — two envelopes, max 100/page, 100 req/hour on managed standard keys; prefer family exports for bulk.
5. **Async treated as done** — imports, exports, sync, and chat are jobs; poll with backoff, enforce timeouts, and resume by ID.
6. **Destructive actions without real preview** — resolve targets, show IDs/amounts/counts, require `--yes` or typed confirmation, never prompt on a pipe.

## Implications for Roadmap

Based on research, the suggested structure is eight vertical-MVP phases:

### Phase 1: Foundation & API-Key Authentication
**Rationale:** Nothing else is testable until the gem installs, targets a server, authenticates, and returns one truthful response.
**Delivers:** Gem skeleton under `cli/`, config profiles, credential store, Faraday pipeline, error/exit-code mapping, output base, `sure doctor`, `sure api`.
**Addresses:** Install, server targeting, API-key login, auth status, profiles, scripting discipline.
**Avoids:** Credential leakage, one-off HTTP code paths, backtraces as UX.

### Phase 2: Read & Report
**Rationale:** Read-only commands prove the API contract and money handling before any mutation exists.
**Delivers:** Accounts, balances, transactions, cash flow (including Sankey), balance sheet, budgets, holdings, securities, insights, usage; pagination normalizer; money value object.
**Uses:** Faraday client, resources, presenters/formatters, OpenAPI snapshot.
**Avoids:** Local totals, display-string parsing, envelope assumptions.

### Phase 3: Safe Writes
**Rationale:** Writes are the highest-consequence surface and need the risk policy, idempotency, and confirmation model built once.
**Delivers:** Transaction create/edit/delete/split, tags, categories create, recurring transactions, valuations, trades; `--dry-run`, confirmation, batch result summaries.
**Implements:** RiskPolicy, idempotent create, per-item failure reporting.
**Avoids:** Duplicate writes, partial-success exits, accidental deletes.

### Phase 4: Imports, Sync & Exports
**Rationale:** These are asynchronous, multi-step workflows and should build on the write safety model.
**Delivers:** Import preflight, CSV import, chunked import sessions, row diagnostics, sync trigger/status, family export request/poll/download; `--wait`, timeouts, resume.
**Addresses:** Import, sync, export, async watch.
**Avoids:** 202-as-done, rate-limit burn, unbounded memory.

### Phase 5: Browser OAuth & Credential UX
**Rationale:** API keys cover every deployment; OAuth is a UX upgrade and can follow proven read/write flows.
**Delivers:** Loopback authorization-code flow with PKCE, dynamic client registration, refresh, logout, scope introspection, keychain hardening.
**Uses:** oauth2, WEBrick, Launchy; existing Doorkeeper `force_pkce`.
**Avoids:** Device-grant server work, reserved client names, token leakage.

### Phase 6: AI Chats & Assisted Workflows
**Rationale:** Chat is a distinct streaming/polling surface and should not complicate the core CRUD path.
**Delivers:** Chat list/show/create/update/delete, message send/retry, streaming or polling output, citations, non-interactive mode.
**Addresses:** AI chats, insights, spending comparisons.
**Avoids:** Turning the CLI into an agent runtime; prompts on a pipe.

### Phase 7: Platform Handoff
**Rationale:** Copyable commands and deep links depend on a stable command grammar and complete catalog.
**Delivers:** `sure commands --json`, canonical command builder with POSIX/PowerShell quoting, `sure open` / `sure://host/path` links, web "Copy CLI command" surfaces and command palette, docs page.
**Addresses:** Copyable commands, deep links, discoverability.
**Avoids:** Server-side execution, shell injection, secrets in command text.

### Phase 8: Full Parity, Hardening & Release
**Rationale:** Parity is an audit and gap-closure exercise, not a big-bang feature; release hardening needs the full surface.
**Delivers:** Settings/family settings/providers/usage commands, reset/delete with typed confirmation, documented-API coverage audit, high-value server API gap closure (following the API consistency checklist) or explicit web fallback, contract tests, compatibility matrix, gem/container/Homebrew release, completions, docs, security review.
**Addresses:** Full parity, quality, release.
**Avoids:** Silent coverage gaps, undocumented drift, unsafe admin commands.

### Phase Ordering Rationale

- Authentication and the HTTP pipeline are prerequisites for every command.
- Read before write: it validates money, pagination, tenancy, and error shapes with no mutation risk.
- Writes before async workflows: imports and sync reuse the risk policy and idempotency rules.
- OAuth after API-key flows: it changes credential acquisition, not command behavior.
- AI after core CRUD: chat adds streaming and a different failure model.
- Platform handoff after the command grammar stabilizes, so generated commands do not churn.
- Parity and release last: coverage can only be audited against a complete command set.

### Research Flags

Phases likely needing deeper research during planning:
- **Phase 3:** Confirm exact write semantics for splits, `kind`, `excluded`, and transaction idempotency against request specs.
- **Phase 4:** Validate import-session chunk limits, export download streaming, and sync status transitions.
- **Phase 5:** Validate DCR metadata, reserved client names, loopback ports, and refresh behavior.
- **Phase 8:** Decide which server-side API gaps are worth closing versus deep-linking to the web.

Phases with standard patterns (skip research-phase):
- **Phase 1:** Well-understood gem, Thor, Faraday, and keychain patterns.
- **Phase 2:** Endpoint guides and OpenAPI are explicit.
- **Phase 7:** Command catalog and deep-link generation are local, deterministic work.

## Confidence Assessment

| Area | Confidence | Notes |
|------|------------|-------|
| Stack | HIGH | Versions verified; keychain fallback and Homebrew packaging are MEDIUM |
| Features | HIGH | Derived from the checked-in API, routes, and client docs |
| Architecture | HIGH | Follows existing repo conventions and a conventional layered CLI |
| Pitfalls | HIGH | Verified against controllers, models, and API guides |

**Overall confidence:** HIGH

### Gaps to Address

- **Cross-platform keychain:** Windows has no dependable built-in Ruby binding; plan a restricted file fallback and document it.
- **Server version negotiation:** There is no `GET /api/v1/meta` or `X-Sure-Version` today; use a capability probe and a compatibility matrix, and consider adding a version header later.
- **Undocumented endpoints:** `POST /api/v1/sync` and `GET /api/v1/usage` are routed but absent from OpenAPI; add them to the spec or treat them as preview.
- **Write coverage:** Accounts, budgets, rules, holdings, transfers, securities, and providers are read-only via the API; full parity requires either server work or explicit web fallbacks.
- **Rate-limit tiers:** Managed standard keys are 100 req/hour; confirm premium/enterprise behavior before promising bulk commands.

## Sources

### Primary (HIGH confidence)
- `docs/api/openapi.yaml`, `docs/api/*.md`, `config/routes.rb`, `app/controllers/api/v1/*`, `app/models/api_key.rb`, `config/initializers/doorkeeper.rb`
- `docs/clients.md`, `docs/llm-guides/architecture.md`, `docs/llm-guides/wealth-agent-harness.md`
- RubyGems and upstream documentation for Thor, Faraday, oauth2, terminal-table, Minitest, WebMock, and VCR

### Secondary (MEDIUM confidence)
- Stripe CLI, GitHub CLI, Plaid CLI, Actual Budget CLI, hledger, and `clig.dev` for command taxonomy and scripting conventions
- OS keychain CLI behavior (`security`, `secret-tool`) across macOS/Linux

### Tertiary (LOW confidence)
- Homebrew and standalone-binary packaging effort for a Ruby CLI; validate during Phase 8

---
*Research completed: 2026-10-31*
*Ready for roadmap: yes*
