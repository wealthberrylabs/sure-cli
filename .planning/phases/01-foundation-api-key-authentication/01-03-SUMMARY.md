---
phase: 01-foundation-api-key-authentication
plan: 03
subsystem: cli
tags: [ruby, faraday, http, redaction, exit-codes, output-contract, json, table, pagination, sure-api]

# Dependency graph
requires:
  - phase: 01-foundation-api-key-authentication
    provides: "Standalone gem, Thor surface, runtime injection, and the 0-9 error taxonomy from Plan 01-01"
  - phase: 01-foundation-api-key-authentication
    provides: "Resolved profiles, prefix-preserving URLs, TLS policy, and the environment-first API-key provider from Plan 01-02"
provides:
  - "One Faraday pipeline with header-only auth, bounded GET/HEAD retries, no redirects, and no request data on exceptions"
  - "Semantic HTTP/local error mapping (D-13) with response status, headers, and request ID preserved"
  - "Redaction of the active credential, sensitive headers, query parameters, and 64-hex key shapes on every output path"
  - "Stable schema_version 1 JSON envelope plus TTY table with safe arbitrary-JSON inference"
  - "Collection envelope and per_page validation shared by later read commands"
  - "`sure api METHOD PATH` with path/method validation, write confirmation, --dry-run, --raw, and --verbose"
affects: [01-04, 01-05, phase-2, phase-3, phase-7]

# Tech tracking
tech-stack:
  added: []
  patterns:
    - "Commands construct one memoized HTTP::Client through Context; no command builds a Faraday connection"
    - "HTTP failure -> Errors::Mapper -> Runner is the only exit-code path; commands never exit"
    - "One Redactor instance per command, registered with the active key by AuthMiddleware"
    - "Output::Result -> Output::Selector -> Json/Table is the only rendering path"
    - "Output data on stdout; warnings, prompts, and verbose lines on stderr"

key-files:
  created:
    - cli/lib/sure/redactor.rb
    - cli/lib/sure/errors/mapper.rb
    - cli/lib/sure/http/connection.rb
    - cli/lib/sure/http/client.rb
    - cli/lib/sure/http/response.rb
    - cli/lib/sure/http/rate_limit.rb
    - cli/lib/sure/http/auth_middleware.rb
    - cli/lib/sure/http/envelope.rb
    - cli/lib/sure/http/pagination.rb
    - cli/lib/sure/output.rb
    - cli/lib/sure/output/result.rb
    - cli/lib/sure/output/column.rb
    - cli/lib/sure/output/base.rb
    - cli/lib/sure/output/json.rb
    - cli/lib/sure/output/table.rb
    - cli/lib/sure/output/selector.rb
    - cli/test/support/local_http_server.rb
    - cli/test/support/fake_tty.rb
    - cli/test/fixtures/api/usage.json
    - cli/test/fixtures/api/accounts.json
    - cli/test/fixtures/api/error_401.json
    - cli/test/fixtures/api/error_429.json
    - cli/test/fixtures/api/error_500.json
    - cli/test/unit/redactor_test.rb
    - cli/test/unit/errors/mapper_test.rb
    - cli/test/unit/http/client_test.rb
    - cli/test/unit/http/pagination_test.rb
    - cli/test/unit/output/json_test.rb
    - cli/test/unit/output/table_test.rb
    - cli/test/unit/output/selector_test.rb
    - cli/test/commands/api_test.rb
    - cli/test/integration/api_smoke_test.rb
  modified:
    - cli/lib/sure/cli/runner.rb
    - cli/lib/sure/cli/context.rb
    - cli/lib/sure/cli/application.rb
    - cli/lib/sure/cli/commands/api.rb
    - cli/lib/sure/http/client.rb
    - cli/lib/sure.rb
    - cli/test/test_helper.rb

key-decisions:
  - "RaiseError is declared before Retry so retry_statuses actually sees 429/5xx; the research order raised on the first 503"
  - "AuthMiddleware refuses any origin other than the resolved server, not just injecting the header blindly"
  - "Context owns one Redactor shared by Client, AuthMiddleware, and --raw rendering; the key is registered lazily"
  - "Runner emits a structured JSON error on --json or a non-TTY stdout, and one human line otherwise"
  - "Output::Table infers columns for sure api instead of failing when no Column list exists"
  - "Selector accepts only table/json in this wave; CSV/NDJSON/--fields remain Plan 01-05 work"
  - "--dry-run resolves the profile but never the credential, and prints the fully joined URL"

