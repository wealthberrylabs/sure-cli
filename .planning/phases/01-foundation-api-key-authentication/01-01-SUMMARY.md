---
phase: 01-foundation-api-key-authentication
plan: 01
subsystem: cli
tags: [ruby, thor, gem, catalog, exit-codes, walking-skeleton]

# Dependency graph
requires: []
provides:
  - "Installable sure gem with exe/sure and a temp-GEM_HOME install path"
  - "Thor application surface for version, help, auth, api, doctor, completion"
  - "Injectable CLI runtime and a single Runner error/exit-code boundary"
  - "Machine-readable operations catalog with a Thor-aware validator"
affects: [01-02, 01-03, 01-04, 01-05, phase-2, phase-7]

# Tech tracking
tech-stack:
  added: [thor 1.5, faraday 2.14, faraday-retry 2.3, terminal-table 4.0, csv 3.3]
  patterns:
    - "Process-boundary error mapping: commands raise, Runner renders one stderr line"
    - "Injected runtime (stdin/stdout/stderr/env/cwd/clock) for every command"
    - "Catalog-driven help/examples with a validator tied to Thor's command tree"
    - "Immutable Data value objects for catalog entries, arguments, and options"

key-files:
  created:
    - cli/sure.gemspec
    - cli/exe/sure
    - cli/lib/sure.rb
    - cli/lib/sure/cli/runner.rb
    - cli/lib/sure/cli/runtime.rb
    - cli/lib/sure/cli/application.rb
    - cli/lib/sure/catalog.rb
    - cli/lib/sure/catalog/validator.rb
    - cli/config/operations.yml
    - cli/test/commands/version_help_test.rb
    - cli/test/unit/catalog_test.rb
  modified:
    - .planning/phases/01-foundation-api-key-authentication/01-SKELETON.md

key-decisions:
  - "Catalog is the single source for help, examples, and command validation; planned entries stay invisible until implemented"
  - "Hide Thor's injected tree command so the product surface matches the catalog"
  - "Patch-level dependency drift accepted within the plan's pessimistic (~>) root-locked constraints"

patterns-established:
  - "Semantic exit codes 0-9 live in Sure::Errors::ExitCodes and are chosen only by Runner"
  - "Every command class is a Thor task; service objects carry behavior and raise Sure::Errors"
  - "Catalog entries carry path/summary/description/risk/status/aliases/arguments/options/examples/api/version_added"

requirements-completed: [FOUND-01, FOUND-02]

# Metrics
duration: 9 min
completed: 2026-11-01
---

# Phase 1 Plan 01: Walking Skeleton Summary

**Installable `sure` gem with a Thor command surface, injected runtime, semantic exit-code boundary, and a validated operation catalog — built and smoke-tested in a clean GEM_HOME without loading Rails**

## Performance

- **Duration:** 9 min
- **Started:** 2026-11-01T01:02:24Z
- **Completed:** 2026-11-01T01:12:32Z
- **Tasks:** 4
- **Files modified:** 36

## Accomplishments

- Standalone `cli/` gem builds with an explicit file allowlist (`exe/`, `lib/`, `config/operations.yml`, README, LICENSE); no test fixtures or secrets ship in the package.
- `sure --version` prints exactly `sure 0.1.0` from both the source tree and a temporary `GEM_HOME` install, with no Rails/ActiveSupport constants loaded.
- `sure help` and `sure help auth login` render catalog-backed summaries, options, and examples through an injected `Thor::Shell`, including `--api-key-stdin` and never a bare `--api-key`.
- Unknown commands/options exit 2 with one stderr line and no Ruby backtrace; the forbidden `--api-key=...` token is rejected before parsing without echoing its value.
- The full D-13 error taxonomy (exit codes 0-9 plus interrupted 130) exists before any HTTP command.
- `config/operations.yml` records implemented entries and planned accounts/transactions/reporting entries; the validator keeps implemented entries one-to-one with Thor's non-hidden leaves and enforces D-04 (`delete` only, no `rm` aliases).

