# Roadmap: Sure CLI

## Overview

Build a first-party Ruby CLI that turns Sure's HTTP API into a safe, scriptable
terminal client — from an installable gem with API-key authentication, through
read-only reporting and guarded writes, to imports, sync, exports, browser OAuth,
AI chats, and platform handoff. Each phase delivers a usable end-to-end slice;
the final phase audits full API coverage and ships v1.0.

The CLI is a client of the existing Rails server. It never connects to the
database, recomputes financial reports, or executes commands on the server on
behalf of the web platform.

## Phases

**Phase Numbering:**
- Integer phases (1, 2, 3): Planned milestone work
- Decimal phases (2.1, 2.2): Urgent insertions (marked with INSERTED)

- [ ] **Phase 1: Foundation & API-Key Authentication** - Installable gem, profiles, HTTP pipeline, credential store, doctor
- [ ] **Phase 2: Read & Report** - Accounts, transactions, cash flow, balance sheet, budgets, holdings
- [ ] **Phase 3: Safe Writes** - Guarded transaction mutations, splits, tags, recurring, valuations, trades
- [ ] **Phase 4: Imports, Sync & Exports** - Preflight, CSV import, chunked sessions, sync, async exports
- [ ] **Phase 5: Browser OAuth & Credential UX** - Loopback OAuth with PKCE, dynamic registration, refresh
- [ ] **Phase 6: AI Chats & Assisted Workflows** - Chats, messages, streaming, retries, citations
- [ ] **Phase 7: Platform Handoff** - Command catalog, copyable commands, `sure://` deep links, web palette
- [ ] **Phase 8: Full Parity, Hardening & Release** - Coverage audit, settings/providers, contract tests, release

## Phase Details

### Phase 1: Foundation & API-Key Authentication
**Goal:** A user can install the gem, point it at a Sure server, authenticate with an API key, and get one truthful API response through a shared, safe pipeline.
**Mode:** mvp
**Depends on:** Nothing (first phase)
**Requirements:** FOUND-01, FOUND-02, FOUND-03, FOUND-04, FOUND-05, FOUND-06, FOUND-07, FOUND-08, FOUND-09, FOUND-10, AUTH-01, AUTH-02, AUTH-03, AUTH-08, AUTH-09, SAFE-05, SAFE-06
**Success Criteria** (what must be TRUE):
  1. A locally built gem installs and `sure --version` plus `sure help` work without loading Rails.
  2. `sure auth login --api-key` stores the key securely, and `sure auth status` shows server, user, key name, and scopes.
  3. `sure --profile staging accounts list --json` returns server data with exit 0, and piped output is valid JSON.
  4. `sure doctor` diagnoses a bad URL, key, or TLS setting and exits nonzero with an actionable message.
  5. `sure api GET /api/v1/accounts` works, and secrets never appear in output, logs, or debug traces.
**Plans:** 5 plans

Plans:
- [ ] 01-01: Gem skeleton, executable, version, help, initial operation catalog
- [ ] 01-02: Config, named profiles, server URL/path/TLS handling, precedence
- [ ] 01-03: Faraday pipeline, error mapping, exit codes, redaction, pagination base
- [ ] 01-04: API-key credential store (keychain + file fallback) and auth commands
- [ ] 01-05: `sure doctor`, `sure api`, shell completion, base output formatters

### Phase 2: Read & Report
**Goal:** A user can inspect accounts, transactions, reports, budgets, and holdings from the terminal with the same numbers the web dashboard shows.
**Mode:** mvp
**Depends on:** Phase 1
**Requirements:** READ-01, READ-02, READ-03, READ-04, READ-05, READ-06, READ-07, READ-08, READ-09, READ-11, READ-12
**Success Criteria** (what must be TRUE):
  1. `sure accounts list`, `sure txns list`, and `sure txns show` return accurate data with filters and pagination.
  2. `sure cashflow --month YYYY-MM` matches the web dashboard, including the optional Sankey graph.
  3. `sure balance-sheet`, `sure budgets`, and `sure holdings` use server totals and exact currencies.
  4. `--all` streams pages with deduplication and bounded memory; JSON/CSV output is stable and `jq`-friendly.
  5. No command recomputes financial totals locally, and mixed-currency data never produces a mixed sum.
**Plans:** 5 plans

