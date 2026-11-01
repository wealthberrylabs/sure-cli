---
phase: 01-foundation-api-key-authentication
plan: 08
subsystem: auth
tags: [credential-isolation, path-prefix, keychain, file-fallback, faraday, logout]

# Dependency graph
requires:
  - phase: 01-foundation-api-key-authentication
    provides: CredentialKey, AuthMiddleware, StoreFactory, FileStore, and Logout from plans 01-03 and 01-04
provides:
  - Credential identity that includes the normalized server path prefix
  - X-Api-Key pinning to the profile's scheme, host, port, and path prefix
  - Keychain-miss fallback to the 0600 file copy for reads
  - Truthful `auth logout` `deleted` result and idempotent second run
affects: [auth, api, doctor, status, phase-01-reverification]

# Tech tracking
tech-stack:
  added: []
  patterns:
    - "Normalized origin identity: scheme + host[:port] + path prefix without a trailing slash"
    - "Prefix-boundary path check so /tenant-a never authorizes /tenant-ab"

key-files:
  created:
    - cli/test/unit/http/auth_middleware_test.rb
    - cli/test/unit/auth/logout_test.rb
  modified:
    - cli/lib/sure/auth/credential_key.rb
    - cli/lib/sure/http/auth_middleware.rb
    - cli/lib/sure/auth/store_factory.rb
    - cli/test/unit/auth/credential_key_test.rb
    - cli/test/unit/auth/store_factory_test.rb
    - cli/test/unit/auth/keychain_store_test.rb
    - cli/test/unit/auth/api_key_provider_test.rb

key-decisions:
  - "The credential origin keeps the path prefix, so two tenants on one origin never share a keychain account or fingerprint"
  - "A trailing slash is normalized away but a root URL and a prefixed URL stay distinct, keeping existing root-URL accounts byte-identical"
  - "AuthMiddleware compares origin and a path prefix (not the request's full path), so a root profile still reaches every endpoint"
  - "A nil keychain read is a miss: the file copy is consulted before concluding the credential is absent"

patterns-established:
  - "Credential identity and outbound header pinning derive from the same normalized origin string"
  - "Read-before-delete determines `deleted`, and the read consults both backends"

requirements-completed: [FOUND-04, AUTH-02, AUTH-09]

# Metrics
duration: 4min
completed: 2026-11-01
---

# Phase 1 Plan 8: Credential Isolation by Server Path Prefix Summary

**Credentials are now keyed and sent per scheme/host/port/path-prefix, and logout finds and truthfully deletes a file-stored key while a keychain is present**

## Performance

- **Duration:** 4 min
- **Started:** 2026-11-01T17:31:00Z
- **Completed:** 2026-11-01T17:35:00Z
- **Tasks:** 2
- **Files modified:** 9 (2 test files created, 7 modified)

## Accomplishments

- `CredentialKey` now includes the URL path prefix in `origin`/`origin_fingerprint`, so `https://host/tenant-a` and `https://host/tenant-b` can no longer overwrite or read each other's credential; root-URL accounts are byte-identical to the pre-change value.
- `AuthMiddleware` refuses to attach `X-Api-Key` to any scheme/host/port or neighboring path prefix (including `/tenant-ab`) before the request leaves the process, while a root profile still reaches every endpoint.
- `StoreFactory#read` treats a nil keychain result as a miss and falls back to the 0600 file copy, so `sure auth logout` reports `deleted: true` when it removes the only copy and `deleted: false` on a second run.

## Task Commits

Each task was committed atomically:

1. **Task 1: Include the normalized path prefix in credential identity and auth pinning** - `0bbec0677` (fix)
2. **Task 2: Treat a nil keychain read as a miss and make logout report the truth** - `21e9380d1` (fix)

**Plan metadata:** `docs(01-08)` commit created after this summary.

## Files Created/Modified

- `cli/lib/sure/auth/credential_key.rb` - `normalize_origin` appends the trailing-slash-stripped path; label stays host-only and `inspect` stays URL-free
- `cli/lib/sure/http/auth_middleware.rb` - `path_prefix`, `path_within_prefix?`, and `expected_destination`; `origin_of` still compares scheme/host/port only
- `cli/lib/sure/auth/store_factory.rb` - keychain nil now falls through to the file copy; `StoreError` fallback unchanged
- `cli/test/unit/auth/credential_key_test.rb` - prefix collision, trailing-slash, root-vs-prefixed, and unchanged root-account assertions
- `cli/test/unit/http/auth_middleware_test.rb` - new: sends for the matching prefix, refuses neighboring prefixes and other origins, root profile coverage
- `cli/test/unit/auth/store_factory_test.rb` - keychain-miss fallback and empty-both-backends cases
- `cli/test/unit/auth/logout_test.rb` - new: file-only credential deletion, idempotent second run, keychain read failure, secret-free rendering
- `cli/test/unit/auth/keychain_store_test.rb` - read-back `server_url` expectation now includes `/sure`
- `cli/test/unit/auth/api_key_provider_test.rb` - default-port test no longer asserts that paths are ignored

