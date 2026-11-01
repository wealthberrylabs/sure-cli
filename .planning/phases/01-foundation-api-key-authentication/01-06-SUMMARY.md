---
phase: 01-foundation-api-key-authentication
plan: 06
subsystem: cli
tags: [thor, argv, global-options, gap-closure, cr-02]

# Dependency graph
requires:
  - phase: 01-foundation-api-key-authentication
    provides: Runner process boundary, Thor Application class options, api command pipeline
provides:
  - Deterministic normalization of global/class options placed before the command
  - Loud exit 2 for unknown or incomplete leading options instead of a silent help screen
  - Regression coverage for leading, trailing, inline, and invalid option placement
affects: [01-07, 01-08, 01-09, phase-2-read-report]

# Tech tracking
tech-stack:
  added: []
  patterns:
    - "Normalize argv once at the process boundary before Thor dispatch"
    - "Allowlisted option hoisting; unknown options fail loudly"

key-files:
  created:
    - cli/test/unit/cli/runner_test.rb
  modified:
    - cli/lib/sure/cli/runner.rb
    - cli/test/commands/version_help_test.rb
    - cli/test/commands/api_test.rb

key-decisions:
  - "Only the contiguous leading run of allowlisted global options is moved; a bare -- disables normalization"
  - "Unknown or value-less leading options raise UsageError and exit 2 instead of falling through to help"
  - "A terminal option keeps its first-token position; when it follows other leading options it is promoted ahead of them so --json --version still resolves"

patterns-established:
  - "argv normalization lives in Runner, not in Thor subclasses or individual commands"

requirements-completed: [FOUND-03, FOUND-06, FOUND-09]

# Metrics
duration: 3min
completed: 2026-11-01
---

# Phase 1 Plan 06: Leading Global Option Normalization Summary

**Global options now work on either side of the command name: `sure --profile staging api GET /api/v1/accounts --json` exits 0 with piped JSON, and `sure --json doctor` propagates doctor's exit 1 instead of printing help and exiting 0.**

## Performance

- **Duration:** 3 min
- **Started:** 2026-11-01T17:19:49Z
- **Completed:** 2026-11-01T17:22:00Z
- **Tasks:** 2
- **Files modified:** 4

## Accomplishments
- `Sure::CLI::Runner#normalize_global_options` hoists the leading run of documented class options behind the command and its arguments before Thor resolves the command name.
- Unknown (`--jsn`, `--bogus`) and value-less (`--profile`) leading options now exit 2 with an actionable message instead of degrading to a help screen with exit 0.
- Terminal options (`--version`, `-v`, `--help`, `-h`) and everything after a bare `--` keep their existing behavior and order.
- End-to-end coverage proves the literal ROADMAP Success Criterion 3 command reaches a real local server with exactly one `GET /api/v1/accounts`, and that `sure --json doctor` returns doctor's real exit code and JSON checklist.

## Task Commits

Each task was committed atomically:

1. **Task 1: Normalize leading global options before Thor dispatch** - `76e4aef77` (fix)
2. **Task 2: Prove the ROADMAP command and leading-flag behavior end to end** - `8bbf5e6cc` (test)

**Plan metadata:** `docs(01-06): complete leading global option normalization plan` (this commit)

## Files Created/Modified
- `cli/lib/sure/cli/runner.rb` - Added `GLOBAL_VALUE_OPTIONS`, `GLOBAL_BOOLEAN_OPTIONS`, `TERMINAL_OPTIONS`, and private `normalize_global_options`; dispatched argv is now normalized after the forbidden `--api-key` check and before `Application.start`.
- `cli/test/unit/cli/runner_test.rb` - Direct normalization coverage: single/multiple leading options, `--opt=value`, boolean and `--no-*` forms, terminal options, bare `--`, unknown and value-less options (no value echoed).
- `cli/test/commands/version_help_test.rb` - `sure --json doctor` exits 1 with `data.checks`, `sure --json --version` prints `sure 0.1.0`, `sure --jsn doctor` exits 2 with no help body.
- `cli/test/commands/api_test.rb` - `LocalHttpServer` proof that `--profile staging` and `--server URL` work before the command with exactly one request, and match the trailing-option form.

