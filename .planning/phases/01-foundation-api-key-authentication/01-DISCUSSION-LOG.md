# Phase 1: Foundation & API-Key Authentication - Discussion Log

> **Audit trail only.** Do not use as input to planning, research, or execution agents.
> Decisions are captured in CONTEXT.md — this log preserves the alternatives considered.

**Date:** 2026-10-31
**Phase:** 1-Foundation & API-Key Authentication
**Areas discussed:** Command grammar & naming; Credential storage & login UX; Output contract & exit codes

---

## Command Grammar & Naming

### Primary command grammar

| Option | Description | Selected |
|--------|-------------|----------|
| Noun-first plural | `sure accounts list`, `sure transactions add`, `sure budgets show` | ✓ |
| Verb-first | `sure list accounts`, `sure add transaction`, `sure show budget` | |
| Singular noun | `sure account list`, `sure transaction add` | |

**User's choice:** Noun-first plural.
**Notes:** Chosen for scalability and consistency with Stripe/GitHub CLI conventions.

### Aliases

| Option | Description | Selected |
|--------|-------------|----------|
| Curated high-frequency aliases | `tx`, `acct`, `cf`, documented and unambiguous | ✓ |
| No aliases | Canonical full names only | |
| Broad aliases | Alias most domains and verbs | |

**User's choice:** Curated high-frequency aliases.
**Notes:** Generated copy-commands should prefer full canonical names.

### Report grouping

| Option | Description | Selected |
|--------|-------------|----------|
| Top-level + `reports` alias | `sure cashflow` and `sure reports cashflow` | ✓ |
| Strict `reports` group | `sure reports cashflow` only | |
| Top-level only | `sure cashflow` only | |

**User's choice:** Top-level report nouns plus a `reports` alias group.

### Destructive verb

| Option | Description | Selected |
|--------|-------------|----------|
| `delete` only | Explicit, always guarded; no `rm` shortcut | ✓ |
| `delete` + `rm` alias | Faster, higher accident risk | |
| `remove` | Softer wording | |
| `destroy` | Rails-internal flavor | |

**User's choice:** `delete` only.

---

## Credential Storage & Login UX

### Storage strategy

| Option | Description | Selected |
|--------|-------------|----------|
| Keychain-first + file fallback | OS keychain when available; 0600 atomic file otherwise | ✓ |
| Keychain only | Refuse to store without a keychain | |
| Encrypted file with passphrase | Portable but adds friction | |
| No persistent storage | Env/file on every run | |

**User's choice:** Keychain-first with a 0600 atomic file fallback.

### Key input

| Option | Description | Selected |
|--------|-------------|----------|
| Prompt + stdin/file/env, no argv | Hidden prompt; `--api-key-file`, `--api-key-stdin`, `SURE_API_KEY` | ✓ |
| Also allow `--api-key` | Convenient but leaks through `ps` and history | |
| File and env only | No interactive prompt | |

**User's choice:** Prompt + stdin/file/env; no `--api-key` argv flag.

### Plaintext fallback

| Option | Description | Selected |
|--------|-------------|----------|
| Auto-fallback + one warning | 0600 file, warn once per profile, visible in `doctor` | ✓ |
| Require explicit opt-in | `--allow-plaintext` required | |
| Never store plaintext | Require env var each session | |

**User's choice:** Automatic fallback with a one-time warning and `doctor` visibility.

### Logout behavior

| Option | Description | Selected |
|--------|-------------|----------|
| Delete local + explain revocation | Remove locally; tell user to revoke in Settings | ✓ |
| Delete local + open web settings | Same, plus browser launch | |
| Keep local, mark inactive | Secret remains on disk | |

**User's choice:** Delete locally and explain that the API key must be revoked in Sure Settings.

---

## Output Contract & Exit Codes

### Default output

| Option | Description | Selected |
|--------|-------------|----------|
| TTY table, piped JSON | Human tables on a terminal; JSON when piped | ✓ |
| Always JSON | One machine contract; `--table` opt-in | |
| Always table | Human-first; `--json` opt-in | |
| Table + `--porcelain` | Separate stable machine format | |

**User's choice:** TTY table, piped JSON, with explicit overrides.

### JSON envelope

| Option | Description | Selected |
|--------|-------------|----------|
| `{data, meta}` with warnings | Stable keys for data, pagination, as-of, rate limit, warnings, schema version | ✓ |
| Raw API passthrough | Emit server payload exactly | |
| Minimal `{data}` only | No metadata | |
| `{ok, data, error}` | Explicit success flag | |

**User's choice:** Stable `{data, meta}` envelope with warnings and metadata.

### Exit codes

| Option | Description | Selected |
|--------|-------------|----------|
| Semantic map | 0–9 categories for usage, auth, not found, validation, rate limit, partial, network, timeout | ✓ |
| Simple 0/1/2 | Success, failure, usage | |
| `sysexits.h` | Unix standard codes | |
| HTTP-status aligned | Mirror 401/404/422/429 | |

**User's choice:** Semantic exit-code map.

### Diagnostics

| Option | Description | Selected |
|--------|-------------|----------|
| Standard CLI discipline | Data stdout; errors/progress stderr; TTY color; `--quiet`/`--verbose` | ✓ |
| Minimal | Errors stderr and color auto only | |
| Rich by default | Spinners/progress whenever possible | |

**User's choice:** Standard CLI discipline.

---

## the agent's Discretion

- Exact YAML config schema and key names.
- HTTP timeouts and retry policy.
- Keychain service names and atomic-write implementation.
- Table columns and help wording.
- `sure doctor` check order and checks.
- Whether aliases appear in generated copy-commands.
- Raw `sure api` confirmation policy for destructive methods and redaction details.

## Deferred Ideas

None — discussion stayed within phase scope.