## Decisions Made

- Path prefix is part of credential identity but the query and fragment are not; `UrlBuilder` already rejects those for server URLs.
- `AuthMiddleware` keeps `origin_of` origin-only and adds a separate prefix check. Comparing the request's full path to the base URL would have broken every root-profile endpoint.
- The refusal message now names the expected destination including the prefix, which is what makes a cross-tenant refusal diagnosable; it still never contains the secret.

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 1 - Bug] Two tests encoded the path-dropping identity**
- **Found during:** Task 1 verification (`bundle exec rake test`)
- **Issue:** `cli/test/unit/auth/keychain_store_test.rb:22` asserted that a read-back credential's `server_url` lost the `/sure` prefix, and `cli/test/unit/auth/api_key_provider_test.rb:151` asserted that different paths share an account — both are the CR-04 defect expressed as expectations.
- **Fix:** The keychain assertion now expects `https://sure.example.com/sure` (the keychain stores reconstruct `server_url` from `key.origin`, which now correctly carries the prefix). The provider test compares the same path for default-port equality and refutes equality across paths.
- **Files modified:** `cli/test/unit/auth/keychain_store_test.rb`, `cli/test/unit/auth/api_key_provider_test.rb`
- **Verification:** `bundle exec rake test` → 339 runs green; `bundle exec rake lint` → 108 files, 0 offenses
- **Committed in:** `0bbec0677` (Task 1 commit)

---

**Total deviations:** 1 auto-fixed (1 bug)
**Impact on plan:** Both edits are test-only consequences of the intended identity change; no production behavior outside the plan. Two files outside the plan's `files_modified` were touched only to keep the suite truthful.

## Issues Encountered

- **`bundle exec rubocop` cannot launch in this environment** (same issue recorded in plan 01-07): the gem is installed and loadable, but Bundler reports `command not found: rubocop`. Lint was run through the repository task instead: `cd cli && bundle exec rake lint` → 108 files inspected, no offenses.
- **The plan's third verification command only executes the first file**: `ruby -Itest a.rb b.rb` treats `b.rb` as an argument, not a second test file. Each of the four test files was therefore run individually (results below).

## Verification Results

| Command | Result |
|---------|--------|
| `cd cli && bundle exec rake test` | 339 runs, 1499 assertions, 0 failures, 0 errors, 0 skips |
| `cd cli && bundle exec rake lint` (rubocop replacement) | 108 files inspected, no offenses |
| `bundle exec ruby -Itest test/unit/auth/credential_key_test.rb` | 9 runs, 29 assertions, 0 failures |
| `bundle exec ruby -Itest test/unit/http/auth_middleware_test.rb` | 8 runs, 64 assertions, 0 failures |
| `bundle exec ruby -Itest test/unit/auth/store_factory_test.rb` | 11 runs, 38 assertions, 0 failures |
| `bundle exec ruby -Itest test/unit/auth/logout_test.rb` | 5 runs, 16 assertions, 0 failures |

**Manual cross-tenant check** (isolated `XDG_CONFIG_HOME`, file-stored credential for `http://127.0.0.1:9/tenant-a`):

- `sure api GET /api/v1/usage --server http://127.0.0.1:9/tenant-b --json` → exit 3, `authentication_error: no API key for profile`, no network request.
- The same command without `--server` (profile `/tenant-a`) → exit 8 network error, proving the credential was resolved and only then reached the transport layer.

## Known Stubs

None. No placeholder values, TODOs, or unwired data sources were introduced.

## Threat Flags

None. The change narrows an existing trust boundary (fewer URLs can receive the key) and adds no new surface.

## User Setup Required

None - no external service configuration required.

## Next Phase Readiness

- Verification gap 4 (per-server credential isolation) and the AUTH-02 partial are closed with collision tests; CR-04 and WR-01 are addressed.
- Real keychain round-trips (macOS Keychain, Linux Secret Service) remain unverified on this Linux host and stay on the phase verification checklist.
- Plan 01-09 remains before phase 01 can be re-verified.

---
*Phase: 01-foundation-api-key-authentication*
*Completed: 2026-11-01*
