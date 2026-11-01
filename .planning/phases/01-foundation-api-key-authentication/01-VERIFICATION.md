---
phase: 01-foundation-api-key-authentication
verified: 2026-11-01T02:14:04Z
status: gaps_found
score: 2/5 must-haves verified
overrides_applied: 0
gaps:
  - truth: "`sure auth login` stores the key from a hidden prompt, and secrets never appear in output"
    status: failed
    reason: "`prompt_secret` only hides input when stdin responds to `getpass`/`noecho`, but nothing requires `io/console`, so on a real TTY the method falls through to `runtime.stdin.gets` and echoes the API key in cleartext. Confirmed in `cli/lib/sure/auth/login.rb:182-196`; no `require \"io/console\"` anywhere in `cli/lib`."
    artifacts:
      - path: "cli/lib/sure/auth/login.rb"
        issue: "Interactive prompt echoes the secret because IO#getpass/noecho are unavailable without io/console"
    missing:
      - "Require `io/console` (guarded for non-TTY) and prefer `IO#getpass`/`noecho`; add a PTY test proving the key is not echoed"
  - truth: "`sure --profile staging api GET /api/v1/accounts --json` returns server data with exit 0"
    status: failed
    reason: "Any global/class option placed before the command name breaks resolution. `sure --profile staging api GET /api/v1/accounts --json` exits 2 with `Could not find command \"api\"`; `sure --json doctor` prints help and exits 0. This is the literal command from the phase success criteria."
    artifacts:
      - path: "cli/lib/sure/cli/runner.rb"
        issue: "No argv normalisation before Thor dispatch; Thor 1.5 retrieve_command_name mis-resolves leading class options"
      - path: "cli/lib/sure/cli/application.rb"
        issue: "Class options are accepted only in the trailing position"
    missing:
      - "Normalise argv (or configure Thor) so class options are accepted before or after the command, and add tests for both orders"
  - truth: "A user can target a server with a custom CA bundle or `--insecure` when authenticating"
    status: failed
    reason: "The `Auth` subcommand declares no `--ca-bundle`/`--insecure` options and `build_profile` omits them, so `sure auth login --ca-bundle ...` cannot reach a private-CA server (it silently accepts an unusable value)."
    artifacts:
      - path: "cli/lib/sure/cli/commands/auth.rb"
        issue: "Auth class options omit ca-bundle/insecure; build_profile ignores TLS settings"
    missing:
      - "Add TLS options to the auth command group and thread them into the login probe/profile"
  - truth: "Credentials are isolated per server URL including path prefix"
    status: failed
    reason: "`CredentialKey#normalize_origin` reduces the server URL to scheme://host[:port], dropping the path. Two deployments at `https://host/tenant-a` and `https://host/tenant-b` share one keychain account, so a login overwrites the other and the origin-only auth check can send that key to the neighbouring deployment."
    artifacts:
      - path: "cli/lib/sure/auth/credential_key.rb"
        issue: "Path prefix excluded from the credential fingerprint"
    missing:
      - "Include the normalised path prefix in the credential key and add a collision test"
  - truth: "Generated zsh completion is installable and usable"
    status: partial
    reason: "`Completion::Generator#render_zsh` defines `_sure` and then calls `_sure \"$@\"` at file scope. When the file is sourced, this invokes the function with the sourcing shell's arguments; when autoloaded via `fpath`, the trailing call is dead code. The generated script does not behave correctly in the documented install path."
    artifacts:
      - path: "cli/lib/sure/completion/generator.rb"
        issue: "Trailing `_sure \"$@\"` call after the function definition"
    missing:
      - "Remove the trailing invocation (keep `#compdef sue`) and verify with `source <(sure completion zsh)` in a clean zsh"
