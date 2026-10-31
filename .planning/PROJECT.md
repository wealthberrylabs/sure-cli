# Sure CLI

## What This Is

A first-party command-line interface for Sure, the self-hosted personal finance
app in this repository. It lets a person, a script, or an agent read and act on a
Sure server from a terminal — and lets the Sure web platform surface the
equivalent command so the same operation can be reproduced, shared, or automated
outside the browser.

The CLI is a client of the existing Rails server, not a second implementation of
Sure. It uses the same `/api/v1` surface, authentication, family tenancy,
authorization rules, and financial semantics as the web, desktop, and mobile
clients.

## Core Value

**Any Sure operation a user can perform in the platform can be performed from a
terminal with the same permissions and accounting semantics — and any platform
action can be reproduced as a copyable CLI command.**

If everything else fails, this must work: a user points the CLI at their Sure
server, authenticates, and gets the same truthful financial data the web app
shows.

## Requirements

### Validated

<!-- Platform capabilities the CLI can rely on today. These are not CLI deliverables. -->

- ✓ Family-scoped accounts, balances, entries, holdings, and valuations — existing server model
- ✓ Documented `/api/v1` HTTP surface (110 operations) with pagination and filters — existing
- ✓ `X-Api-Key` authentication with `read` / `read_write` scopes — existing
- ✓ Doorkeeper OAuth 2.0 authorization-code flow and dynamic client registration — existing
- ✓ Transaction, budget, category, merchant, tag, rule, import, sync, chat, and settings APIs — existing
- ✓ MCP endpoint for external agents — existing, separate from this project
- ✓ Web, macOS desktop, and Flutter mobile clients — existing

### Active

- [ ] User can install the CLI as a Ruby gem and run `sure` from any shell.
- [ ] User can configure multiple named Sure servers and switch between them.
- [ ] User can authenticate with an API key without editing files by hand.
- [ ] User can authenticate through a browser with OAuth in a later phase.
- [ ] User can read accounts, balances, transactions, cash flow, budgets, holdings, and reports.
- [ ] User can create, edit, categorize, split, and delete transactions, tags, merchants, and rules.
- [ ] User can run CSV imports and inspect or trigger syncs.
- [ ] User can use Sure's AI chats, insights, and spending comparisons from the terminal.
- [ ] User can reach the remaining API surface (settings, providers, exports, transfers, valuations).
- [ ] User can choose human-readable tables or stable machine-readable JSON/CSV output.
- [ ] User can script the CLI safely: non-interactive mode, deterministic exit codes, no prompts on a pipe.
- [ ] User can preview destructive actions with `--dry-run` and confirm them explicitly.
- [ ] User can copy a CLI command or open a `sure://` deep link from the Sure web platform.
- [ ] User can discover commands through help, examples, shell completion, and generated docs.
- [ ] Maintainers can verify the CLI against a running Sure instance in CI without a browser.

### Out of Scope

- **Server-side command execution from the web UI** — the platform may show or
  deep-link a command, but it must never execute a shell command on the server.
  Reason: remote code execution and multi-tenant blast radius.
- **Embedded web terminal** — a terminal panel is a second UI and a security
  boundary; not needed to prove the CLI.
- **Direct database access** — the CLI must not connect to Postgres or read Rails
  internals. Reason: bypasses authorization, tenancy, and the API contract.
- **A second financial engine** — balances, cash flow, budgets, and classification
  stay server-calculated. The CLI formats; it does not recompute.
- **Replacing the web app** — the CLI is an additional client, not a migration path.
- **Storing credentials in the repository or in plaintext config** — secrets belong
  in the OS keychain or a permission-restricted credential store.
- **A GUI, TUI dashboard, or full-screen app** — initial scope is command-based;
  an interactive TUI can be a later milestone.

## Context

Sure is a Rails 8.1 / Ruby 3.4 application backed by PostgreSQL and Redis. It
supports `managed` and `self_hosted` modes; provider availability differs by
installation. The repository already ships a macOS Tauri shell, a Flutter mobile
app, a `bin/sure-backup` operator script, and an MCP server. There is no
first-party general-purpose CLI today.