Plans:
- [ ] 02-01: Money value object, presenters, table/JSON/CSV formatters
- [ ] 02-02: Accounts, balances, and transaction list/show resources with filters
- [ ] 02-03: Cash flow (with Sankey), balance sheet, budgets, budget categories
- [ ] 02-04: Holdings, securities, prices, valuations, insights, usage, transfers
- [ ] 02-05: Pagination/streaming normalizer and read integration tests

### Phase 3: Safe Writes
**Goal:** A user can create, edit, split, and delete financial records with real previews, explicit confirmation, and no duplicate side effects.
**Mode:** mvp
**Depends on:** Phase 2
**Requirements:** WRITE-01, WRITE-02, WRITE-03, WRITE-04, WRITE-05, WRITE-06, WRITE-07, WRITE-08, WRITE-09, SAFE-01, SAFE-02, SAFE-03, SAFE-04
**Success Criteria** (what must be TRUE):
  1. A user can create, edit, and delete a transaction, and the result appears correctly in the web app.
  2. A split is rejected before the request unless children sum exactly to the parent amount.
  3. `--dry-run` performs no writes, and destructive commands require `--yes` or a typed phrase.
  4. Repeating a transaction create with the same `source` and `external_id` returns the existing record instead of duplicating it.
  5. A batch write reports per-item results and exits nonzero if any item failed.
**Plans:** 5 plans

Plans:
- [ ] 03-01: Risk policy, confirmation prompts, dry-run framework, scope preflight
- [ ] 03-02: Transaction create/update/delete with idempotent create
- [ ] 03-03: Splits, tags, and category commands
- [ ] 03-04: Recurring transactions, valuations, and trades
- [ ] 03-05: Batch write runner, partial-failure reporting, write integration tests

### Phase 4: Imports, Sync & Exports
**Goal:** A user can move data in and out of Sure and run long jobs without guessing whether they finished.
**Mode:** mvp
**Depends on:** Phase 3
**Requirements:** DATA-01, DATA-02, DATA-03, DATA-04, DATA-05, DATA-06, DATA-07, DATA-08, READ-10
**Success Criteria** (what must be TRUE):
  1. `sure import preflight` shows columns, warnings, and row counts before any write.
  2. A CSV import reports progress and per-row failures, and a failed row is inspectable afterward.
  3. An interrupted chunked import session resumes without duplicating rows.
  4. `sure sync run --wait` reaches a terminal state and reports the sync outcome.
  5. An export request polls to completion and downloads the archive; a 429 honors `Retry-After` and exits nonzero.
**Plans:** 5 plans

Plans:
- [ ] 04-01: Async job model with `--wait`, timeout, backoff, and resume hints
- [ ] 04-02: Import preflight, single CSV import, row diagnostics
- [ ] 04-03: Chunked import sessions with stable client IDs
- [ ] 04-04: Sync trigger, status, latest, and error reporting
- [ ] 04-05: Family exports, full-history download, rate-limit and large-file tests

### Phase 5: Browser OAuth & Credential UX
**Goal:** A user can log in through the browser and stay logged in without pasting long-lived API keys.
**Mode:** mvp
**Depends on:** Phase 4
**Requirements:** AUTH-04, AUTH-05, AUTH-06, AUTH-07
**Success Criteria** (what must be TRUE):
  1. `sure auth login` opens the browser, completes a loopback callback, and stores a token.
  2. Dynamic client registration succeeds with an allowed, non-reserved client name.
  3. An expired access token refreshes automatically, and a failed refresh gives a clear re-login instruction.
  4. `sure auth logout` clears local credentials and revokes the token when the server supports it.
  5. No token is written to config, logs, or shell history.
**Plans:** 4 plans

Plans:
- [ ] 05-01: Loopback callback server, PKCE verifier/challenge, state validation
- [ ] 05-02: Dynamic client registration and browser/headless fallback
- [ ] 05-03: Token refresh, expiry handling, logout/revoke
- [ ] 05-04: Credential-store hardening and cross-platform tests

