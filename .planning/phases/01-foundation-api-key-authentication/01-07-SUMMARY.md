---
phase: 01-foundation-api-key-authentication
plan: 07
subsystem: auth
tags: [ruby, thor, api-key, tls, io-console, pty, redactor, config-resolver]

# Dependency graph
requires:
  - phase: 01-foundation-api-key-authentication
    provides: "Config::Resolver precedence and TLS validation, keychain-first credential stores, the Redactor, and the auth command group from plans 01-02 and 01-04"
provides:
  - "Hidden-input-only interactive login: IO#getpass/noecho via io/console, with a hard refusal instead of an echoed read"
  - "A 4-byte minimum accepted secret length at prompt, stdin, file, environment, and stored-credential boundaries"
  - "Login profiles built by Config::Resolver, so CA bundles, TLS policy, timeouts, scopes, and store choice match every other command"
  - "TLS and output class options on the auth command group, with --insecure/--ca-bundle conflict rules from any source"
  - "Strict GET /api/v1/usage validation that refuses a 2xx body without api_key.scopes before persisting"
affects: [01-08, 01-09, doctor, api, status, credential-stores]

# Tech tracking
tech-stack:
  added: [io/console, pty]
  patterns:
    - "Login resolves its probe profile through Config::Resolver instead of hand-building Config::Profile"
    - "A secret is never read with echo enabled: no silent fallback to gets"
    - "Accepted secret length equals the redactor floor at every input boundary"

key-files:
  created: []
  modified:
    - cli/lib/sure/auth/login.rb
    - cli/lib/sure/auth/api_key_provider.rb
    - cli/lib/sure/cli/commands/auth.rb
    - cli/lib/sure/config/resolver.rb
    - cli/lib/sure/redactor.rb
    - cli/test/unit/auth/login_test.rb
    - cli/test/unit/auth/api_key_provider_test.rb
    - cli/test/unit/config/resolver_test.rb
    - cli/test/commands/auth_test.rb

key-decisions:
  - "Guarded require of io/console at load time; prompt_secret raises UsageError when neither getpass nor noecho exists"
  - "MIN_BYTES = 4 in both Login and ApiKeyProvider, matching Redactor::MIN_ACTIVE_SECRET_LENGTH, so an accepted credential is always maskable"
  - "Login delegates profile construction to Config::Resolver#resolve(profile_name:) with the resolved server URL passed as the flag value"
  - "Auth group redeclares root output/TLS options without defaults, because the root options are what parse the flags and a group default would overwrite them during Thor's subcommand option merge"
  - "reject_insecure_with_ca! now fires whenever a CA bundle is present, regardless of source (flag, SURE_CA_BUNDLE, profile)"
  - "validate! requires api_key to be a Hash and api_key.scopes to be an Array; an empty array is still a valid read_only profile"

patterns-established:
  - "One TLS precedence: commands build Config::Resolver profiles rather than copying CA/TLS fields"
  - "Secret input boundaries reject values shorter than the redactor floor without interpolating the value"
  - "PTY regression test proves a real terminal does not echo a typed key"

requirements-completed: [AUTH-01, AUTH-09, FOUND-04, SAFE-05]

# Metrics
duration: 5min
completed: 2026-11-01
---

# Phase 1 Plan 7: Hidden login input, TLS-aware login, and strict /usage validation Summary

**Login now reads secrets only through hidden input, resolves CA/TLS settings through Config::Resolver like every other command, and refuses short keys and `/usage` bodies without scopes before anything is persisted**

## Performance

- **Duration:** 5 min
- **Started:** 2026-11-01T17:24:08Z
- **Completed:** 2026-11-01T17:29:14Z
- **Tasks:** 3
- **Files modified:** 9

## Accomplishments

- Interactive `sure auth login` never echoes the key: `io/console` is required at load, `getpass`/`noecho` are preferred, and a terminal without either raises `UsageError` instead of calling `gets`. A real `PTY.spawn` regression test asserts the typed key never appears in terminal output, and an `OpaqueTTY` test asserts `gets` is never called.
- Every accepted credential is now long enough for the redactor to mask: `MIN_BYTES = 4` is enforced on the prompt, stdin, `--api-key-file`, `SURE_API_KEY`, and stored-credential paths, with errors that name the minimum and never echo the value.
- `Login#build_profile` delegates to `Config::Resolver`, so `--ca-bundle`, `SURE_CA_BUNDLE`, `--insecure`, `SURE_INSECURE`, and profile `tls_verify: false` all reach the `/api/v1/usage` probe. Unreadable CA bundles exit 2 before any request, and a CA bundle plus any disabled-verification source exits 2.
- The `auth` group declares `--ca-bundle`, `--insecure`, `--quiet`, `--verbose`, and `--no-color`; `--quiet` suppresses the plaintext-storage warning, and `--quiet --verbose` exits 2 through Thor's exclusive-option check.
- `GET /api/v1/usage` bodies without `api_key.scopes` now fail with an actionable `--server` hint and persist neither `config.yml` nor `credentials.json`; an empty scopes array remains a valid `read_only` profile. `persist!`'s warning argument now means what its name says.

