---
phase: 01-foundation-api-key-authentication
plan: 04
subsystem: auth
tags: [ruby, keychain, credential-store, api-key, login, logout, scope-preflight, openapi, minitest, rswag]

# Dependency graph
requires:
  - phase: 01-foundation-api-key-authentication
    provides: "Immutable credentials, CredentialKey identity, the Store interface, and environment-first key precedence from Plan 01-02"
  - phase: 01-foundation-api-key-authentication
    provides: "The shared Faraday pipeline, redaction, semantic exit codes, output contract, and sure api from Plan 01-03"
provides:
  - "Keychain-first credential storage with macOS security and Linux secret-tool helpers plus an atomic 0600 file fallback"
  - "StoreFactory read/write/delete fallback transitions with one-time plaintext warnings"
  - "sure auth login with file/stdin/environment/hidden-prompt precedence, usage validation before persistence, and config rollback"
  - "sure auth status with a non-secret /usage projection and sure auth logout with local deletion plus revocation guidance"
  - "Write-scope preflight that stops read-only keys with exit 3 before the write request"
  - "An additive identity-only user object on GET /api/v1/usage, covered by Minitest and OpenAPI"
affects: [01-05, phase-2, phase-3, phase-5, phase-7]

# Tech tracking
tech-stack:
  added: []
  patterns:
    - "Credential backends implement Auth::Store; StoreFactory owns selection and every fallback transition"
    - "Secrets reach helper processes only through stdin, with a PATH-resolved executable and an explicit environment allowlist"
    - "Login proves the key with GET /api/v1/usage before any write and deletes the credential if config persistence fails"
    - "Cached profile scopes are trusted only for stored credentials; environment keys re-check /usage on every write"
    - "Auth commands render Output::Result so piped output is always valid JSON and never contains the key"

key-files:
  created:
    - cli/lib/sure/auth/command_runner.rb
    - cli/lib/sure/auth/file_store.rb
    - cli/lib/sure/auth/mac_keychain_store.rb
    - cli/lib/sure/auth/secret_service_store.rb
    - cli/lib/sure/auth/store_factory.rb
    - cli/lib/sure/auth/login.rb
    - cli/lib/sure/auth/logout.rb
    - cli/lib/sure/auth/status.rb
    - cli/lib/sure/auth/scope_preflight.rb
    - cli/test/unit/auth/credential_key_test.rb
    - cli/test/unit/auth/command_runner_test.rb
    - cli/test/unit/auth/file_store_test.rb
    - cli/test/unit/auth/keychain_store_test.rb
    - cli/test/unit/auth/store_factory_test.rb
    - cli/test/unit/auth/login_test.rb
    - cli/test/unit/auth/scope_preflight_test.rb
    - cli/test/commands/auth_test.rb
    - cli/test/support/fake_store.rb
    - cli/test/support/fake_command_runner.rb
    - cli/test/support/fake_keychain.rb
    - spec/requests/api/v1/usage_spec.rb
  modified:
    - cli/lib/sure.rb
    - cli/lib/sure/auth/store.rb
    - cli/lib/sure/cli/context.rb
    - cli/lib/sure/cli/commands/auth.rb
    - cli/lib/sure/cli/commands/api.rb
    - cli/test/support/fake_tty.rb
    - cli/test/commands/api_test.rb
    - cli/test/fixtures/api/usage.json
    - app/controllers/api/v1/usage_controller.rb
    - test/controllers/api/v1/usage_controller_test.rb
    - spec/swagger_helper.rb
    - docs/api/openapi.yaml

key-decisions:
  - "StoreFactory subclasses Auth::Store and owns selection plus fallback, so Context and the provider stay unaware of keychain versus file"
  - "Login persists read_only derived from the validated scopes, letting a read-only key fail preflight without a network round trip"
  - "ScopePreflight runs after write confirmation but before the write request, preserving the non-TTY/abort behavior while still blocking read-only keys"
  - "The additive /usage user object is identity-only (email, first_name, last_name) with no id, matching the minimal-payload decision"
  - "Login sets default_profile when the config has none so a first login is immediately usable by later commands"