deferred: []
human_verification:
  - test: "Run `sure auth login` in a logged-in macOS session and confirm the item is stored in the login keychain, then `sure auth logout` removes it."
    expected: "Keychain entry created and deleted; `auth status` reflects both transitions."
    why_human: "No macOS Keychain backend in this Linux environment; only fakes were exercised."
  - test: "Run `sure auth login` against a Linux desktop with libsecret/Secret Service running."
    expected: "Secret stored via Secret Service and readable back by `sure auth status`."
    why_human: "No Secret Service daemon in this environment."
  - test: "Run `sure auth status` and `sure api GET /api/v1/accounts --json` against a real Sure deployment with a read-only key."
    expected: "Status shows server, user, key name and scopes; api returns the server payload with exit 0 and valid JSON."
    why_human: "No live Sure server was available; pipeline correctness was proven only against a local HTTP fixture server."
---

# Phase 1: Foundation & API-Key Authentication Verification Report

**Phase Goal:** A user can install the gem, point it at a Sure server, authenticate with an API key, and get one truthful API response through a shared, safe pipeline.
**Verified:** 2026-11-01T02:14:04Z
**Status:** gaps_found
**Re-verification:** No — initial verification

> Verification note: ROADMAP marks this phase `Mode: mvp`, but the phase goal is not in the MVP user-story form (`As a …, I want to …, so that …`). Standard goal-backward verification was applied against the ROADMAP success criteria instead of refusing on the MVP format guard.

## Goal Achievement

### Observable Truths

| # | Truth | Status | Evidence |
| --- | --- | --- | --- |
| 1 | A locally built gem installs and `sure --version` / `sure help` work without loading Rails | ✓ VERIFIED | Built `sure-0.1.0.gem`, installed into temp `GEM_HOME`; `sure --version` → `sure 0.1.0`, `sure help` exit 0; `require "sure"; Sure.run(["--version"])` left `Rails` undefined |
| 2 | `sure auth login` stores a key from a hidden prompt, `--api-key-file`, `--api-key-stdin`, or `SURE_API_KEY`; `auth status` shows server, user, key name, scopes | ✗ FAILED | Hidden-prompt path echoes the key (`login.rb:190-196`, no `io/console`). File/stdin/env paths and the status payload are implemented and tested, but the hidden-prompt criterion is not met |
| 3 | `sure --profile staging api GET /api/v1/accounts --json` returns server data with exit 0 and piped JSON | ✗ FAILED | Literal command exits 2: `Could not find command "api"`. Leading options break resolution; `sure --json doctor` prints help and exits 0. `sure api …` without leading options works (integration smoke test passes) |
| 4 | `sure doctor` diagnoses a bad URL, key, or TLS setting and exits nonzero with an actionable message | ✓ VERIFIED | `sure doctor --server "not a url" --json` exited 1 with FAIL on config/profile and concrete `fix` strings; ordered non-short-circuiting checks covered by doctor tests |
| 5 | `sure api GET /api/v1/accounts` works, and secrets never appear in output, logs, or debug traces | ✗ FAILED | Request pipeline and redaction work for non-interactive paths, but interactive login prints the API key to the terminal; the redactor also ignores secrets shorter than 4 characters |

**Score:** 2/5 truths verified

### Required Artifacts

| Artifact | Expected | Status | Details |
| --- | --- | --- | --- |
| `cli/sure.gemspec`, `cli/exe/sure` | Installable gem, no Rails | ✓ VERIFIED | Gem builds/installs; `config/operations.yml` packaged |
| `cli/lib/sure/config/*.rb` | Profiles, paths, atomic writes, URL builder | ✓ VERIFIED | Unit tests green; TLS/profile plumbing exists for `api`/`doctor` but not `auth` |
| `cli/lib/sure/http/*.rb` | Faraday pipeline, auth, retry, rate limit | ✓ VERIFIED | Single connection factory; smoke test against loopback server |
| `cli/lib/sure/output/*.rb` | JSON/table/CSV/NDJSON/fields | ✓ VERIFIED | Formatter tests green; leading-flag parsing gap is in Runner, not formatters |
| `cli/lib/sure/auth/*.rb` | Keychain-first store + 0600 fallback | ⚠️ PARTIAL | Fakes pass; file fallback is ignored on read whenever keychain mode is active, so logout can report `deleted: false` while deleting a real credential |
| `cli/lib/sure/auth/credential_key.rb` | Per-server credential identity | ✗ STUB (semantically incomplete) | Origin ignores the URL path prefix |
| `cli/lib/sure/completion/generator.rb` | bash/zsh/fish completion | ⚠️ PARTIAL | bash/fish parse; zsh script has a trailing self-invocation |
| `app/controllers/api/v1/usage_controller.rb` | Key/scopes/user on usage response | ✓ VERIFIED | Rails test 7 runs / 146 assertions green; rswag spec documents the schema |
| `.planning/phases/01-…/01-REVIEW.md` | Code review report | ✓ VERIFIED | 5 critical / 11 warning / 6 info; all 5 criticals independently reproduced by the verifier |