## Task Commits

Each task was committed atomically:

1. **Task 1: Make the hidden prompt truly hidden and enforce a redactable key length** - `bb350b378` (fix)
2. **Task 2: Build the login profile through Config::Resolver and honor auth TLS/output flags** - `2c02aea9c` (fix)
3. **Task 3: Reject unexpected /usage bodies and make the warning flag truthful** - `6c8d231db` (fix)

**Plan metadata:** commit created with this SUMMARY and the STATE/ROADMAP updates (docs: complete plan)

## Files Created/Modified

- `cli/lib/sure/auth/login.rb` - Guarded `io/console` require, hidden-input-only `prompt_secret`, `MIN_BYTES`, resolver-built profile, strict `/usage` validation, truthfully named warning flag
- `cli/lib/sure/auth/api_key_provider.rb` - `MIN_BYTES` enforcement for `SURE_API_KEY` and stored credentials
- `cli/lib/sure/cli/commands/auth.rb` - CA/TLS and output class options plus the quiet/verbose exclusive group
- `cli/lib/sure/config/resolver.rb` - CA/insecure rejection across flag, environment, and profile sources
- `cli/lib/sure/redactor.rb` - Comment documents that every boundary rejects values below the redaction floor
- `cli/test/unit/auth/login_test.rb` - PTY and OpaqueTTY prompt tests, short stdin/file key tests, missing-scopes and empty-scopes tests
- `cli/test/unit/auth/api_key_provider_test.rb` - Three-byte environment and stored-key tests, four-byte maskability test
- `cli/test/unit/config/resolver_test.rb` - Environment CA + `--insecure`, profile CA + `SURE_INSECURE`, profile CA + profile `tls_verify: false`
- `cli/test/commands/auth_test.rb` - Unreadable/readable CA, `--insecure`, profile TLS, CA conflict, `--quiet`, and output-flag command tests

## Decisions Made

- **Hidden input is a hard requirement.** `io/console` is required behind a `LoadError` guard, but if a terminal still has no `getpass`/`noecho`, login refuses and points at `--api-key-file`, `--api-key-stdin`, or `SURE_API_KEY`. There is no echoed fallback.
- **The redaction floor is the acceptance floor.** `MIN_BYTES = 4` is duplicated in `Login` and `ApiKeyProvider` to match `Redactor::MIN_ACTIVE_SECRET_LENGTH`; the alternative (lowering the redactor floor) would risk masking ordinary text.
- **One TLS implementation.** Login no longer builds `Config::Profile` by hand; `Config::Resolver#resolve(profile_name:)` supplies CA bundle, `tls_verify`, timeouts, scopes, `credential_store`, and source tracking.
- **Auth group option defaults defer to the root.** Thor parses root class options before dispatching a subcommand and then merges the subcommand's options over them. Declaring `default: false` for `insecure` (or `default: true` for `color`) on `Commands::Auth` overwrote the flag value, which was reproduced with a probe (`--insecure` arrived as `false`). The auth group therefore declares the options without defaults so the root's parsed values survive.

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 1 - Bug] Auth-group option defaults silently discarded `--insecure`**
- **Found during:** Task 2 (Build the login profile through Config::Resolver and honor auth TLS/output flags)
- **Issue:** The plan specified `class_option :insecure, default: false` and `class_option :color, default: true` on `Commands::Auth`. Thor parses root class options before the subcommand and then does `config[:class_options].merge(subcommand_options)`, so the group's defaults overwrote the root's parsed values. Result: `sure auth login --insecure` reached the resolver as `insecure: false` (exit 0 instead of 2 for a CA conflict; `tls_verify` stayed true).
- **Fix:** Declared `:insecure` and `:color` on the auth group without defaults. The root `Application` keeps `default: false` / `default: true`, and its parsed values now survive the merge. Verified by two new command tests and a manual CLI run.
- **Files modified:** `cli/lib/sure/cli/commands/auth.rb`
- **Verification:** `test_insecure_reaches_the_login_probe_profile_and_warns` and `test_environment_ca_bundle_with_insecure_flag_exits_two` pass; `sure auth login --insecure` with `SURE_CA_BUNDLE` exits 2.
- **Committed in:** `2c02aea9c` (Task 2 commit)