patterns-established:
  - "FileStore: flock on credentials.lock, re-read, merge, temp write 0600, fsync, rename, directory fsync, unlock in ensure"
  - "CommandRunner: absolute PATH resolution, explicit allowlisted environment, no shell, secret on stdin only"
  - "StoreFactory transition table: keychain write failure -> file + warning; keychain read failure -> existing file copy or actionable exit 3; logout removes configured store and file copy"
  - "Auth status projects only non-secret fields and emits user: null plus a warning rather than fabricating identity"

requirements-completed: [AUTH-01, AUTH-02, AUTH-03, SAFE-06]

# Metrics
duration: 15 min
completed: 2026-11-01
---

# Phase 1 Plan 04: Credential Storage, Auth Commands, and Usage Identity Summary

**A keychain-first credential store with an atomic 0600 file fallback, login/status/logout that validate before persisting and never echo the key, a write-scope preflight that stops read-only keys before the request, and an additive identity-only user object on GET /api/v1/usage**

## Performance

- **Duration:** 15 min
- **Started:** 2026-11-01T01:35:00Z
- **Completed:** 2026-11-01T01:50:03Z
- **Tasks:** 3
- **Files modified:** 33

## Accomplishments

- `Auth::FileStore` writes a schema_version 1 JSON document at 0600 inside a 0700 directory, serializes writes with `flock`, merges profiles, renames atomically, fsyncs the file and directory, and refuses symlinked, foreign-owned, or group/world-readable files with a `chmod 600` fix.
- `Auth::CommandRunner` resolves helpers from PATH, passes only `PATH`, `HOME`, `USER`, `LOGNAME`, `TMPDIR`, and `DBUS_SESSION_BUS_ADDRESS`, times out after 2 seconds, and never places the secret in argv or the child environment.
- `Auth::MacKeychainStore` and `Auth::SecretServiceStore` send the secret on stdin, strip exactly one trailing newline, verify the macOS read-back, and use the documented service/profile/origin attributes.
- `Auth::StoreFactory` implements the fallback transition table and warns once for plaintext storage; `Auth::FileStore` locks, merges, and removes only the target entry.
- `sure auth login` accepts `--api-key-file`, `--api-key-stdin`, `SURE_API_KEY`, or a hidden prompt; validates against `GET /api/v1/usage`; stores the credential; persists `server_url`, `scopes`, `credential_store`, `read_only`, and the warning marker; and rolls the credential back if the config write fails.
- `sure auth status --json` reports profile, server, user, key name/scopes/timestamps, `authentication_method`, `credential_source`, and rate-limit tier, and contains no secret.
- `sure auth logout` deletes the credential, is idempotent, warns when `SURE_API_KEY` is still set, and prints the Settings → API Keys revocation guidance.
- `sure api` write methods call `Auth::ScopePreflight`; a read-only profile exits 3 before any write request, and environment keys fetch scopes from `/usage` every time without persisting them.
- `GET /api/v1/usage` now returns `user.email`, `user.first_name`, and `user.last_name`, with no `id` and no secret fields; Minitest and generated OpenAPI cover it.

## Task Commits

Each task was committed atomically:

1. **Task 1: Implement keychain stores, the atomic file fallback, and store selection** - `1db7bb379` (feat)
2. **Task 2: Implement auth login/status/logout and write-scope preflight** - `06ad311b3` (feat)
3. **Task 3: Add the authenticated user object to GET /api/v1/usage with tests and OpenAPI docs** - `19bf39819` (feat)

**Plan metadata:** `docs(01-04)` commit follows this summary.

## Files Created/Modified