### Key Link Verification

| From | To | Via | Status | Details |
| --- | --- | --- | --- | --- |
| `cli/lib/sure/cli/commands/api.rb` | `cli/lib/sure/http/client.rb` | shared pipeline | ✓ WIRED | Integration smoke + command tests |
| `cli/lib/sure/http/connection.rb` | `cli/lib/sure/http/auth_middleware.rb` | Faraday middleware | ✓ WIRED | `X-Api-Key` asserted in tests |
| `cli/lib/sure/http/client.rb` | `cli/lib/sure/errors/mapper.rb` | rescue boundary | ✓ WIRED | Exit-code mapping tests |
| `cli/lib/sure/auth/login.rb` | `cli/lib/sure/auth/store_factory.rb` | credential write | ⚠️ PARTIAL | Write path wired; keychain read fallback logic flawed |
| `cli/lib/sure/cli/runner.rb` | `cli/lib/sure/cli/application.rb` | argv → Thor | ✗ NOT_WIRED | Leading class options never reach the command |

### Data-Flow Trace (Level 4)

| Artifact | Data Variable | Source | Produces Real Data | Status |
| --- | --- | --- | --- | --- |
| `cli/lib/sure/cli/commands/doctor.rb` | check results | `Doctor::Runner` ordered checks | Yes (observed FAIL/SKIP output) | ✓ FLOWING |
| `cli/lib/sure/cli/commands/api.rb` | response envelope | Faraday client | Yes (loopback fixture server) | ✓ FLOWING |
| `cli/lib/sure/auth/status.rb` | user/key/scopes | `GET /api/v1/usage` | Yes (controller test + parser tests) | ✓ FLOWING |
| `cli/lib/sure/output/table.rb` | rows | response envelope | Yes (formatter tests) | ✓ FLOWING |

### Behavioral Spot-Checks

| Behavior | Command | Result | Status |
| --- | --- | --- | --- |
| Gem installs and reports version without Rails | `gem build && GEM_HOME=$tmp gem install --local … && $tmp/bin/sure --version` | `sure 0.1.0`; Rails undefined | ✓ PASS |
| Unknown command exits 2, stderr only, no backtrace | `sure nonexistent` | exit 2; stdout empty; one JSON error line | ✓ PASS |
| Leading global option before command | `sure --profile staging api GET /api/v1/accounts --json` | exit 2 `Could not find command "api"` | ✗ FAIL |
| Leading output flag before command | `sure --json doctor` | Prints help, exit 0 | ✗ FAIL |
| Doctor diagnoses bad input | `sure doctor --server "not a url" --json` | exit 1, FAIL checks with fixes | ✓ PASS |
| Interactive login hides input | code inspection: `prompt_secret` without `io/console` | falls through to `stdin.gets` | ✗ FAIL |
| CLI suite | `cd cli && bundle exec rake test` | 281 runs, 1217 assertions, 0 failures | ✓ PASS |
| Rails usage controller | `RAILS_ENV=test bin/rails test test/controllers/api/v1/usage_controller_test.rb` | 7 runs, 146 assertions, 0 failures | ✓ PASS |

### Probe Execution

Step 7c: SKIPPED (no `scripts/*/tests/probe-*.sh` probes declared or present).

### Requirements Coverage

