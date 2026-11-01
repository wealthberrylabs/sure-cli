---
phase: 01-foundation-api-key-authentication
plan: 05
subsystem: cli
tags: [ruby, csv, ndjson, field-selection, doctor, diagnostics, shell-completion, non-tty, minitest]

# Dependency graph
requires:
  - phase: 01-foundation-api-key-authentication
    provides: "Resolved profiles, SURE_OUTPUT handling, and URL/CA/TLS resolution from Plan 01-02"
  - phase: 01-foundation-api-key-authentication
    provides: "Output::Result/Json/Table/Selector, the Faraday pipeline, redaction, and exit-code mapping from Plan 01-03"
  - phase: 01-foundation-api-key-authentication
    provides: "StoreFactory modes, Auth::Status, and credential sources from Plan 01-04"
provides:
  - "CSV and NDJSON formatters plus one shared --fields projection across JSON, table, CSV, and NDJSON"
  - "Terminal-safe table cells and spreadsheet-formula neutralising in CSV"
  - "sure doctor with nine ordered, non-short-circuiting checks and first-failure exit codes"
  - "Catalog-driven bash/zsh/fish completion with validated tokens and snapshots"
  - "A non-TTY regression suite proving no prompt path hangs without a TTY"
affects: [phase-2, phase-3, phase-4, phase-5, phase-6, phase-7, phase-8]

# Tech tracking
tech-stack:
  added: []
  patterns:
    - "All four formats share Output::FieldSelection; unknown fields are usage errors before rendering"
    - "JSON projects fields inside a collection envelope rather than on envelope keys"
    - "Doctor checks own their prerequisites through explicit state flags and report SKIP instead of secondary failures"
    - "Doctor's rendered checklist is followed by a silent exit-status error, so the process boundary adds no second line"
    - "Completion scripts are generated only from validated catalog tokens and fixed option names"

key-files:
  created:
    - cli/lib/sure/output/csv.rb
    - cli/lib/sure/output/ndjson.rb
    - cli/lib/sure/output/field_selection.rb
    - cli/lib/sure/doctor/check.rb
    - cli/lib/sure/doctor/result.rb
    - cli/lib/sure/doctor/runner.rb
    - cli/lib/sure/completion/generator.rb
    - cli/test/unit/output/formatters_test.rb
    - cli/test/unit/output/field_selection_test.rb
    - cli/test/unit/doctor/runner_test.rb
    - cli/test/commands/doctor_test.rb
    - cli/test/commands/completion_test.rb
    - cli/test/commands/non_tty_test.rb
    - cli/test/fixtures/completion/sure.bash
    - cli/test/fixtures/completion/_sure
    - cli/test/fixtures/completion/sure.fish
  modified:
    - cli/lib/sure/output.rb
    - cli/lib/sure/output/base.rb
    - cli/lib/sure/output/column.rb
    - cli/lib/sure/output/json.rb
    - cli/lib/sure/output/selector.rb
    - cli/lib/sure/output/table.rb
    - cli/lib/sure/config/resolver.rb
    - cli/lib/sure/cli/application.rb
    - cli/lib/sure/cli/commands/api.rb
    - cli/lib/sure/cli/commands/auth.rb
    - cli/lib/sure/cli/commands/doctor.rb
    - cli/lib/sure/cli/commands/completion.rb
    - cli/lib/sure/cli/runner.rb
    - cli/lib/sure/errors/error.rb
    - cli/lib/sure.rb
    - cli/test/unit/output/selector_test.rb
    - cli/test/unit/config/resolver_test.rb
    - cli/test/unit/errors/mapper_test.rb
    - cli/test/commands/version_help_test.rb

key-decisions:
  - "Field selection validates against collection item keys inside an envelope, so --fields name,balance works on sure api without exposing envelope keys"
  - "Doctor resolves config, profile, and credential inside checks and tracks success explicitly; a missing config becomes Check 1 FAIL instead of an uncaught UsageError"
  - "Doctor reports the first FAIL code through a silent ExitStatusError because the checklist is the complete output"
  - "CSV uses CSV.generate, strips terminal controls, and prefixes only non-numeric formula text; numeric negatives such as -12.34 stay unchanged"
  - "Completion never interpolates descriptions into shell command positions; only validated tokens and fixed flags are emitted"
  - "Unsupported shells and unsafe catalog tokens are usage errors (exit 2) before any script reaches stdout"