- `cli/lib/sure/auth/command_runner.rb` - PATH-resolved helper execution with a scrubbed environment and timeout
- `cli/lib/sure/auth/file_store.rb` - Private JSON credential store with flock, merge, atomic rename, and safety checks
- `cli/lib/sure/auth/mac_keychain_store.rb` - macOS `security` backend with stdin writes and read-back verification
- `cli/lib/sure/auth/secret_service_store.rb` - Linux `secret-tool` backend gated on a session bus
- `cli/lib/sure/auth/store_factory.rb` - Keychain-first selection and the fallback transition table
- `cli/lib/sure/auth/login.rb` - Input precedence, validation-before-store, fallback warning, and rollback
- `cli/lib/sure/auth/logout.rb` - Local deletion, idempotency, and revocation guidance
- `cli/lib/sure/auth/status.rb` - Non-secret `/usage` projection
- `cli/lib/sure/auth/scope_preflight.rb` - The single write guard, including environment-key re-checks
- `cli/lib/sure/cli/commands/auth.rb` - Thor subcommands rendering `Output::Result`
- `cli/lib/sure/cli/commands/api.rb` - Preflight call before a write request
- `cli/lib/sure/cli/context.rb` - Context now builds `StoreFactory` instead of `NullStore`
- `cli/test/**` - Store, runner, factory, login, preflight, and auth-command tests plus fakes
- `app/controllers/api/v1/usage_controller.rb` - Additive identity-only user object
- `spec/requests/api/v1/usage_spec.rb` - Documentation-only `GET /api/v1/usage` spec
- `spec/swagger_helper.rb` - Reusable `Usage` schema
- `docs/api/openapi.yaml` - Regenerated `/api/v1/usage` documentation

## Decisions Made

- `StoreFactory` is itself an `Auth::Store`, so `Context` and `Auth::ApiKeyProvider` never branch on storage mode.
- Login records `read_only` from the validated scopes. This makes the read-only preflight fail closed without a `/usage` round trip and still matches the server's scope model.
- The write preflight runs after write confirmation. That preserves existing non-TTY and abort behavior (no prompt-skipping) while still preventing the write request.
- The additive `/usage` user payload is identity-only. No `id`, family, or account fields are exposed; Minitest asserts the exact three keys.
- `default_profile` is set on first login when absent, so the just-created profile is immediately discoverable.

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 2 - Missing Critical] Login persists `read_only` derived from scopes**
- **Found during:** Task 2 (login persistence and SAFE-06 verification)
- **Issue:** The plan's config write listed `server_url`, `scopes`, and `credential_store` only. Without a persisted `read_only`, a read-only key would need a `/usage` request during every write preflight, contradicting the "zero requests" acceptance criterion.
- **Fix:** Login derives `read_only` from the validated scopes and writes it with the profile.
- **Files modified:** `cli/lib/sure/auth/login.rb`
- **Verification:** The auth command test logs in with a read-only key, runs `sure api POST`, and observes exit 3 with the server request count unchanged.
- **Committed in:** `06ad311b3`

**2. [Rule 2 - Missing Critical] Environment-key write tests now stub `/usage`**
- **Found during:** Task 2 (full-suite regression)
- **Issue:** Existing `sure api` write tests used `SURE_API_KEY`; the mandatory environment-key re-check added a `/usage` request, so the write tests failed under WebMock.
- **Fix:** Added `/usage` stubs returning `read_write` to the successful write tests and added a dedicated read-only-scope test.
- **Files modified:** `cli/test/commands/api_test.rb`
- **Verification:** All 17 `sure api` tests pass; the read-only case exits 3 and never posts.
- **Committed in:** `06ad311b3`

**3. [Rule 2 - Missing Critical] StoreFactory skips an unavailable keychain on delete**
- **Found during:** Task 2 (logout idempotency)
- **Issue:** Logout tried to invoke a missing helper even when the factory had already selected the file backend.
- **Fix:** `delete_from_keychain` returns early unless the keychain reports itself available; it still deletes a file copy.
- **Files modified:** `cli/lib/sure/auth/store_factory.rb`
- **Verification:** Logout exits 0 twice on a host with no keychain; the first removes the file and the second reports `deleted: false`.
- **Committed in:** `06ad311b3`