## Task Commits

Each task was committed atomically:

1. **Task 0: Confirm the Ruby 3.4.9 toolchain** - `3117317e6` (chore)
2. **Task 1: Scaffold the standalone gem, executable, and build tasks** - `1bf5a6dc5` (feat)
3. **Task 2: Thor application, injectable runtime, and exit-code boundary** - `c658fb8f9` (feat)
4. **Task 3: Operation catalog, validator, and skeleton contract** - `d868ff696` (feat)
5. **Verification: RuboCop omakase spacing** - `142ae586f` (style)

**Plan metadata:** final `docs(01-01)` commit for this plan

## Files Created/Modified

- `cli/sure.gemspec` - Gem metadata, runtime/dev dependencies, explicit file allowlist
- `cli/Gemfile`, `cli/Gemfile.lock` - Isolated bundle pinned to the root-locked toolchain
- `cli/Rakefile`, `cli/.rubocop.yml` - `test`/`lint`/`build` tasks and omakase style
- `cli/exe/sure`, `cli/bin/sure` - Installed entry point and development wrapper
- `cli/lib/sure.rb` - `Sure.run` public entry point returning a semantic exit code
- `cli/lib/sure/version.rb` - `Sure::VERSION = "0.1.0"`
- `cli/lib/sure/cli/{application,base,runner,runtime,shell,context}.rb` - Dispatch, injection, and process boundary
- `cli/lib/sure/cli/commands/{auth,api,doctor,completion}.rb` - Command surface with staged placeholders
- `cli/lib/sure/errors/{error,exit_codes}.rb` - D-13 taxonomy and constants
- `cli/lib/sure/catalog{,/operation,/loader,/validator}.rb` - Catalog loading, value objects, and validation
- `cli/config/operations.yml` - Implemented and planned command metadata
- `cli/test/**` - StringIO-driven command tests, catalog/validator tests, malformed-root fixture
- `.planning/phases/01-foundation-api-key-authentication/01-SKELETON.md` - Directory layout updated to include `catalog`

## Decisions Made

- Catalog drives help and examples; planned entries are data-only and never mounted, so Phase 1 help cannot advertise unimplemented commands.
- Thor's injected `tree` task is hidden: it is an implementation aid, not a product command, and the validator would otherwise require a catalog entry for it.
- `sure api` is catalogued as `risk: raw_write`; the D-04 destructive rule applies only to `risk: destructive` entries.
- The plan's pessimistic `~>` constraints were kept verbatim; they resolved faraday 2.14.4 and rubocop 1.76.2 (root lock: 2.14.3 / 1.76.1). No new gem families were introduced.

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 3 - Blocking] Thor 1.5 crashes on unknown commands when class-exclusive options exist**
- **Found during:** Task 2 (application/runtime implementation)
- **Issue:** `Thor::DynamicCommand` builds an empty `options_relation`, so `Thor::Base#initialize` raised `NoMethodError` on `nil << name` before it could report an unknown command.
- **Fix:** Added an `Application::UnknownCommand < Thor::DynamicCommand` subclass that supplies empty `exclusive_option_names`/`at_least_one_option_names` keys, and overrode `dynamic_command_class`.
- **Files modified:** `cli/lib/sure/cli/application.rb`
- **Verification:** `sure nonexistent` now exits 2 with `Could not find command "nonexistent".`
- **Committed in:** `c658fb8f9`

**2. [Rule 2 - Missing Critical] Hide Thor's inherited `tree` command**
- **Found during:** Task 3 (validator/tree comparison)
- **Issue:** Thor injects `tree` into every application/subcommand; it appeared in `sure help` and would fail the "non-hidden leaf needs a catalog entry" rule.
- **Fix:** Registered `tree` as a hidden command in `Sure::CLI::Base` so it is absent from help and skipped by the validator while remaining available for debugging.
- **Files modified:** `cli/lib/sure/cli/base.rb`
- **Verification:** `Application.all_commands["tree"].hidden? == true`; `sure help` omits it; validator passes.
- **Committed in:** `d868ff696`