Key facts that shape the design:

- The API is documented in `docs/api/openapi.yaml` and generated from request
  specs. Endpoint guides live in `docs/api/`.
- API authentication accepts either `X-Api-Key` or a Doorkeeper bearer token.
  API keys are opaque, scoped to `read` or `read_write`, and created in
  **Settings → API Keys**.
- OAuth dynamic client registration already allows loopback redirect URIs, so a
  browser-based CLI login is feasible without new server endpoints.
- Doorkeeper is configured with `use_refresh_token` and `read` / `read_write`
  scopes; no device grant is configured today.
- Family tenancy, account sharing rules, `Current.user` / `Current.family`, and
  `Money` currency semantics are enforced server-side. The CLI must preserve them.
- The web platform's cash-flow endpoint is the authoritative reporting surface;
  native clients are told not to rebuild reporting rules from transactions.
- MCP exists for agents and is intentionally separate. The CLI should not become
  a second MCP implementation; it may later call MCP tools where that is the
  better contract.

## Constraints

- **Language**: Ruby, matching the repository's runtime (`.ruby-version` 3.4.9).
  Reason: one toolchain, shared conventions, and the platform can invoke the gem
  directly if needed.
- **Transport**: HTTP `/api/v1` only. Reason: preserve authentication, tenancy,
  scopes, and server-calculated financial semantics.
- **Authentication**: API key first; OAuth authorization-code with loopback
  callback later. Reason: API keys work on every current deployment with no
  server change.
- **Distribution**: RubyGems plus a container image; optional Homebrew formula.
  Reason: self-hosters already run Ruby or Docker, and a gem keeps the release
  close to the server.
- **Compatibility**: support the current and previous minor Sure server versions.
  Reason: self-hosted users upgrade on their own schedule.
- **Security**: never log or echo API keys; redact `Authorization` and
  `X-Api-Key`; require explicit confirmation for destructive operations.
- **Repository fit**: the CLI lives in `cli/` as its own gem, with its own
  `Gemfile`, tests, and release workflow. It must not add runtime dependencies to
  the Rails app or change existing API behavior without following the API
  consistency checklist.
- **Licensing**: AGPLv3, consistent with the repository.
- **Platform integration**: copyable commands and `sure://` deep links only; no
  server-side execution.

## Key Decisions

| Decision | Rationale | Outcome |
|----------|-----------|---------|
| Ruby gem implemented with Thor (or equivalent) | Same runtime as Sure; reusable conventions; can be invoked by Rails; natural gem distribution for self-hosters | — Pending |
| Build on the public HTTP API, never the database | Preserves auth, tenancy, scopes, and server-side financial rules | — Pending |
| API-key login first, OAuth loopback second | API keys work today on every deployment; OAuth improves UX without a device grant | — Pending |
| Full API parity, delivered in phases | User asked for a CLI version of the platform, not a read-only reporting tool | — Pending |
| Platform trigger = copyable command + `sure://` deep link | Delivers the requested workflow without remote command execution risk | — Pending |
| Human tables on a TTY, JSON when piped, explicit `--json`/`--csv` | Serves both interactive users and scripts without a second command set | — Pending |
| Separate `cli/` gem inside the monorepo | Keeps Rails dependencies and release cadence independent | — Pending |
| Dry-run and confirmation for destructive commands | Financial data is high-consequence; accidental deletes are unacceptable | — Pending |

## Evolution

This document evolves at phase transitions and milestone boundaries.

**After each phase transition** (via `/gsd-transition`):
1. Requirements invalidated? → Move to Out of Scope with reason
2. Requirements validated? → Move to Validated with phase reference
3. New requirements emerged? → Add to Active
4. Decisions to log? → Add to Key Decisions
5. "What This Is" still accurate? → Update if drifted

**After each milestone** (via `/gsd-complete-milestone`):
1. Full review of all sections
2. Core Value check — still the right priority?
3. Audit Out of Scope — reasons still valid?
4. Update Context with current state (users, feedback, metrics)

---
*Last updated: 2026-10-31 after initialization*