| Requirement | Source Plan | Description | Status | Evidence |
| --- | --- | --- | --- | --- |
| FOUND-01 | 01-01 | Installable gem, runnable from any shell | ✓ SATISFIED | Temp GEM_HOME install smoke |
| FOUND-02 | 01-01 | Version, help, per-command help | ✓ SATISFIED | CLI + tests |
| FOUND-03 | 01-02 | Named profiles, `--profile`/env/default switch | ✗ BLOCKED | `--profile` before a command breaks dispatch; env/default paths exist |
| FOUND-04 | 01-02 | Server URL with path prefix, CA bundle, insecure opt-in | ✗ BLOCKED | Path prefix dropped in credential key; auth command cannot pass TLS options |
| FOUND-05 | 01-05 | TTY tables, piped JSON | ✓ SATISFIED | Formatter + non-TTY tests |
| FOUND-06 | 01-05 | Force `--json`/`--csv`/`--ndjson`/`--fields` | ✗ BLOCKED | Leading flags before the command are ignored (help + exit 0) |
| FOUND-07 | 01-03 | Deterministic exit codes, stderr, no backtraces | ✓ SATISFIED | Error mapper and unknown-command checks |
| FOUND-08 | 01-05 | `sure doctor` full checklist | ✓ SATISFIED | Doctor tests + live run |
| FOUND-09 | 01-03 | Any endpoint via `sure api`, redaction | ✓ SATISFIED | Pipeline + redactor tests |
| FOUND-10 | 01-05 | bash/zsh/fish completion | ⚠️ PARTIAL | zsh generator defect |
| AUTH-01 | 01-04 | Login via hidden prompt/file/stdin | ✗ BLOCKED | Hidden prompt echoes the key |
| AUTH-02 | 01-04 | Keychain + 0600 atomic file fallback | ⚠️ PARTIAL | File fallback read bug; real backends untested here |
| AUTH-03 | 01-04 | `auth status` shows server/profile/user/key/scopes/tier | ✓ SATISFIED | Status payload tests + usage controller |
| AUTH-08 | 01-02 | `SURE_API_KEY` without persistence | ✓ SATISFIED | Provider tests |
| AUTH-09 | 01-03 | Never print/log secrets | ✗ BLOCKED | Interactive echo; short-secret redaction gap |
| SAFE-05 | 01-05 | No prompt without a TTY | ✓ SATISFIED | Non-TTY tests |
| SAFE-06 | 01-04 | Scope preflight before writes | ✓ SATISFIED | Scope preflight tests |

No orphaned requirements: all 17 phase requirement IDs are claimed by a plan.

### Anti-Patterns Found

| File | Line | Pattern | Severity | Impact |
| --- | --- | --- | --- | --- |
| `cli/lib/sure/cli/base.rb` | 13 | `NOT_IMPLEMENTED = "not implemented until its plan lands"` | ℹ️ Info | Intentional placeholder text, not emitted by shipped commands |
| `cli/lib/sure/auth/store.rb` | 37 | Comment: "Safe placeholder until real storage lands" | ℹ️ Info | Stale comment: real stores now exist; NullStore remains test-only |

No `TBD`/`FIXME`/`XXX` debt markers were found in phase source files.

### Human Verification Required

1. **macOS Keychain round-trip** — log in, confirm the item exists, log out, confirm removal. Not testable on Linux.
2. **Linux Secret Service round-trip** — same flow with libsecret running. No daemon here.
3. **Live Sure server** — `sure auth status` and `sure api GET /api/v1/accounts --json` against a real deployment with a read-only key. Only a local fixture server was used.

### Gaps Summary

The technical foundation is largely real: the gem builds and installs without Rails, the HTTP/output/error pipeline is shared and tested, doctor works, and the Rails usage endpoint is covered. However, the phase's headline user journey is not yet truthful. The exact command in Success Criterion 3 fails because leading global options break Thor dispatch. Interactive `auth login` echoes the API key because `io/console` is never loaded. `auth login` cannot pass a custom CA or insecure opt-in. Credentials are keyed without the URL path, so two deployments on one host collide. The zsh completion script is malformed. These are blocking gaps, corroborated by the phase code review (5 critical findings, each independently reproduced).

---

_Verified: 2026-11-01T02:14:04Z_
_Verifier: OpenCode orchestrator (inline goal-backward verification; gsd-verifier agent unavailable in this runtime)_