### Plan text vs. declared files

**2. [Rule 2 - Missing Critical] Redactor comment update outside `files_modified`**
- **Found during:** Task 1 (Make the hidden prompt truly hidden and enforce a redactable key length)
- **Issue:** Task 1's `<action>` requires updating the `Redactor::MIN_ACTIVE_SECRET_LENGTH` comment, but `cli/lib/sure/redactor.rb` is absent from the plan's `files_modified` list.
- **Fix:** Applied the comment-only edit (no behavior change) so the redactor documents that every boundary rejects shorter values.
- **Files modified:** `cli/lib/sure/redactor.rb`
- **Verification:** `bundle exec rake test` and `bundle exec rake lint` both green.
- **Committed in:** `bb350b378` (Task 1 commit)

---

**Total deviations:** 2 auto-fixed (1 bug, 1 missing critical documentation)
**Impact on plan:** Both were necessary for the plan's stated behavior. The option-default fix was required for `--insecure` to work at all; the comment edit keeps the redaction contract documented at its source. No scope creep.

## Issues Encountered

- **`bundle exec rubocop` is broken in this environment.** The executable resolves inside the bundle (`Gem.bin_path` returns the gem's `exe/rubocop`), but `bundle exec rubocop` reports `bundler: command not found: rubocop` and `bundle exec ruby -S rubocop` looks for a nonexistent `/usr/local/bin/ruby`-relative script. RuboCop was run through the repository's own task instead: `bundle exec rake lint` (`RuboCop::RakeTask`) → 106 files, 0 offenses. This is an environment issue, not a code issue.
- **The plan's per-task `<automated>` command passes multiple files to `ruby -Itest`.** Ruby executes only the first script argument, so each file was run separately; all four are green individually (see verification below).
- **PTY test portability.** The test skips when `PTY` cannot be loaded and waits up to 10 s for the prompt before typing, so it does not race the tty echo state. It passes in ~0.6 s on this Linux runner.

## User Setup Required

None - no external service configuration required.

## Verification Results

| Check | Command | Result |
| --- | --- | --- |
| Full CLI suite | `cd cli && bundle exec rake test` | 320 runs, 1400 assertions, 0 failures, 0 errors, 0 skips |
| Lint | `cd cli && bundle exec rake lint` | 106 files inspected, no offenses (used because `bundle exec rubocop` cannot launch here) |
| Gem build | `cd cli && gem build sure.gemspec` | Successfully built `sure-0.1.0.gem` |
| Login tests | `cd cli && bundle exec ruby -Itest test/unit/auth/login_test.rb` | 17 runs, 104 assertions, 0 failures |
| Provider tests | `cd cli && bundle exec ruby -Itest test/unit/auth/api_key_provider_test.rb` | 16 runs, 74 assertions, 0 failures |
| Resolver tests | `cd cli && bundle exec ruby -Itest test/unit/config/resolver_test.rb` | 19 runs, 91 assertions, 0 failures |
| Auth command tests | `cd cli && bundle exec ruby -Itest test/commands/auth_test.rb` | 16 runs, 100 assertions, 0 failures |
| Manual: unreadable CA | `sure auth login --server … --api-key-stdin --ca-bundle /nonexistent/ca.pem` | exit 2, `CA bundle /nonexistent/ca.pem is not readable`, no config written |
| Manual: env CA + `--insecure` | `SURE_CA_BUNDLE=… sure auth login … --insecure` | exit 2, `--ca-bundle and --insecure cannot be used together` |
| Manual: output flags | `sure auth status --quiet --verbose --json` | exit 2, `Found exclusive options '--quiet', '--verbose'` |
| Manual: short key | `printf 'zq7' \| sure auth login --api-key-stdin …` | exit 2, `API key must be at least 4 bytes`, no files written |
| Manual: hidden prompt | `PTY.spawn` test in `login_test.rb` | typed key absent from terminal output |

## Known Stubs

None.

## Threat Flags

None - no new network endpoints, auth paths, or trust boundaries beyond the mitigations listed in the plan's threat model (T-07-01..T-07-04).

## Next Phase Readiness

- Login now matches every other command's TLS and output contract, so private-CA self-hosted instances can authenticate.
- The remaining phase gaps (credential-key path prefix, zsh completion) are the subjects of plans 01-08 and 01-09.
- Human verification from `01-VERIFICATION.md` (macOS Keychain, Linux Secret Service, live Sure server) is still outstanding and unaffected by this plan.

---
*Phase: 01-foundation-api-key-authentication*
*Completed: 2026-11-01*

## Self-Check: PASSED
