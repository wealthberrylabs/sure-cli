---
phase: 01-foundation-api-key-authentication
plan: 02
subsystem: cli
tags: [ruby, config, profiles, tls, atomic-write, api-key, precedence]

# Dependency graph
requires:
  - phase: 01-foundation-api-key-authentication
    provides: "Standalone gem, Thor application surface, injected runtime, and error/exit-code boundary from Plan 01-01"
provides:
  - "Schema-validated, private (0700/0600) config files with locked atomic writes"
  - "Named profile resolution with flag > environment > profile > default precedence"
  - "Prefix-preserving URL joining and TLS policy (CA bundle, --insecure, http warning)"
  - "Environment-first API-key provider with a credential/store contract and redacted inspection"
affects: [01-03, 01-04, 01-05, phase-2, phase-7]

# Tech tracking
tech-stack:
  added: []
  patterns:
    - "One resolver answers profile/server/TLS/output for every command; commands never inspect argv or ENV"
    - "Config writes are read-modify-write under an exclusive flock, then temp-file + rename at 0600"
    - "Secrets are read into memory only and redacted by inspect at every object boundary"
    - "Immutable Data value objects for profiles and credentials"

key-files:
  created:
    - cli/lib/sure/config.rb
    - cli/lib/sure/config/paths.rb
    - cli/lib/sure/config/loader.rb
    - cli/lib/sure/config/profile.rb
    - cli/lib/sure/config/resolver.rb
    - cli/lib/sure/config/atomic_file.rb
    - cli/lib/sure/http/url_builder.rb
    - cli/lib/sure/auth/credential.rb
    - cli/lib/sure/auth/credential_key.rb
    - cli/lib/sure/auth/store.rb
    - cli/lib/sure/auth/api_key_provider.rb
    - cli/test/unit/config/paths_test.rb
    - cli/test/unit/config/loader_test.rb
    - cli/test/unit/config/atomic_file_test.rb
    - cli/test/unit/config/resolver_test.rb
    - cli/test/unit/http/url_builder_test.rb
    - cli/test/unit/auth/api_key_provider_test.rb
    - cli/test/fixtures/config/valid.yml
    - cli/test/fixtures/config/invalid_schema.yml
    - cli/test/fixtures/config/invalid_url.yml
    - cli/test/support/temp_config.rb
  modified:
    - cli/lib/sure.rb
    - cli/lib/sure/cli/base.rb
    - cli/lib/sure/cli/context.rb

key-decisions:
  - "Config paths expose both credentials.lock (credential store) and config.lock (config read-modify-write) so the two concerns never share a lock"
  - "Profile values are resolved into one frozen Config::Profile with a sources map for diagnostics"
  - "UrlBuilder validates the server base URL structurally and warns on plain http; Resolver reuses validation without duplicating the warning"
  - "NullStore is the safe wave-3 placeholder; concrete keychain/file stores remain Plan 01-04 work"
  - "Environment keys mark cached profile scopes untrusted via Context#scopes_trusted?"

patterns-established:
  - "Config::AtomicFile.write(path, content, mode: 0o600): symlink refusal, temp file + rename, directory fsync"
  - "Config::Loader#save deep-merges profiles inside an flock and re-reads before writing"
  - "Config::Resolver#resolve returns an immutable Profile and raises UsageError for missing/invalid settings"
  - "Auth::ApiKeyProvider#fetch returns [secret, :environment | :store] and never calls the network"

requirements-completed: [FOUND-03, FOUND-04, AUTH-08]

# Metrics
duration: 4 min
completed: 2026-11-01
---

# Phase 1 Plan 02: Configuration, Profiles, and API-Key Provider Summary

**Named profiles with flag-first precedence, prefix-safe TLS-aware URLs, locked 0600 atomic config writes, and an environment-first API key that never touches disk**

## Performance

- **Duration:** 4 min
- **Started:** 2026-11-01T01:14:52Z
- **Completed:** 2026-11-01T01:18:31Z
- **Tasks:** 3
- **Files modified:** 24

## Accomplishments

- `Config::Paths` resolves `XDG_CONFIG_HOME/sure`, `%APPDATA%\sure`, or `~/.config/sure`, creates a 0700 directory, and names `config.yml`, `credentials.json`, `credentials.lock`, and `config.lock`.
- `Config::Loader` reads with `YAML.safe_load_file(..., aliases: false)`, rejects unknown top-level/profile keys and unsafe permissions, and writes through an `flock`-serialized deep merge into a 0600 atomic file.
- `Config::Resolver` applies `flag > environment > profile > default` to profile, server, CA bundle, TLS verification, and output, returning an immutable `Config::Profile` with a `sources` map.
- `HTTP::UrlBuilder` preserves server path prefixes (`https://host/sure` + `/api/v1/usage` → `https://host/sure/api/v1/usage`), rejects userinfo/query/fragment/API-prefixed URLs, and warns once for non-loopback plain `http`.
- `Auth::ApiKeyProvider` returns `SURE_API_KEY` for the current process first, falls back to the store, rejects unsafe keys with exit 2, and raises exit 3 with actionable login guidance when absent.
- `Sure::CLI::Context` resolves profile, URL builder, output format, API key, and credential source once per command; `inspect` never reveals the secret.