patterns-established:
  - "Retry policy: GET/HEAD only, max 2, capped 10s; POST/PUT/PATCH/DELETE are never retried"
  - "A 3xx is an error (exit 8); redirects are never followed, so the key cannot move hosts"
  - "sure api rejects absolute URLs, fragments, CR/LF, .., %2e/%2f/%5c (after double decoding), and --data on GET/HEAD"
  - "Write prompts print `Proceed with <METHOD> <path>? [y/N]` to stderr; non-TTY without --yes exits 2 before any request"

requirements-completed: [FOUND-07, FOUND-09, AUTH-09]

# Metrics
duration: 7 min
completed: 2026-11-01
---

# Phase 1 Plan 03: HTTP Pipeline, Output Contract, and `sure api` Summary

**One redacted Faraday pipeline turns a real authenticated `/api/v1` request into a schema_version 1 envelope or TTY table, with every failure mapped to a semantic exit code and no command able to bypass auth, validation, or redaction**

## Performance

- **Duration:** 7 min
- **Started:** 2026-11-01T01:21:59Z
- **Completed:** 2026-11-01T01:28:46Z
- **Tasks:** 3
- **Files modified:** 39

## Accomplishments

- `HTTP::Connection` builds the only Faraday stack: `X-Api-Key` middleware, JSON encode/decode with `allow_nan`, bounded GET/HEAD retries, `raise_error(include_request: false)`, no logger, no redirect following, and profile timeouts/CA/verify settings.
- `Errors::Mapper` maps 401/403→3, 404→4, 400/409/422→5, 429→6, timeout/408/504→9, 5xx/3xx/connection/TLS/malformed JSON→8, Thor→2, and everything else→1, while keeping `http_status`, headers (including `Date`), and `request_id` for `sure doctor`.
- `Sure::Redactor` masks the exact active secret, `Authorization`/`X-Api-Key`/`Proxy-Authorization`, Bearer values, `api_key`-style JSON/query assignments, and 64-hex keys in server messages, exceptions, verbose lines, and `--raw` bodies.
- `Runner` is still the only process boundary: machine mode (`--json` or piped stdout) writes one JSON error object with `error`, `message`, `details`, `request_id`, `http_status`, and `exit_code`; no Ruby backtrace escapes.
- `Output::Json` always emits `data`, `meta.schema_version`, `meta.as_of`, and `meta.warnings`, normalizes `Infinity`/`NaN` to `null` with one warning on stderr, and includes pagination/rate-limit/request metadata when present.
- `Output::Table` renders explicit columns with alignments/formatters, and safely infers rows for arbitrary `sure api` JSON (collection envelope, key/value hash, scalar array).
- `Output::Selector` applies flag → `SURE_OUTPUT` → profile → TTY precedence, enforces `--json`/`--table` exclusivity, and exposes `color?`/`quiet?`/`verbose?`.
- `HTTP::Envelope`/`HTTP::Pagination` normalize both documented collection shapes and validate `per_page` 1–100.
- `sure api` proves the whole chain against a stdlib `TCPServer`: one `X-Api-Key` header, zero `Authorization` headers, prefix-preserving URLs, write confirmation on a TTY (`y`/`n`), non-TTY exit 2, zero-network `--dry-run`, redacted `--raw`, and 401→3.

## Task Commits

Each task was committed atomically:

1. **Task 1: Implement the Faraday pipeline, redactor, and exit-code mapper** - `400896dfe` (feat)
2. **Task 2: Implement the output contract, envelope adapter, and pagination base** - `213003c47` (feat)
3. **Task 3: Implement `sure api` and prove the pipeline end-to-end** - `aeff9bfe8` (feat)
4. **Fixture follow-up: accounts collection fixture** - `50f921d2b` (test)

**Plan metadata:** final `docs(01-03)` commit follows this summary.

## Files Created/Modified