---

**Total deviations:** 3 auto-fixed (3 missing critical)
**Impact on plan:** No architectural change. The additions are required to satisfy the write-preflight guarantee and to keep logout safe on hosts without a keychain.

## Issues Encountered

- `bundle exec rubocop` is not exposed as a bundle executable in this environment, even though RuboCop 1.76.2 is locked and installed. The equivalent `bundle exec rake lint` task ran 92 files with 0 offenses, and `bin/rubocop` on the changed Rails files reported 0 offenses.
- The first full-suite run after adding preflight exposed the expected env-key `/usage` calls as unstubbed WebMock requests; the test updates above resolved them.
- The Linux host has no libsecret or macOS Security helper. Keychain behavior is covered with fake runners and stores; real keychain checks remain the manual `user_setup` items in the plan.

## User Setup Required

Manual keychain verification is still advisable on real desktops (the plan's `user_setup` items):

- macOS: run `sure auth login` in a logged-in session and confirm the `sure-cli` generic-password item exists.
- Linux desktop: run `sure auth login` with GNOME Keyring or KWallet unlocked.
- The Rails `db`/`redis` services were already running natively for the controller tests and rswag regeneration; no additional environment work was needed.

## Known Stubs

| File | Stub | Resolved by |
|------|------|-------------|
| `cli/lib/sure/auth/store.rb` | `Auth::NullStore` remains as a safe no-op backend | Not used by `Context`; retained for tests and environment-only clients |
| `cli/lib/sure/cli/commands/doctor.rb` | `call` placeholder | Plan 01-05 |
| `cli/lib/sure/cli/commands/completion.rb` | `call` placeholder | Plan 01-05 |

`NullStore` is no longer on the production path: `Context#store` constructs `StoreFactory`.

## Threat Flags

None beyond the plan's threat model. T-04-01 (private atomic storage and input limits), T-04-02 (stdin-only keychain secrets and scrubbed child environment), T-04-03 (usage validation before persistence and config rollback), T-04-04 (write preflight and 403 -> exit 3), T-04-05 (non-secret status projection), and T-04-SC (absolute helper resolution with argument arrays) are implemented and covered by tests.

## Next Phase Readiness

- Plan 01-05 can report `StoreFactory#mode`/`#location` and reuse `Auth::Status` for `sure doctor`, and extend `Output::Selector` for CSV/NDJSON without touching this slice.
- Phase 2 read commands inherit a working credential source and never need to call `store.read` themselves; they use `Context#client`.
- Verification evidence:
  - `cd cli && bundle exec rake test` → 237 runs, 966 assertions, 0 failures.
  - `cd cli && bundle exec rake lint` → 92 files, 0 offenses.
  - `cd cli && bundle exec ruby -Itest test/commands/auth_test.rb` → 9 runs, 65 assertions, 0 failures.
  - `cd /home/randy/sure-cli && RAILS_ENV=test bin/rails test test/controllers/api/v1/usage_controller_test.rb` → 7 runs, 146 assertions, 0 failures.
  - `cd /home/randy/sure-cli && RAILS_ENV=test bundle exec rake rswag:specs:swaggerize` → 452 examples, 0 failures, 89 pending; `/api/v1/usage` and the `Usage` schema were generated.
  - `bin/rubocop` on the four changed Rails/spec files → 0 offenses.

## Self-Check: PASSED

- Task commits `1db7bb379`, `06ad311b3`, and `19bf39819` exist on `main`.
- All new store, auth, test-support, spec, and documentation files exist on disk; `docs/api/openapi.yaml` contains `"/api/v1/usage"` and `Usage:`.
- No secret appears in any test assertion output, status payload, or generated documentation path exercised by the suite.

---
*Phase: 01-foundation-api-key-authentication*
*Completed: 2026-11-01*
