# Phase 1 — Review Response

**Source:** `01-REVIEWS.md` (GPT-6 Luna and Gemini 4 Argon, 2026-11-01)
**Replanned:** 2026-11-01
**Plans revised:** 01-01, 01-02, 01-03, 01-04, 01-05

## Review Feedback Addressed

| Concern | Severity | How addressed |
|---|---|---|
| AUTH-09: `Credential` default `inspect` leaks the secret | HIGH | 01-02 Task 3: `Credential#inspect`/`#to_s` redact `secret`; test asserts `[REDACTED]`. |
| AUTH-09: active non-64-hex key can leak | HIGH | 01-03 Task 1: `Redactor.new(active_secret:)` masks the exact key in server messages, exceptions, verbose lines, and raw bodies; non-64-hex test. |
| AUTH-09: `--raw` can print a key | HIGH | 01-03 Task 3: `--raw` removes the envelope but still passes the body through the active-secret redactor; test. |
| AUTH-09: `Runner` error rendering predates `Redactor` | HIGH | 01-03 Task 1: `cli/lib/sure/cli/runner.rb` is modified to redact every error and emit structured JSON on stderr in machine mode. |
| AUTH-09: Thor echoes `--api-key=secret` | HIGH | 01-01 Task 2: pre-parse argv scan rejects `--api-key` without echoing the value; test. |
| Output ownership duplicated between 01-03 and 01-05 | HIGH | 01-03 Task 2 now implements only JSON/Table; 01-05 Task 1 owns CSV/NDJSON/FieldSelection and the selector/flags. |
| Thor `doctor`/`completion` mounted as subcommands | HIGH | 01-01 Task 2: `doctor`, `api`, and `completion` are top-level `Application` methods; only `auth` is a subcommand group. |
| Thor help ignores injected IO | MEDIUM | 01-01 Task 2: `Sure::CLI::Shell` bridges `runtime.stdout`/`stderr`; StringIO help test. |
| Doctor aborts on missing config/server | MEDIUM | 01-05 Task 2: `Doctor::Runner` builds config/provider directly and catches errors into FAIL/SKIP; fresh-install test. |
| Doctor loses status/headers on 401/403 | MEDIUM | 01-03 Task 1: `Errors::Error` carries `http_status`/`headers`; check 4/8 test. |
| Doctor repeats `/usage` requests | MEDIUM | 01-05 Task 2: one `/usage` response reused; accounts probe only after connectivity/auth pass. |
| Ruby/Bundler toolchain unavailable | HIGH | 01-01 Task 0: devcontainer → version manager → blocking human checkpoint; no sudo. |
| Rails test DB/rswag provisioning | HIGH | 01-04 Task 3 + `user_setup`: devcontainer `db`/`redis` preflight; no automatic migrations; blocking checkpoint if unreachable. |
| `sure api` TTY confirmation undefined | MEDIUM | 01-03 Task 3: TTY writes prompt `[y/N]` through runtime streams; non-TTY requires `--yes`; both tested. |
| `sure api` path boundary too loose | MEDIUM | 01-03 Task 3: exact `/api/v1` or `/api/v1/`; rejects `/api/v10`, encoded traversal/separators; tests. |
| `sure api` table rendering of arbitrary JSON | MEDIUM | 01-03 Task 2: infer columns from collection/first Hash; single Hash key/value; scalar array `value`. |
| CA-bundle relative path/readability | MEDIUM | 01-02 Task 2: flag/env relative to cwd, profile relative to config dir, readable check, exit 2. |
| Base URL ending `/api/v1` | MEDIUM | 01-02 Task 2: reject `/api` or `/api/v1` suffix with guidance. |
| Windows POSIX permission checks | MEDIUM | 01-02 Task 1: `unless Gem.win_platform?` guard; symlink refusal still applies. |
| Config read-modify-write race | MEDIUM | 01-02 Task 1: `config.lock` + flock around re-read/merge/write; concurrent test. |
| FileStore lockfile/race handling | MEDIUM | 01-04 Task 1: lock file `0600`, no symlink, `ensure` release; fallback transition table + tests. |
| Hidden prompt bypasses injected runtime | MEDIUM | 01-04 Task 2: prompt to `runtime.stderr`, read via `runtime.stdin.getpass`/`noecho`; FakeTTY test. |
| `/usage` user payload includes unnecessary `id` | HIGH (one reviewer) | 01-04 Task 3: minimal `{email, first_name, last_name}`; `id` absent and asserted. |
| API consistency checklist missing | MEDIUM | 01-04 Task 3: `docs/llm-guides/api-endpoint-consistency.md` read/verified and noted. |
| Catalog handoff drift | MEDIUM | 01-01 Task 2 creates one schema; Task 3 only adds entries and validator. |
| Completion shell-token injection | MEDIUM | 01-05 Task 3: conservative token grammar, description escaping, malicious-catalog fixture. |

## Review Feedback Deferred / Judgment Calls

| Concern | Reason |
|---|---|
| Include `user.id` in `/usage` | Deliberately omitted: no Phase 1 consumer; minimizes personal data. Divergent reviewer accepted the existing mobile shape, but the smaller payload still satisfies AUTH-03. |
| Overall risk rating disagreement (HIGH vs LOW/MEDIUM) | Calibration difference, not a scope disagreement; all concrete fixes above are addressed. |
| Full nested `--fields` dotted paths | Deferred to a later phase; Phase 1 projects top-level keys only and says so explicitly. |
| Publish gem to RubyGems | Out of scope; Phase 8 release work. |
| Replace OpenCode-based review with a second external CLI | Deferred: `claude`/`codex` are installed but unauthenticated; review provenance is disclosed in `01-REVIEWS.md`. |

## Result

The five plans remain in five waves with the same 17 Phase 1 requirements. The review changes are targeted hardening and interface clarifications; no phase scope was added. `01-03` now proves the walking skeleton (JSON/table + `sure api`), and `01-05` owns the remaining machine formats, doctor, and completion.