- `cli/lib/sure/http/{connection,client,response,rate_limit,auth_middleware}.rb` - The one request pipeline and its immutable response value
- `cli/lib/sure/errors/mapper.rb` - HTTP/local exception to D-13 exit-code mapping with metadata
- `cli/lib/sure/redactor.rb` - Credential, header, query, and environment redaction
- `cli/lib/sure/{output.rb,output/*.rb}` - Result/Column values, JSON envelope, table inference, format selector
- `cli/lib/sure/http/{envelope,pagination}.rb` - Collection-shape normalization and `per_page` validation
- `cli/lib/sure/cli/{runner,context,application}.rb` - Structured error rendering, one memoized client, `api` options and delegation
- `cli/lib/sure/cli/commands/api.rb` - Validated raw escape hatch with dry-run, confirmation, raw redaction, and verbose logging
- `cli/lib/sure.rb` - Loads the HTTP, output, and redaction namespaces
- `cli/test/**` - 173-run suite including WebMock unit tests and a real local-server integration smoke test

## Decisions Made

- **Middleware order:** `raise_error` is declared before `retry`. Faraday builds response handlers inner-to-outer; the research order made the first 503 raise before the retry middleware could inspect the status. This is the one substantive deviation from the research snippet and is documented below.
- **Origin guard:** `AuthMiddleware` compares the request origin to the resolved server and refuses to send the key elsewhere, rather than relying only on the URL builder.
- **Lazy credential:** `Context#client` never calls the provider; `AuthMiddleware` fetches and registers the secret on the first real request. `--dry-run` therefore works with no key configured.
- **Structured errors:** machine mode is triggered by `--json` or non-TTY stdout, matching the plan, even when `--table` is requested on a pipe.
- **No color code path:** `Output::Table` emits no ANSI at all; `Selector#color?` exists for Plan 01-05 and future colored cells.

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 1 - Bug] Retry middleware could not see retryable statuses behind RaiseError**
- **Found during:** Task 1 (GET 503-then-200 test)
- **Issue:** With `request :retry` declared before `response :raise_error` (the research snippet order), `raise_error` raises `Faraday::ServerError` on the first 503 inside the retry app; retry only matches timeout/RetriableResponse exceptions, so `retry_statuses` never fired and the GET failed without retrying.
- **Fix:** Declared `response :raise_error, include_request: false` first so it wraps Retry; Retry now inspects statuses, retries GET/HEAD, and RaiseError only fires on the final response. Added a comment explaining the ordering.
- **Files modified:** `cli/lib/sure/http/connection.rb`
- **Verification:** GET 503/503/200 is requested three times; POST 503 is requested exactly once; 302 is never followed.
- **Committed in:** `400896dfe`

**2. [Rule 2 - Missing Critical] Socket timeouts surfaced as ConnectionFailed bypassed exit 9**
- **Found during:** Task 1 (timeout mapping test)
- **Issue:** WebMock/`net_http` can wrap an expired socket timeout as `Faraday::ConnectionFailed` ("execution expired"), which mapped to exit 8 instead of the documented timeout code.
- **Fix:** `Mapper#connection_error` detects timeout-shaped ConnectionFailed messages (`timed out`, `timeout`, `execution expired`) and maps them to `Errors::TimeoutError` (9).
- **Files modified:** `cli/lib/sure/errors/mapper.rb`
- **Verification:** `Faraday::TimeoutError`, `Timeout::Error`, and timeout-shaped ConnectionFailed all return 9.
- **Committed in:** `400896dfe`

**3. [Rule 3 - Blocking] `sure api --dry-run` needed a joined URL without a request**
- **Found during:** Task 3 (dry-run implementation)
- **Issue:** `UrlBuilder#join` takes a path without a query; the validated path can carry `?per_page=1`, and `Client#build_url` was private.
- **Fix:** Added public `HTTP::Client#url_for` delegating to the existing URL joining logic; dry-run uses it and normal requests keep the same path/query semantics.
- **Files modified:** `cli/lib/sure/http/client.rb`
- **Verification:** Dry-run prints the exact joined URL for both plain and query-string paths; client request tests still pass.
- **Committed in:** `aeff9bfe8`