patterns-established:
  - "One Result -> Selector -> formatter path; commands never branch on output format except doctor's shared Result"
  - "Table cells remove C0 controls and flatten line breaks; CSV removes controls while leaving quoting to the CSV library"
  - "Doctor dependency chain: config -> profile -> credential -> connectivity -> authentication -> scope/capability/rate-limit"
  - "Completion fixtures are byte-for-byte snapshots regenerated only when the implemented catalog or flags change"

requirements-completed: [FOUND-05, FOUND-06, FOUND-08, FOUND-10, SAFE-05]

# Metrics
duration: 9 min
completed: 2026-11-01
---

# Phase 1 Plan 05: Output Formats, Doctor, and Completion Summary

**Every phase-one command now renders identical data as JSON, table, CSV, or NDJSON with a shared `--fields` projection, while `sure doctor` diagnoses nine ordered checks and `sure completion` emits validated bash/zsh/fish scripts**

## Performance

- **Duration:** 9 min
- **Started:** 2026-11-01T01:52:00Z
- **Completed:** 2026-11-01T02:02:00Z
- **Tasks:** 3
- **Files modified:** 35

## Accomplishments

- `Output::Csv` uses `CSV.generate` for quoting, prefixes only non-numeric formula text (`=`, `+`, `-`, `@`), leaves numeric negatives untouched, and strips terminal control characters.
- `Output::Ndjson` emits exactly one compact JSON object per data item, projects `--fields` per record, and normalizes non-finite floats to `null`.
- `Output::FieldSelection` is the single allowlist shared by JSON, table, CSV, and NDJSON; empty segments, duplicates, and unknown fields are exit 2 with the available names.
- JSON field selection now descends into a collection envelope, so `--fields name,balance` works identically on `sure api` responses and on commands with explicit columns.
- `Output::Table` filters explicit columns or inferred headings, flattens line breaks, and removes escape sequences so server strings cannot reshape the terminal.
- `sure doctor` runs nine ordered checks without short-circuiting: config permissions, profile URL, credential presence and storage mode, connectivity/TLS, authentication, scope, server capability, clock skew, and rate limit.
- Doctor reuses one `/usage` response for connectivity, authentication, scope, clock, and rate limits; the `/api/v1/accounts?per_page=1` probe runs only after authentication succeeds.
- A fresh install with no `config.yml` reports Check 1 `FAIL` with `Run sure auth login` instead of raising an uncaught error.
- 401 on `/usage` still proves reachability, fails authentication, skips dependent checks, and reads the `Date` header; a capability 401 exits 3.
- `sure completion bash|zsh|fish` is generated from implemented catalog entries, validates every command token, includes canonical names and aliases, and rejects unsupported shells with exit 2.
- A non-TTY suite proves `auth login`, `api` writes, and `--api-key-stdin` fail fast with actionable messages and never prompt.

## Task Commits

Each task was committed atomically:

1. **Task 1: Add CSV, NDJSON, field selection, and terminal-safety rules** - `0ec68c6e2` (feat)
2. **Task 2: Implement `sure doctor` with ordered, non-short-circuiting checks** - `582c7275b` (feat)
3. **Task 3: Implement catalog-driven completion and the non-TTY regression suite** - `f1095a1f3` (feat)
4. **Follow-up: simplify the doctor Date header lookup** - `dac9cb2f5` (refactor)

**Plan metadata:** final `docs(01-05)` commit follows this summary.

## Files Created/Modified

- `cli/lib/sure/output/{csv,ndjson,field_selection}.rb` - Machine formats and the shared field allowlist
- `cli/lib/sure/output/{base,json,table,selector}.rb` - Quiet handling, collection-aware projection, terminal sanitation, four-format selection
- `cli/lib/sure/config/resolver.rb` - `SURE_OUTPUT` accepts `csv` and `ndjson`
- `cli/lib/sure/cli/application.rb` - `--csv`, `--ndjson`, `--fields`, and four-way output exclusivity
- `cli/lib/sure/cli/commands/auth.rb` - The same output options on auth subcommands
- `cli/lib/sure/cli/commands/api.rb` - Rejects `--fields` with `--raw` and all format flags with `--raw`
- `cli/lib/sure/doctor/{check,result,runner}.rb` - Ordered definitions, immutable results, and the non-short-circuiting runner
- `cli/lib/sure/cli/commands/doctor.rb` - Renders `data.checks` and returns the first failure code
- `cli/lib/sure/completion/generator.rb` - Validated bash/zsh/fish templates
- `cli/lib/sure/cli/commands/completion.rb` - Writes only the script to stdout
- `cli/lib/sure/errors/error.rb` - `ExitStatusError` for already-rendered command exits
- `cli/test/**` - Formatter, field, doctor, completion, and non-TTY coverage plus completion snapshots