### Phase 6: AI Chats & Assisted Workflows
**Goal:** A user can use Sure's AI chats and insights from the terminal, with the same citations and server truth as the web.
**Mode:** mvp
**Depends on:** Phase 5
**Requirements:** AI-01, AI-02, AI-03, AI-04, AI-05, AI-06
**Success Criteria** (what must be TRUE):
  1. `sure chats list` and `sure chats show` display messages and citations.
  2. A user can create a chat, send a message, and see a streamed response on a TTY.
  3. `sure chats send --json` works non-interactively and returns a parseable envelope.
  4. Retrying the last response replaces or appends the assistant reply without duplicating the user message.
  5. Chat output never presents a locally computed figure as a server answer.
**Plans:** 3 plans

Plans:
- [ ] 06-01: Chat and message resources, create/rename/delete, message send
- [ ] 06-02: Streaming and polling renderer with citations
- [ ] 06-03: Retry, non-interactive mode, chat integration tests

### Phase 7: Platform Handoff
**Goal:** A user can reproduce a Sure platform action as a CLI command or jump from the terminal to the exact web record, without the server executing anything.
**Mode:** mvp
**Depends on:** Phase 6
**Requirements:** PLAT-01, PLAT-02, PLAT-03, PLAT-04, PLAT-05, PLAT-06, PLAT-07
**Success Criteria** (what must be TRUE):
  1. `sure commands --json` exports a complete, validated catalog of commands, arguments, flags, risk levels, and examples.
  2. Key Sure web pages show a "Copy CLI command" action, and the copied command runs successfully.
  3. `sure open transaction <entry_id>` opens the matching web page through a `sure://` deep link.
  4. The web command palette lists supported commands and never executes them server-side.
  5. Command and deep-link generation resists shell injection from names, notes, and search terms.
**Plans:** 5 plans

Plans:
- [ ] 07-01: Operation catalog schema, generation, and coverage test
- [ ] 07-02: Canonical command builder with POSIX/PowerShell quoting and redaction
- [ ] 07-03: Deep-link resolver and `sure open`
- [ ] 07-04: Web copy-command component and command palette
- [ ] 07-05: Docs, injection tests, and end-to-end handoff verification

### Phase 8: Full Parity, Hardening & Release
**Goal:** Every documented Sure API operation is reachable or explicitly falls back to the web, and v1.0 ships with tested packaging and docs.
**Mode:** mvp
**Depends on:** Phase 7
**Requirements:** PARITY-01, PARITY-02, PARITY-03, PARITY-04, PARITY-05, PARITY-06, PARITY-07, QUAL-01, QUAL-02, QUAL-03, QUAL-04, QUAL-05, QUAL-06, QUAL-07, QUAL-08, QUAL-09, QUAL-10, QUAL-11
**Success Criteria** (what must be TRUE):
  1. A coverage audit maps every documented `/api/v1` operation to a command, a web fallback, or an exclusion with a reason, and CI fails on drift.
  2. Settings, family settings, providers, usage, and danger-zone commands work with appropriate safeguards.
  3. Contract tests pass against a pinned OpenAPI snapshot and a live server matrix.
  4. The gem, container image, shell completions, and optional Homebrew formula publish from a `cli-v*` tag.
  5. A security review confirms no secret leakage, unsafe shell generation, or unguarded destructive path remains.
**Plans:** 5 plans

Plans:
- [ ] 08-01: Settings, family settings, providers, usage, and danger-zone commands
- [ ] 08-02: Coverage audit, explicit web fallbacks, server-gap decisions
- [ ] 08-03: Contract tests, compatibility matrix, sanitized fixtures
- [ ] 08-04: Packaging, release workflow, container, Homebrew, completions
- [ ] 08-05: Docs, update check, security review, v1.0.0 release

## Progress

**Execution Order:**
Phases execute in numeric order: 1 → 2 → 3 → 4 → 5 → 6 → 7 → 8

| Phase | Plans Complete | Status | Completed |
|-------|----------------|--------|-----------|
| 1. Foundation & API-Key Authentication | 0/5 | Not started | - |
| 2. Read & Report | 0/5 | Not started | - |
| 3. Safe Writes | 0/5 | Not started | - |
| 4. Imports, Sync & Exports | 0/5 | Not started | - |
| 5. Browser OAuth & Credential UX | 0/4 | Not started | - |
| 6. AI Chats & Assisted Workflows | 0/3 | Not started | - |
| 7. Platform Handoff | 0/5 | Not started | - |
| 8. Full Parity, Hardening & Release | 0/5 | Not started | - |