## Decisions Made
- **Allowlist, not heuristics.** Only the twelve documented class options are moved; anything else starting with `-` raises `UsageError`, satisfying T-06-02 (a mistyped flag must not look like success).
- **Rejected options are named by option only.** The error for an unknown token uses the part before `=`, so `--bogus=secret` never echoes the value (T-06-03). The existing `reject_forbidden_api_key` still runs on the original argv.
- **Terminal options stay authoritative.** A first-token terminal returns argv untouched; a terminal appearing later in the leading run is promoted to the front with the already-collected options beside it, which is what makes `sure --json --version` print the version.

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 3 - Blocking] Created the runner unit test during Task 1 to satisfy Task 1's declared verify command**
- **Found during:** Task 1 (Normalize leading global options)
- **Issue:** Task 1's verify command runs `test/unit/cli/runner_test.rb`, but that file was scheduled for creation in Task 2, so the declared verification could not pass at Task 1's boundary.
- **Fix:** Wrote the `normalize_global_options` unit coverage in Task 1 and committed it with the implementation; Task 2 then added the command-level end-to-end assertions as planned.
- **Files modified:** `cli/test/unit/cli/runner_test.rb`
- **Verification:** `bundle exec ruby -Itest test/unit/cli/runner_test.rb` — 15 runs, 0 failures.
- **Committed in:** `76e4aef77`

### Plan Wording Adjustments

**2. Terminal-option handling narrowed to keep `sure --json --version` working**
- **Found during:** Task 1, checked against Task 2's acceptance criteria
- **Plan text:** "if any terminal option appears, return the original argv unchanged."
- **Why adjusted:** Returning argv unchanged for `["--json", "--version"]` keeps `--json` as the leading token, which Thor rejects (`Unknown switches "--version"`, exit 2) — contradicting Task 2's requirement that `sure --json --version` still prints `sure 0.1.0`.
- **Implementation:** A terminal option as the first token returns argv unchanged (all Task 1 acceptance cases, `assert_same` in tests); a terminal option later in the leading run is promoted to the first token with collected options beside it.
- **Verification:** `run_cli("--json", "--version")` → exit 0, `sure 0.1.0`; `run_cli("--version", "--bogus")` still exits 2.

---

**Total deviations:** 1 auto-fixed (1 blocking), 1 documented wording adjustment
**Impact on plan:** No scope creep; the adjustment is required to satisfy the plan's own Task 2 acceptance criteria.

## Issues Encountered

- **`bundle exec rubocop` is unavailable in this environment.** RuboCop 1.76.2 is installed outside the bundle (`bundle exec rubocop` → "command not found"), so the plan's lint command was run through the installed 1.76.2 binary at `/home/randy/.local/share/mise/installs/ruby/3.4.9/bin/rubocop`: 106 files, no offenses. Code was not modified to work around this.
- **Multi-file Ruby verify command only runs the first file.** `ruby -Itest a.rb b.rb c.rb` treats the extra paths as ARGV, so only `a.rb` executed. Each file was run individually instead; all green. Recommend `bundle exec rake test TEST="..."` or separate invocations in future plans.

## Verification Results

| Command | Result |
|---------|--------|
| `cd cli && bundle exec rake test` | 301 runs, 1281 assertions, 0 failures |
| `cd cli && rubocop` (installed 1.76.2) | 106 files, no offenses |
| `cd cli && gem build sure.gemspec` | `sure-0.1.0.gem` built successfully |
| `sure --json doctor; echo $?` | JSON checklist on stdout, exit 1 with no config (was help + exit 0) |
| `sure --profile staging api GET /api/v1/accounts --json` against `LocalHttpServer` | exit 0, one `GET /api/v1/accounts`, parseable JSON |
| `sure --jsn doctor` | exit 2, stderr names `--jsn`, stdout empty |

## User Setup Required

None - no external service configuration required.

## Next Phase Readiness

- Verification gap 2 and review finding CR-02 are closed; the phase headline command in ROADMAP Success Criterion 3 is now executable and regression-tested.
- Gap-closure plans 01-07 (login/TLS/strict `/usage`), 01-08 (path-scoped credentials), and 01-09 (zsh completion) are untouched by this change and remain independent.

---
*Phase: 01-foundation-api-key-authentication*
*Completed: 2026-11-01*

## Self-Check: PASSED

- Files: all 4 plan files plus this summary exist on disk.
- Commits: `76e4aef77` (Task 1) and `8bbf5e6cc` (Task 2) exist in history.