**4. [Rule 2 - Missing Critical] Added a selector unit test not listed in the plan**
- **Found during:** Task 2 (acceptance criteria for TTY/pipe selection)
- **Issue:** The plan's file list had no selector test, but four acceptance criteria describe selector behavior.
- **Fix:** Added `cli/test/unit/output/selector_test.rb` covering piped/TTY defaults, flags, `SURE_OUTPUT`, profile precedence, exclusivity, color opt-outs, and quiet/verbose.
- **Files modified:** `cli/test/unit/output/selector_test.rb`
- **Committed in:** `213003c47`

---

**Total deviations:** 4 auto-fixed (1 bug, 2 missing critical coverage/robustness, 1 blocking)
**Impact on plan:** No architectural change. The middleware reorder is required for the plan's retry guarantee; the timeout sniff makes exit 9 reliable on real adapters; the URL helper keeps dry-run honest.

## Issues Encountered

- WebMock's `to_timeout` surfaces as `Faraday::ConnectionFailed` in Faraday 2.14.4, which exposed the timeout-mapping gap above.
- `Output::Table` originally ignored `Column#formatter` for explicit rows; fixed before commit so money/format lambdas apply to both hash rows and positional rows.
- The accounts fixture was created during Task 1 but only staged after Task 3; it is committed separately as `50f921d2b`. No test depended on an uncommitted file at task-commit time because it was present on disk, but the follow-up keeps the repo self-contained.

## User Setup Required

None - no external service configuration required. The integration test uses a loopback TCP server created inside the test process.

## Known Stubs

| File | Stub | Resolved by |
|------|------|-------------|
| `cli/lib/sure/auth/store.rb` | `Auth::NullStore` read-miss and write/delete errors | Plan 01-04 |
| `cli/lib/sure/cli/commands/auth.rb` | `login`, `logout`, `status` placeholders | Plan 01-04 |
| `cli/lib/sure/cli/commands/doctor.rb` | `call` placeholder | Plan 01-05 |
| `cli/lib/sure/cli/commands/completion.rb` | `call` placeholder | Plan 01-05 |

`sure api` replaced its 01-01 placeholder in this plan. The remaining stubs are outside this plan's scope and fail with exit 2 and an actionable message.

## Threat Flags

None beyond the plan's threat model. T-03-01 (no request data on exceptions, no logger, redaction), T-03-02 (GET/HEAD-only retries, no redirects), T-03-03 (origin-checked `X-Api-Key` only, no `--header`), T-03-04 (URI-decoded `/api/v1` path validation and `--data` restrictions), T-03-05 (JSON envelope with non-finite normalization and redacted `--raw`), and T-03-SC (root-locked Faraday/faraday-retry/terminal-table only) are implemented and covered by tests.

## Next Phase Readiness

- Plan 01-04 can build `Auth::FileStore`/keychain stores behind the existing `Auth::Store` contract and reuse `Context#redactor`, `Context#client`, and the provider unchanged.
- Plan 01-05 can extend `Output::Selector` with CSV/NDJSON/`--fields` without touching the envelope or error pipeline; `doctor` already has `http_status`/`headers`/`request_id` on mapped errors.
- Phase 2 read commands should call `HTTP::Envelope.normalize` and pass an `Output::Result`; they must not create a second Faraday connection.
- Verification evidence: `bundle exec rake test` → 173 runs, 700 assertions, 0 failures; `bundle exec rubocop` → 72 files, 0 offenses; `ruby -Itest test/integration/api_smoke_test.rb` → 3 runs, 22 assertions, 0 failures; `grep -R "Faraday.new" cli/lib` → only `connection.rb`; `--version` loads without Rails.

## Self-Check: PASSED

- Task commits `400896dfe`, `213003c47`, `aeff9bfe8`, `50f921d2b` exist on `main`.
- `cli/lib/sure/http/client.rb`, `cli/lib/sure/errors/mapper.rb`, `cli/lib/sure/redactor.rb`, `cli/lib/sure/output/json.rb`, and `cli/lib/sure/cli/commands/api.rb` exist on disk.
- Full suite, lint, and the local-server integration test are green.
- No test or library file is left untracked; only the untracked `.opencode/` tooling directory remains.

---
*Phase: 01-foundation-api-key-authentication*
*Completed: 2026-11-01*