## Decisions Made

- **Field selection descends into collections:** the first implementation validated JSON fields against envelope keys (`accounts`, `pagination`), which contradicted the cross-format `--fields name,balance` contract. JSON now projects collection items while preserving the envelope.
- **Doctor owns its prerequisites:** each check records `config_ok`, `profile_ok`, `credential_ok`, `reachable`, and `authenticated` explicitly. A profile failure therefore skips the credential check instead of triggering a second, misleading failure.
- **Silent exit status:** doctor must print its checklist and still return a semantic code. `Errors::ExitStatusError` is silent at the Runner boundary, so no duplicate `error:` line or JSON error object is appended.
- **CSV safety split:** formula neutralisation applies only to text beginning with a formula character; numeric strings such as `-12.34` and real numerics are unchanged.
- **Completion descriptions:** fish descriptions are single-quoted and escaped; bash and zsh deliberately omit descriptions, so neither shell evaluates catalog text.

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 1 - Bug] `Column` autogenerated labels called an instance method**
- **Found during:** Task 1 (formatter tests creating columns without an explicit label)
- **Issue:** `Column#initialize` called `humanize(key)`, but `humanize` is a class method. Every existing test supplied a label, so the latent error only surfaced when CSV/table tests used `Column.new(key: "name")`.
- **Fix:** Call `self.class.humanize(key)`.
- **Files modified:** `cli/lib/sure/output/column.rb`
- **Verification:** CSV and table tests create columns without labels and render the expected headings.
- **Committed in:** `0ec68c6e2`

**2. [Rule 1 - Bug] NDJSON emitted all items on one line**
- **Found during:** Task 1 (one-line-per-item test)
- **Issue:** Each item was written with `JSON.generate` but no separator, so two records produced one invalid NDJSON line.
- **Fix:** Write a newline after every item.
- **Files modified:** `cli/lib/sure/output/ndjson.rb`
- **Verification:** Two records produce two lines, each parsed with `JSON.parse`.
- **Committed in:** `0ec68c6e2`

**3. [Rule 2 - Missing Critical] JSON field projection validated envelope keys instead of item keys**
- **Found during:** Task 1 (cross-format field-selection acceptance criteria)
- **Issue:** `sure api GET /api/v1/accounts --fields name,balance` raised `unknown field "name"` because the data is `{accounts: [...], pagination: ...}`.
- **Fix:** Detect a collection array inside the envelope, validate against item keys, and project each item while preserving pagination and meta.
- **Files modified:** `cli/lib/sure/output/json.rb`
- **Verification:** The JSON formatter test projects `name` and `balance` inside `data.accounts` and keeps `data.pagination`.
- **Committed in:** `0ec68c6e2`

**4. [Rule 2 - Missing Critical] CSV could carry terminal control characters**
- **Found during:** Task 1 (no-ANSI acceptance criterion)
- **Issue:** `CSV.generate` quotes correctly but preserves a raw ESC byte in a server-controlled cell, so a piped/cat'ed CSV could emit terminal escapes.
- **Fix:** Strip C0 control characters (except tab/newline/carriage return, which CSV quoting handles) before writing each cell.
- **Files modified:** `cli/lib/sure/output/csv.rb`
- **Verification:** A value containing `\e[31m` produces CSV with no raw escape sequence.
- **Committed in:** `0ec68c6e2`