## Task Commits

Each task was committed atomically:

1. **Task 1: Implement config paths, schema validation, and atomic 0600 writes** - `4d19f1d9f` (feat)
2. **Task 2: Implement precedence resolution, URL joining, and TLS policy** - `94dd72642` (feat)
3. **Task 3: Implement the environment-first API-key provider and secret-safe context** - `a3b820c8c` (feat)

**Plan metadata:** `docs(01-02)` commit follows this summary.

## Files Created/Modified

- `cli/lib/sure/config/paths.rb` - XDG/APPDATA/home directory resolution and private directory creation
- `cli/lib/sure/config/loader.rb` - Closed-schema YAML validation, permission checks, locked deep-merge saves
- `cli/lib/sure/config/profile.rb` - Immutable resolved profile value with defaults and source map
- `cli/lib/sure/config/atomic_file.rb` - Symlink-safe 0600 temp-file/rename writer with directory fsync
- `cli/lib/sure/config/resolver.rb` - Precedence resolution for profile/server/CA/TLS/output
- `cli/lib/sure/http/url_builder.rb` - Prefix-preserving URL validation and joining
- `cli/lib/sure/auth/credential.rb` - Redacted immutable credential value
- `cli/lib/sure/auth/credential_key.rb` - Service/account/origin-fingerprint identity
- `cli/lib/sure/auth/store.rb` - Store interface plus `NullStore` wave-3 placeholder
- `cli/lib/sure/auth/api_key_provider.rb` - Environment-first key selection and validation
- `cli/lib/sure/cli/context.rb` - One-per-command resolution of profile, URL, output, key, and source
- `cli/lib/sure/cli/base.rb` - Passes Thor options into `Context.current`
- `cli/lib/sure.rb` - Loads config, resolver, URL builder, and auth provider
- `cli/test/**` - Paths/loader/atomic/resolver/URL/provider tests, fixtures, and temp-config helper

## Decisions Made

- Kept separate lock files: `credentials.lock` for Plan 01-04 credential writes and `config.lock` for profile read-modify-write. The plan referenced both names; separating them avoids coupling two write paths.
- `Resolver` validates the server URL through `UrlBuilder.parse` (no warning), while `Context` builds the `UrlBuilder` that emits the one-time `http` warning, so validation is idempotent.
- `NullStore` ships now as the interface placeholder; concrete keychain/file stores are intentionally left to Plan 01-04.
- Cached profile scopes are marked untrusted whenever the key comes from `SURE_API_KEY`, exposed as `Context#scopes_trusted?` for Plan 01-04 to enforce.

## Deviations from Plan

None - plan executed exactly as written.

## Issues Encountered

- The acceptance criterion "the process exits 3 through `Sure.run`" cannot be exercised end-to-end yet because no command consumes `Context` until Plan 01-04. The provider test asserts `error.exit_code == Errors::ExitCodes::AUTHENTICATION` (3), and `Runner` already maps that class; Plan 01-04 will exercise it through `auth status`.
- The plan's targeted verification command passes multiple test files to `ruby -Itest`; Ruby only executes the first. Each file was run individually (resolver 16, URL builder 12, provider 13 runs) and the full `rake test` suite (85 runs) covers all of them.

## User Setup Required

None - no external service configuration required.

## Known Stubs

| File | Stub | Resolved by |
|------|------|-------------|
| `cli/lib/sure/auth/store.rb` | `Auth::NullStore` read-miss and write/delete `GeneralError` | Plan 01-04 |

`NullStore` is deliberate: it lets an environment-only `SURE_API_KEY` build a client before keychain/file storage lands.

## Threat Flags

None beyond the plan's threat model. T-02-01 (private atomic storage), T-02-02 (URL/TLS validation), T-02-03 (key never persisted or printed), and T-02-04 (closed YAML schema) are implemented and covered by tests.

## Next Phase Readiness

- Plan 01-03 can build `HTTP::Client` from `Context#profile` and `Context#url_builder`; timeouts call `open_timeout`/`read_timeout`.
- Plan 01-04 implements `FileStore`/keychain stores against `Auth::Store` and `CredentialKey`, and consumes `SURE_API_KEY` through `ApiKeyProvider` without redefining the contract.
- Verification evidence: `bundle exec rake test` → 85 runs, 343 assertions, 0 failures; `bundle exec rubocop` → 45 files, 0 offenses.

## Self-Check: PASSED

- Task commits `4d19f1d9f`, `94dd72642`, `a3b820c8c` exist on `main`.
- `cli/lib/sure/config/resolver.rb`, `cli/lib/sure/http/url_builder.rb`, `cli/lib/sure/auth/api_key_provider.rb`, `cli/lib/sure/config/atomic_file.rb`, `cli/lib/sure/cli/context.rb`, and all three targeted test files exist on disk.
- `grep -R "SURE_API_KEY" cli/lib` shows only the provider read and the existing 01-01 rejection message; no file write path.
- Full suite and lint are green.

---
*Phase: 01-foundation-api-key-authentication*
*Completed: 2026-11-01*