**3. [Rule 1 - Bug] Corrected `require_relative` depths during Task 2**
- **Found during:** Task 2 (first test run)
- **Issue:** `errors/error.rb`, `catalog.rb`, and `catalog/loader.rb` resolved sibling paths one directory too high and raised `LoadError`.
- **Fix:** Adjusted to `require_relative "exit_codes"`, `"errors"`, and `"../errors"` respectively.
- **Files modified:** `cli/lib/sure/errors/error.rb`, `cli/lib/sure/catalog.rb`, `cli/lib/sure/catalog/loader.rb`
- **Verification:** `require "sure"` and the full suite load cleanly.
- **Committed in:** `c658fb8f9`

---

**Total deviations:** 3 auto-fixed (1 bug, 1 missing critical, 1 blocking)
**Impact on plan:** All three were required for correct dispatch, a clean help surface, and a loadable gem. No scope creep; no architectural changes.

## Issues Encountered

- `bundle exec rubocop` could not find the executable because mise places gem wrappers in the Ruby install's `bin`, which Bundler does not add to `PATH`. Lint ran clean via `bundle exec rake lint` and via `PATH="$(ruby -e 'print Gem.bindir'):$PATH" bundle exec rubocop` (27 files, 0 offenses). No repo change was needed.
- Gem resolution moved faraday to 2.14.4 and rubocop to 1.76.2 because the plan mandates `~>` constraints anchored at the root-locked versions. Both remain within the same minor line and no new gem families were added.
- The SDK `state.record-metric` row appended outside the Performance Metrics table; STATE.md was normalized by hand into a dedicated plan-metrics table.

## Known Stubs

Intentional, plan-scoped placeholders — each raises `Sure::Errors::UsageError` with `not implemented until its plan lands` and is covered by a test:

| File | Stub | Resolved by |
|------|------|-------------|
| `cli/lib/sure/cli/commands/auth.rb` | `login`, `logout`, `status` | Plan 01-04 |
| `cli/lib/sure/cli/commands/api.rb` | `call` | Plan 01-03 / 01-05 |
| `cli/lib/sure/cli/commands/doctor.rb` | `call` | Plan 01-05 |
| `cli/lib/sure/cli/commands/completion.rb` | `call` | Plan 01-05 |
| `cli/lib/sure/cli/context.rb` | `Context.current` | Plan 01-02 |

These do not block the plan goal: Phase 1's skeleton proves packaging, dispatch, catalog-backed help, and exit codes before behavior lands.

## Threat Flags

None. The implementation adds no network surface, no credential handling, and no schema changes; the gemspec allowlist and catalog loader (`YAML.safe_load_file`, `aliases: false`) implement T-01-01 and T-01-03.

## Next Phase Readiness

- Plan 01-02 can build `Config::Paths/Loader/Resolver` behind `Sure::CLI::Base#context`; the placeholder already fails with exit 2.
- Plan 01-03 can add the Faraday pipeline and extend `Sure::Errors` without touching dispatch.
- Catalog validation is wired and will catch any command added without metadata.
- Verification evidence: `bundle exec rake test` → 24 runs, 127 assertions, 0 failures; `bundle exec rake lint` → 27 files, 0 offenses; `gem build` → `sure-0.1.0.gem`; temp `GEM_HOME` install → `sure 0.1.0`, `sure help` exit 0.

## Self-Check: PASSED

- Task commits `3117317e6`, `1bf5a6dc5`, `c658fb8f9`, `d868ff696`, `142ae586f` exist on `main`.
- `cli/sure.gemspec`, `cli/exe/sure`, `cli/config/operations.yml`, `cli/lib/sure/catalog/validator.rb`, and both test files exist on disk.
- `cli/config/operations.yml` ships in the built gem; no `test/` path is packaged.
- Full suite and lint are green; temp-GEM_HOME install prints `sure 0.1.0` and `sure help` exits 0.

---
*Phase: 01-foundation-api-key-authentication*
*Completed: 2026-11-01*