**5. [Rule 2 - Missing Critical] Doctor produced a secondary failure after a profile error**
- **Found during:** Task 2 (fresh-install checklist test)
- **Issue:** The credential check keyed off `state[:profile]`; when Check 2 skipped, Check 3 ran `context.credential`, resolved the profile again, and failed with a second "no server URL" error.
- **Fix:** Track `profile_ok` explicitly and skip the credential check when the profile did not pass.
- **Files modified:** `cli/lib/sure/doctor/runner.rb`
- **Verification:** With no config file, Check 1 is FAIL and every later check is SKIP.
- **Committed in:** `582c7275b`

**6. [Rule 2 - Missing Critical] Doctor needed a silent exit path**
- **Found during:** Task 2 (command integration)
- **Issue:** Rendering the checklist and then raising a normal error would add a second `error:` line (or a JSON error object on stderr) after a complete diagnosis.
- **Fix:** Add `Errors::ExitStatusError` with `silent?`, and have `CLI::Runner` skip rendering it.
- **Files modified:** `cli/lib/sure/errors/error.rb`, `cli/lib/sure/cli/runner.rb`
- **Verification:** `sure doctor --json` prints one envelope on stdout and nothing on stderr, while returning the first failed check's code.
- **Committed in:** `582c7275b`

---

**Total deviations:** 6 auto-fixed (2 bugs, 4 missing critical)
**Impact on plan:** No architectural change. The fixes are required for the cross-format field contract, terminal safety, and a doctor report that is the complete and only output.

## Issues Encountered

- Implementing `doctor` and `completion` invalidated two earlier tests that used those commands as deliberate "not implemented" probes. `mapper_test` now uses an invalid `sure api` method for structured/human error rendering, and `version_help_test` asserts the real doctor and completion behavior.
- `WebMock`'s Minitest teardown is bypassed when a test class defines its own `teardown`; the new doctor tests call `WebMock.reset!` in `setup` so request-count assertions stay per-test.
- One early full-suite run reported a single failure that did not reproduce across five consecutive runs (281 runs, 1217 assertions, 0 failures each). No failing example was captured.
- `bundle exec rubocop` is still not exposed as a bundle executable in this environment; `bundle exec rake lint` ran 105 files with 0 offenses.

## User Setup Required

None - no external service configuration required. Completion scripts are written to stdout for the user to install in their shell; the repository snapshots are fixtures, not installed files.

## Known Stubs

| File | Stub | Resolved by |
|------|------|-------------|
| `cli/lib/sure/auth/store.rb` | `Auth::NullStore` remains a safe no-op backend | Not on the production path; retained for environment-only clients and tests |

The `doctor` and `completion` placeholders from earlier plans are now implemented.

## Threat Flags

None beyond the plan's threat model. T-05-01 (CSV quoting, formula neutralisation, table control escaping), T-05-02 (doctor reports origin and storage mode, never the key), T-05-03 (completion from validated catalog tokens only), T-05-04 (TLS/clock failures with exact fixes, no automatic downgrade), and T-05-SC (snapshot tests plus `bash -n`, unsupported shells exit 2) are implemented and covered.

## Next Phase Readiness

- Phase 2 read commands can call `Output::Selector#render` with an `Output::Result`; CSV, NDJSON, and `--fields` are free and consistent.
- Commands should keep using `Sure::HTTP::Client`; `sure doctor` proves the same pipeline can inspect status/headers without a second HTTP path.
- Any new catalog entry with `status: implemented` must regenerate the three completion fixtures or the snapshot tests fail.
- Verification evidence:
  - `cd cli && bundle exec rake test` -> 281 runs, 1217 assertions, 0 failures.
  - `cd cli && bundle exec rake lint` -> 105 files, 0 offenses.
  - `cd cli && gem build sure.gemspec` -> `sure-0.1.0.gem` built successfully.
  - Temporary `GEM_HOME` install -> `sure --version`, `sure help`, and `sure doctor --json` all ran; doctor returned 1 on the host's missing config with a Check 1 FAIL.
  - `bash -n test/fixtures/completion/sure.bash` -> accepted.

## Self-Check: PASSED

- Task commits `0ec68c6e2`, `582c7275b`, `f1095a1f3`, and follow-up `dac9cb2f5` exist on `main`.
- All created formatter, doctor, completion, and fixture files exist on disk.
- Full suite, lint, gem build, temporary-GEM_HOME smoke test, and `bash -n` are green.

---
*Phase: 01-foundation-api-key-authentication*
*Completed: 2026-11-01*
