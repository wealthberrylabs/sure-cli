---
phase: 1
reviewers: [opencode-gpt-6-luna, opencode-gemini-4-argon]
reviewed_at: 2026-11-01T00:35:00Z
plans_reviewed: [01-01-PLAN.md, 01-02-PLAN.md, 01-03-PLAN.md, 01-04-PLAN.md, 01-05-PLAN.md]
---

# Cross-AI Plan Review — Phase 1

**Reviewer availability:** The installed `claude` and `codex` CLIs are not authenticated in this environment (`Not logged in` / `HTTP 401`), and no Gemini/Qwen/Cursor/local-model reviewer is installed. To avoid a self-review by the executing session, the review was run through OpenCode with two different model families: `opencode-go/gpt-6-luna` and `opencode-go/gemini-4-argon`. Treat the reviewers as independent model families, not as independent CLI implementations.

## GPT-6 Luna Review

# Phase 1 Plan Review

## Overall assessment

The plans are unusually thorough about security boundaries, testability, packaging, and aligning the CLI with Sure’s existing API. Taken together, they cover the 17 listed Phase 1 requirements and build a plausible walking skeleton: package and help, profiles, a shared HTTP pipeline, API-key auth, diagnostics, and automation-friendly output. However, several execution-critical details conflict across plans, and there are unresolved security gaps in secret redaction and raw output. The plans also make the phase dependent on a Ruby toolchain the research environment explicitly lacks, without a concrete provisioning path available to the executor. I would resolve those items before execution.

## Plan 01-01 — Gem skeleton and command catalog

**Summary:** Strong foundation for an isolated gem and testable command boundary. The planned placeholder commands and catalog are useful scaffolding, but the catalog lifecycle is split across tasks in a way that may cause drift.

**Strengths**
- Explicit gem file allowlist and no Rails runtime dependency directly address packaging and isolation risks.
- The injected runtime and single runner boundary support deterministic tests and semantic exit codes.
- Unknown options are rejected, which is important for preventing a forbidden `--api-key` option from being silently accepted.
- The plan reconciles the roadmap’s `accounts list` and `--api-key` wording with the locked Phase 1 decisions.

**Concerns**
- **HIGH — Toolchain blocks execution.** Task 0 says to stop if Ruby 3.4.9/Bundler 2.6.7 are unavailable, while the research says they are unavailable in the execution environment. The suggested devcontainer paths may not be available to the executor, and no confirmed provisioning route is included.
- **MEDIUM — Catalog ownership is split.** Task 2 creates a minimal catalog and loader; Task 3 replaces/expands them and adds validation. The plan also expects command help to be catalog-backed before Task 3. This is workable, but creates an interim state with two catalog schemas.
- **MEDIUM — Thor behavior needs a precise contract.** The plan relies on `Application.start(..., debug: true)` and `exit_on_failure? = false`, but also expects help and version to behave through injected IO. Verify that all Thor help/version/error paths honor the injected streams and do not call `exit` or write through Thor’s global shell.
- **LOW — Verification paths are ambiguous.** The temp install command refers to `cli/sure-0.1.0.gem`; from `cli/`, the artifact is `sure-0.1.0.gem`. Specify the working directory and artifact path consistently.

**Suggestions**
- Resolve the Ruby/Bundler provisioning blocker before execution, or explicitly make it a user setup prerequisite with a confirmed route.
- Define one catalog schema up front and have Task 2 populate it with a minimal valid catalog; Task 3 should add entries and validation rather than change the schema.
- Add a subprocess smoke test for `help` and `version` to verify exit behavior and stdout/stderr separation, in addition to injected-IO tests.

**Risk assessment: MEDIUM.** The skeleton design is sound, but the toolchain blocker and command/catalog handoff need resolution.

## Plan 01-02 — Config, profiles, URL handling, and key provider

**Summary:** Good coverage of precedence, secure config files, server URL validation, and environment-key handling. Some security-sensitive value-object and filesystem details are underspecified.

**Strengths**
- Centralized resolution avoids commands independently interpreting profile, server, TLS, or output settings.
- The URL builder explicitly avoids `URI.join` dropping a mounted path prefix.
- Config loading rejects unknown keys and unsafe YAML aliases.
- The plan distinguishes environment credentials from stored credentials and tests that the environment key is not persisted.

**Concerns**
- **HIGH — Credential inspection can disclose the key.** `Auth::Credential` is specified as `Data.define(:kind, :secret, ...)`, but its generated `inspect` includes the secret. The plan protects `Profile`, `Context`, and `ApiKeyProvider` inspection, but not `Credential`; this conflicts with AUTH-09.
- **MEDIUM — Config writes can lose concurrent changes.** `Loader#save` deep-merges profiles but does not specify locking or a read-modify-write transaction. Concurrent logins or config updates can overwrite one another.
- **MEDIUM — Atomic-write race protection is incomplete.** Refusing symlinks before writing is vulnerable to a target or directory being replaced between validation and rename. Ownership and symlink checks need to cover the config directory and relevant ancestors consistently.
- **MEDIUM — TLS policy and CA paths need more definition.** The plan says custom CA bundles and explicit insecure opt-in, but does not specify validating CA readability or resolving relative paths. A profile with `tls_verify: false` may also disable verification without an explicit per-command opt-in or warning.
- **LOW — API-key source validation is not fully bounded.** It says to reject keys over 4 KiB but does not specify reading a bounded amount from the environment before validating.

**Suggestions**
- Override `Credential#inspect`/`#to_s` to redact `secret`, and add a test asserting the key is absent.
- Specify locking for config read-modify-write, and tests for concurrent profile updates.
- Define the symlink/ownership policy for config directories and files, including race-resistant operations where practical.
- Validate CA bundle existence/readability, define relative-path resolution, and warn whenever TLS verification is disabled.
- Read at most 4 KiB plus one byte from environment/file/pipe sources to enforce the input cap without unbounded reads.

**Risk assessment: HIGH.** The config architecture is solid, but a default `Credential#inspect` leaks secrets and filesystem concurrency/security details need tightening.

## Plan 01-03 — HTTP pipeline, output contract, and `sure api`

**Summary:** This plan establishes the critical shared pipeline and addresses many high-impact HTTP risks. Its biggest gaps are secret redaction of arbitrary keys, raw-response behavior, and an endpoint path-boundary check.

**Strengths**
- One Faraday client, no logging middleware, `include_request: false`, and GET/HEAD-only retries are strong defaults.
- The plan distinguishes server errors, timeouts, rate limits, and authentication failures with stable exit codes.
- It treats redirects as errors and rejects arbitrary hosts in `sure api`.
- The integration test exercises the full command-to-server path, including the API-key header and a mounted server prefix.

**Concerns**
- **HIGH — Redaction cannot guarantee AUTH-09 for arbitrary keys.** The key input accepts keys without requiring the current 64-hex format, but the redactor’s key-shape fallback only masks 64-hex strings. If the server echoes an opaque key in an error message or response, the plan does not ensure that exact active credential is redacted.
- **HIGH — `--raw` conflicts with the “never print keys” guarantee.** It emits the exact success response body and only mentions redaction on errors. A server response that contains an API key would therefore be printed. The plan needs an explicit rule for this conflict.
- **MEDIUM — API path boundary is too loose as written.** “Must start with `/api/v1`” may permit paths such as `/api/v10/...`. It should require exactly `/api/v1` or the `/api/v1/` prefix after normalization, and define treatment of encoded separators and traversal.
- **MEDIUM — Middleware/provider interfaces are underspecified.** `ApiKeyProvider#fetch(profile)` returns a tuple, while `AuthMiddleware` is described as injecting a secret and the client receives an `auth_provider`. Specify how the middleware obtains the key, when it is fetched, and how errors are mapped without exposing it.
- **MEDIUM — Output work is duplicated in Plan 01-05.** This plan creates CSV, NDJSON, field selection, and formatter tests; Plan 01-05 lists the same files and tests again as additions. This risks conflicting ownership and rework.
- **LOW — Error output mode is not explicit.** The context describes JSON errors on stderr in machine mode, but this plan only requires a one-line error. Define whether machine-mode errors are structured JSON or plain text.

**Suggestions**
- Redact the exact active credential in addition to pattern-based matches, including server messages and all error/verbose paths. Add a test with a non-64-hex key.
- Decide how raw output honors AUTH-09: either redact known credentials even in raw mode, or explicitly constrain the guarantee and document the tradeoff.
- Require an exact API-path segment boundary and test `/api/v1`, `/api/v1/accounts`, `/api/v10/accounts`, encoded traversal, and encoded slashes.
- Specify a single provider/middleware contract and test that the secret is fetched once per request context and never appears in exception inspection.
- Assign CSV/NDJSON/field-selection implementation to either this plan or 01-05, not both.

**Risk assessment: HIGH.** The pipeline design is strong, but the redaction/raw-output conflict directly threatens a core security requirement.

## Plan 01-04 — Credential stores, auth commands, and usage API change

**Summary:** The login flow has good validation-before-persistence sequencing and rollback intent. The store fallback and status API work are broad but mostly appropriate. The proposed user payload includes more data than the stated status requirement, and several storage/fallback transitions need firmer contracts.

**Strengths**
- Login validates credentials against `/usage` before persisting them.
- The plan addresses keychain limitations with read-back verification and file fallback.
- Scope preflight occurs before writes, including for environment-supplied keys.
- Logout correctly avoids claiming to revoke an API key when no revocation endpoint exists.
- The additive `/usage` field is covered by Minitest and generated OpenAPI documentation rather than an undocumented CLI assumption.

**Concerns**
- **HIGH — User payload may exceed the requirement.** Task 3 adds `user.id` in addition to email and names, although AUTH-03 only requires the user identity and the research recommendation does not include an ID. This increases personal-data exposure in a response that may be routinely queried by automation.
- **MEDIUM — Keychain fallback persistence is unclear.** A keychain write failure should switch to `FileStore`, update the profile’s configured store, and warn once. The plan describes pieces of this behavior across `StoreFactory` and `Login` but does not make the transition contract explicit for subsequent reads, logout, and failed config writes.
- **MEDIUM — The credential fallback has race and lock-file risks.** `FileStore` specifies a lock and atomic rename but not symlink/ownership/permission checks for the lock file, concurrent directory creation, or what happens when the lock file itself is replaced.
- **MEDIUM — API checklist follow-through is missing.** The repository guidance requires the post-commit API consistency checklist after API endpoint commits. This plan includes tests/spec generation but does not explicitly include that checklist.
- **MEDIUM — `SURE_API_KEY` semantics need clarification.** Login accepts `SURE_API_KEY` as an input and then stores a validated key, while AUTH-08 says automation can use the variable without persistence. These can coexist, but the distinction between ordinary commands and explicit `auth login` should be stated in help and tests.
- **LOW — Adding a user ID is unnecessary for the CLI display.** The CLI status output does not need the server’s internal identifier to satisfy the requirement.

**Suggestions**
- Limit the new API payload to the minimum fields needed for `auth status`; omit `id` unless there is a specific consumer and privacy justification.
- Define store selection and fallback transitions as a state table, including write failure, read failure, config-write rollback, logout, and stale copies.
- Harden and test lock-file permissions, symlinks, ownership, and concurrent writes.
- Add the API consistency checklist as a task acceptance criterion.
- Document that `SURE_API_KEY` is ephemeral for normal commands, while `auth login` intentionally persists the supplied key.

**Risk assessment: MEDIUM-HIGH.** The login sequence is well considered, but filesystem edge cases and unnecessary user data should be addressed before implementation.

## Plan 01-05 — Doctor, output hardening, and completion

**Summary:** The plan rounds out the scripting and diagnostics surface and covers valuable injection risks. It overlaps substantially with 01-03 and needs more precise semantics for doctor’s requests, completion validation, and CSV types.

**Strengths**
- Doctor runs independent checks and distinguishes skipped dependent checks from failures.
- The CSV formula-injection mitigation preserves numeric negatives as a separate case.
- Completion is generated from the catalog and tested as a shell script, not just a string.
- The non-TTY regression suite directly addresses hangs in automation.
- Table output neutralizes terminal control characters.

**Concerns**
- **MEDIUM — Duplicate implementation with 01-03.** CSV, NDJSON, field selection, and associated tests are already assigned to Plan 01-03. Plan 01-05 should not re-own those files.
- **MEDIUM — Doctor may consume quota unnecessarily.** The checklist separately describes connectivity and authentication requests to `/usage`, plus rate-limit data from `/usage`. It does not say to reuse a single response, so doctor may make redundant calls.
- **MEDIUM — Missing config behavior is ambiguous.** A fresh CLI install may have no config directory or file yet. Doctor’s first check says the directory/file must exist, but does not define whether absence is an actionable failure or a normal “not configured” state.
- **MEDIUM — Completion validation is underspecified.** The threat model says paths and aliases are validated, but the validator’s described checks do not constrain shell-token characters or specify escaping for bash/zsh/fish.
- **MEDIUM — CSV typing is underspecified.** The plan requires prefixing text beginning with `-` but not numeric negatives. Without a defined column type or reliable way to distinguish a numeric value from a numeric-looking string, this behavior is ambiguous.
- **LOW — `--fields` behavior for nested data is unclear.** It is defined for columns or top-level object keys, but the exact projection behavior for nested hashes and heterogeneous records is not specified.

**Suggestions**
- Reconcile output ownership with Plan 01-03 and keep this plan focused on hardening, doctor, and completion.
- Reuse one `/usage` response for connectivity, authentication, scopes, and rate-limit checks; issue the accounts probe only when the prerequisites pass.
- Define missing config as either a normal unconfigured state or a specific actionable failure, and test it.
- Validate completion tokens against a conservative grammar or use shell-specific escaping; add malicious-catalog fixture cases.
- Add explicit numeric/text column typing for CSV formula protection.
- Specify whether field selection applies only to top-level keys or supports nested paths, and test mixed record shapes.

**Risk assessment: MEDIUM.** The user-facing surfaces are appropriate, but duplicate work and several underspecified edge cases could lead to inconsistent output and diagnostics.

## Cross-plan phase assessment

**Requirement coverage:** The five plans collectively address FOUND-01 through FOUND-10, AUTH-01 through AUTH-03/AUTH-08/AUTH-09, and SAFE-05/SAFE-06. The domain-read command is correctly deferred to Phase 2, with `sure api GET /api/v1/accounts` serving as the walking-skeleton proof.

**MVP fit:** The walking skeleton is genuinely demonstrated by the proposed end-to-end API smoke test. The implementation is broad for an MVP—especially catalog validation, three completion shells, multiple output formats, two keychain implementations, and detailed doctor checks—but these are explicitly required for Phase 1, so the scope is internally consistent rather than accidental.

**Highest-priority revisions before execution:**
1. Resolve the missing Ruby/Bundler toolchain path.
2. Close the AUTH-09 gap for arbitrary active keys, `Credential#inspect`, and raw response output.
3. Reconcile duplicate output ownership between Plans 01-03 and 01-05.
4. Tighten API path-prefix validation and define middleware/provider interfaces.
5. Minimize the new `/usage` user data and add the repository’s API consistency checklist.
6. Clarify doctor’s request reuse and behavior on a fresh, unconfigured install.

---

## Gemini 4 Argon Review

# Cross-AI Plan Review — Sure CLI Phase 1

---

## Plan 01-01: Gem Skeleton, Executable, Version, Help, Initial Operation Catalog

### 1. Summary
Plan 01-01 establishes the standalone `cli/` gem scaffold, executable entry point (`exe/sure`), Thor command tree, injectable runtime/runner boundary, D-13 exit-code error taxonomy, and machine-readable operation catalog (`cli/config/operations.yml`). It cleanly separates the CLI from the Rails runtime and removes the unapproved `pastel` gem in favor of root-locked dependencies, though a few Thor internals and gem-building sequencing details need tightening so tasks execute without friction.

### 2. Strengths
- **Strict supply-chain and dependency discipline (`01-01-T1`, T-01-SC):** Overrides `01-RESEARCH.md` to drop `pastel` and rely strictly on root-locked gems (`thor ~> 1.5.0`, `faraday ~> 2.14.3`, `faraday-retry ~> 2.3.2`, `terminal-table ~> 4.0.0`, `csv ~> 3.3.5`).
- **Process boundary & IO injection (`01-01-T2`):** `Sure.run` with `Sure::CLI::Runtime` and `Application.start(argv, debug: true)` + `exit_on_failure? = false` solves Thor's notorious exit-code-1 default early in Wave 1.
- **Catalog-first grammar enforcement (`01-01-T3`):** Encodes D-01 through D-04 into `Catalog::Validator` (e.g., forbidding `rm` aliases and requiring `risk: destructive` commands to end in `delete`, while exempting `sure api` via `risk: raw_write`).
- **Toolchain preflight (`01-01-T0`):** Explicitly catches the missing Ruby 3.4.9 / Bundler 2.6.7 environment gap identified in `01-RESEARCH.md` before any file edits happen.

### 3. Concerns
- **[HIGH] `gem build sure.gemspec` in `01-01-T1` references a missing file (`config/operations.yml`):**
  In `01-01-T1`, the action specifies: *"Use an explicit gemspec files allowlist: `exe/*`, `lib/**/*.rb`, `config/operations.yml`, `README.md`, `LICENSE`"*. However, `config/operations.yml` is not created until `01-01-T2`. If `sure.gemspec` lists `"config/operations.yml"` as a literal array element rather than a `Dir[...]` glob (or if `gem build` checks file existence), `gem build` in `01-01-T1`'s `<verify>` block will either fail with `Errno::ENOENT` or silently omit the file depending on whether `Dir[]` is used.
- **[MEDIUM] Thor `help` and subcommand routing ignore `runtime.stdout` unless Thor's shell io is overridden (`01-01-T2`):**
  `01-01-T2` states that `test/commands/version_help_test.rb` asserts `sure help` and `sure help auth login` using *injected StringIO streams* (`Runtime`). However, Thor's built-in `help` command writes to `shell.stdout` (`$stdout`), not `Sure::CLI::Runtime.current.stdout`. Unless a custom Thor shell or `Base#shell` bridges to `Runtime.current.stdout`/`stderr`, assertions on the injected StringIO for `help` will capture empty strings.
- **[MEDIUM] Thor `subcommand "doctor"` and `subcommand "completion"` mismatch with leaf command invocation (`01-01-T2`, `01-01-T3`):**
  In `01-01-T2`, `Application` registers `subcommand "doctor", Sure::CLI::Commands::Doctor` and `subcommand "completion", Sure::CLI::Commands::Completion` where `Doctor` declares `run` and `Completion` declares `SHELL`. In Thor, `subcommand` mounts a nested `Thor` class (which would expect `sure doctor run` or `sure completion bash` where `bash` is a subcommand task name, not a `SHELL` argument!). Yet `01-01-T3` says *"(`auth`, `doctor` is a leaf, `completion` is a leaf)"* and requirements specify `sure doctor` and `sure completion bash`. Mounting `doctor` and `completion` as `subcommand` classes instead of top-level commands on `Application` (or without `default_task` / argument delegation) will break `sure doctor` and `sure completion zsh`.
- **[LOW] Redaction of forbidden `--api-key` value not yet wired in `01-01-T2`:**
  If a user runs `sure auth login --api-key=secret123` in Wave 1, Thor's `UnknownArgumentError` message includes `"--api-key=secret123"`, echoing the secret to stderr before `Sure::Redactor` arrives in Plan 01-03.

### 4. Suggestions
- **Define `doctor` and `completion` as top-level `Application` commands (delegating to `Commands::Doctor` / `Commands::Completion` service/command objects) rather than Thor `subcommand` classes**, or explicitly specify how Thor dispatches `sure doctor` (no subcommand verb) and `sure completion SHELL` (where `SHELL` is a positional argument, not a subcommand).
- **Bridge Thor's shell to `Runtime.current` in `Sure::CLI::Base`:** Override `shell` (or pass a custom `Thor::Shell::Basic` subclass backed by `Runtime.current.stdout` and `Runtime.current.stderr` into `Application.start(argv, debug: true, shell: ...)`). This guarantees `sure help` writes to injected `StringIO` in tests.
- **Create a minimal `cli/config/operations.yml` stub in `01-01-T1` or use `Dir[...]` in `sure.gemspec`** so `gem build` in `01-01-T1` is deterministic.

### 5. Risk Assessment
**Overall Risk: MEDIUM.** The Thor subcommand vs. leaf command dispatch for `doctor` and `completion`, plus Thor's internal `$stdout` usage during `help`, are classic Thor traps that will cause `01-01-T2` tests to fail if the executor follows the prompt literally.

---

## Plan 01-02: Config, Named Profiles, Server URL/Path/TLS Handling, Precedence

### 1. Summary
Plan 01-02 implements XDG/Windows path resolution, strict YAML config loading, atomic `0600` file writes with symlink/ownership checks, flag > env > profile > default precedence resolution, prefix-preserving URL construction, and the `SURE_API_KEY` / store credential provider contract. It is security-conscious and well-scoped.

### 2. Strengths
- **Prefix-preserving `HTTP::UrlBuilder` (`01-02-T2`):** Directly prevents Pitfall 4 (`URI.join` stripping `/sure` when joining `/api/v1/...`) and forbids userinfo, query strings, and fragments on the base URL.
- **Hardened file hygiene (`01-02-T1`, T-02-01):** `Config::AtomicFile` enforces `0700` directories, `0600` files, `File.lstat` symlink refusal, `Process.euid` ownership checks, and `Tempfile` + `fsync` + `rename`.
- **Clean decoupling of `NullStore` (`01-02-T3`):** Introducing `Auth::Credential`, `Auth::CredentialKey`, `Auth::Store`, and `Auth::NullStore` in Wave 2 allows Wave 3 (`sure api` with `SURE_API_KEY`) to function cleanly before Wave 4 builds the OS keychain stores.

### 3. Concerns
- **[MEDIUM] Relative `--ca-bundle` path resolution ambiguity (`01-02-T2`):**
  `01-RESEARCH.md` (Pitfall 5) explicitly requires: *"resolve profile-relative CA paths against the config directory and flag-relative paths against cwd; validate readability before the request"*. `01-02-T2` does not specify this path expansion or readability check in its `<action>` or `<acceptance_criteria>`, risking a cryptic OpenSSL error (exit 8 instead of exit 2) when a user passes a missing or relative `--ca-bundle`.
- **[MEDIUM] Windows `Process.euid` and POSIX permission behavior (`01-02-T1`):**
  `01-02-T1` mandates: *"refuse group/world-readable files and files not owned by `Process.euid`"*. On Windows (`Gem.win_platform?`), `File.stat.mode & 0o077` and `Process.euid` do not behave like POSIX. While `01-RESEARCH.md` notes Windows should skip POSIX `0600` checks, `01-02-T1` omits the ` unless Gem.win_platform?` guard.
- **[LOW] Server URL ending in `/api/v1` (`01-02-T2`):**
  `01-RESEARCH.md` (Pitfall 4) notes *"do not accept a server URL ending in `/api/v1`"* (a very common user mistake that produces `/api/v1/api/v1/accounts`). `01-02-T2` does not include this check in `UrlBuilder`.

### 4. Suggestions
- **Add `/api/v1` base-URL rejection to `01-02-T2`:** Have `HTTP::UrlBuilder` reject (or strip with a clear error) base URLs whose path ends in `/api` or `/api/v1`, exiting 2 with a message to pass the server base URL without `/api/v1`.
- **Specify CA bundle path expansion and readability check in `01-02-T2`:** Expand `--ca-bundle` / `SURE_CA_BUNDLE` relative to `runtime.cwd`, expand profile `ca_bundle` relative to the config directory, and verify `File.readable?` (raising `UsageError` exit 2 if unreadable).
- **Guard POSIX permission/ownership checks with `unless Gem.win_platform?` in `01-02-T1`.**

### 5. Risk Assessment
**Overall Risk: LOW.** The interfaces are crisp, dependencies on 01-01 are accurate, and test cases are isolated and fast.

---

## Plan 01-03: Faraday Pipeline, Output Contract, `sure api`, Error Mapping, Exit Codes, Redaction, Pagination Base

### 1. Summary
Plan 01-03 delivers the core HTTP request pipeline, Faraday middleware, secret redactor, exit-code mapper, output envelope/formatters, pagination normalizer, and the `sure api` escape hatch, verified against a local `TCPServer` smoke test. It proves the walking skeleton end-to-end, though there is file duplication with Plan 01-05 and a missing TTY confirmation path in `sure api`.

### 2. Strengths
- **Defense-in-depth secret protection (`01-03-T1`, T-03-01):** Combines `f.response :raise_error, include_request: false`, zero Faraday logging middleware, header/token/64-hex regex scrubbing in `Sure::Redactor`, and redirect refusal (`3xx` → `NetworkError` exit 8 so `X-Api-Key` is never forwarded across origins).
- **Safe retry semantics (`01-03-T1`, T-03-02):** Overrides `faraday-retry`'s dangerous default (`DELETE`/`PUT`) with `methods: %i[get head]`, caps `Retry-After` / `X-RateLimit-Reset` waits at `max_interval: 10`, and treats Sure's reset header as seconds remaining rather than an epoch.
- **Self-hosted `Float::INFINITY` handling (`01-03-T1`, `01-03-T2`):** Parses JSON with `allow_nan: true` and normalizes non-finite numbers to `null` with a `meta.warnings` entry so self-hosted `NoopApiRateLimiter` responses don't break `jq`.

### 3. Concerns
- **[HIGH] Overlap and duplication between `01-03-T2` and `01-05-T1` on `Csv`, `Ndjson`, and `FieldSelection`:**
  `01-03-T2` creates `output/csv.rb`, `output/ndjson.rb`, `output/field_selection.rb`, `test/unit/output/formatters_test.rb`, and `test/unit/output/field_selection_test.rb` and requires full CSV/NDJSON/field-projection passing criteria. Then `01-05-T1` ("Add CSV, NDJSON, field selection, and terminal-safety rules") lists the *exact same 6 production files and 2 test files* in `files_modified` to add CSV formula-injection protection and terminal control-character escaping. Having Wave 3 build 80% of Wave 5's deliverables creates unclear boundaries and wasted rework.
- **[MEDIUM] Missing interactive TTY confirmation when `--yes` is omitted on `sure api` writes (`01-03-T3`):**
  `01-CONTEXT.md` (Discretion) and `01-RESEARCH.md` (Pitfall 2 / Pitfall 12) specify that on a TTY without `--yes`, `sure api DELETE/POST/PUT/PATCH` should prompt for confirmation (`y/N` on stderr, reading `runtime.stdin.gets`) and exit 2 if declined, whereas on non-TTY without `--yes` it must fail immediately with exit 2. `01-03-T3` says: *"Write methods (`POST PUT PATCH DELETE`) require `--yes` on a TTY; when stdin is not a TTY and `--yes` is absent, exit 2"*. This conflates TTY prompting with requiring `--yes` unconditionally, which contradicts `01-RESEARCH.md` ("`sure api DELETE` + fake TTY + `n` → exit 2, no request").
- **[MEDIUM] Error output contract on stderr when `--json` or piped (`01-03-T1`, `01-03-T2`):**
  `01-RESEARCH.md` states: *"Errors go to stderr as `{"error":"...","message":"...","details":{},"request_id":"...","exit_code":3}` in machine mode, or a concise human line otherwise."* Neither `01-01-T2` (`Runner`) nor `01-03-T1` (`Mapper`) specifies how `Runner#render_error` switches between human one-liner and JSON error object on stderr, or ensures `Sure::Redactor` is wired into `Runner#render_error` (which was created in `01-01-T2` before `Redactor` existed).
- **[LOW] `Output::Table` and arbitrary JSON objects from `sure api` (`01-03-T2`, `01-03-T3`):**
  When a user runs `sure api GET /api/v1/accounts` on a TTY (defaulting to `:table`), `Commands::Api` passes the parsed response body (`{"accounts" => [...], "pagination" => {...}}`) as `Result#data` with no predefined `Result#columns`. `01-03-T2` does not specify how `Output::Table` derives columns when `Result#columns` is `nil` or when `data` is a nested Hash/Array from `sure api`.

### 4. Suggestions
- **Specify dynamic column inference in `Output::Table` (`01-03-T2`):** When `Result#columns` is `nil` (as in `sure api`), if `data` matches a known collection envelope (`HTTP::Envelope`), unwrap the rows and infer columns from the first Hash's keys (or render a 2-column `key | value` table for a single Hash).
- **Update `Sure::CLI::Runner` in `01-03-T1`:** Add `cli/lib/sure/cli/runner.rb` to `01-03-T1`'s `files_modified` so `Runner#render_error` and `Runner#render_usage_error` pass all messages through `Sure::Redactor.redact_value`.
- **Clarify TTY vs. non-TTY write confirmation on `sure api` (`01-03-T3`):** Either explicitly prompt `[y/N]` on stderr when `runtime.stdin.tty?` is true and `--yes` is false, or explicitly document that `sure api` always requires `--yes` even on a TTY (and align `01-05-T3` tests accordingly).
- **Consolidate or clearly split `01-03-T2` and `01-05-T1`:** Either put CSV formula-escaping and table control-char sanitization directly into `01-03-T2` (freeing `01-05` to focus on `doctor`, `completion`, and `non_tty_test`), or keep `01-03-T2` to `Json` + `Table` and introduce `Csv`, `Ndjson`, and `FieldSelection` once in `01-05-T1`.

### 5. Risk Assessment
**Overall Risk: MEDIUM.** The core Faraday pipeline is rock-solid, but `sure api GET /api/v1/accounts` on a TTY will fail or render garbage in `Output::Table` unless generic Hash/Array table rendering is specified for `Result` objects that lack static `Column` definitions.

---

## Plan 01-04: API-Key Credential Store (Keychain + File Fallback) and Auth Commands

### 1. Summary
Plan 01-04 implements OS keychain storage (`security` on macOS, `secret-tool` on Linux), the `0600` locked `FileStore` fallback, `sure auth login|status|logout`, `Auth::ScopePreflight` for write commands, and the additive `user` object on `GET /api/v1/usage`. It thoroughly addresses the credential lifecycle and closes the `AUTH-03` server contract gap identified during research.

### 2. Strengths
- **Validation-before-storage with rollback (`01-04-T2`, T-04-03):** `Auth::Login` probes `GET /api/v1/usage` with an ephemeral provider before touching the keychain or `config.yml`, and rolls back the credential if the `config.yml` write fails.
- **Subprocess secret isolation (`01-04-T1`, T-04-02):** `Auth::CommandRunner` scrubs `SURE_API_KEY` and token env vars, passes secrets exclusively via `stdin_data` to `Open3.capture3`, enforces a 2-second timeout, and verifies macOS `security` writes via read-back before trusting the keychain.
- **Truthful `AUTH-03` resolution (`01-04-T3`):** Adds `user: { id, email, first_name, last_name }` to the `:api_key` branch of `Api::V1::UsageController#show` with Minitest and rswag specs while keeping the CLI tolerant of older servers (`user: null` + warning).

### 3. Concerns
- **[HIGH] Rails test and rswag verification in `01-04-T3` may be blocked by environment constraints:**
  In `01-01-T0` and `01-RESEARCH.md`, the environment has no Ruby provisioned initially, and even once Ruby is available, running `bin/rails test test/controllers/api/v1/usage_controller_test.rb` and `RAILS_ENV=test bundle exec rake rswag:specs:swaggerize` requires a running PostgreSQL (and potentially Redis) instance with the test database migrated. `AGENTS.md` forbids running migrations automatically. While `01-04-T3` includes a fallback note for `rswag`, it does *not* include a fallback if `bin/rails test` in `<verify>` cannot connect to Postgres, which would block Wave 4 completion.
- **[MEDIUM] `UsageController#show` user payload in `01-04-T3` vs. `01-RESEARCH.md`:**
  `01-04-T3` specifies `{ id:, email:, first_name:, last_name: }`, whereas `01-RESEARCH.md` (and `mobile_user_payload` in `auth_controller.rb:489-494`) uses `{ id:, email:, first_name:, last_name: }`. However, in `01-04-T2`, the status output specification and `cli/test/fixtures/api/usage.json` (first created in `01-03-T3`!) must match. Because `cli/test/fixtures/api/usage.json` is created in `01-03-T3` and modified again in `01-04-T2` and `01-04-T3`, if `01-03-T3` creates `usage.json` without `user`, `01-04-T2` and `01-04-T3` should stay synchronized.
- **[MEDIUM] `IO#getpass` interaction with injected `FakeTTY` (`01-04-T2`):**
  In Ruby's `io/console`, `stdin.getpass` writes the prompt directly to the C-level console/controlling terminal or `stderr`, not necessarily to an injected `FakeTTY` stdout/stderr unless `Auth::Login` calls a method on `runtime.stdin` (e.g., writes the prompt to `runtime.stderr.print` and calls `runtime.stdin.noecho(&:gets)` or `runtime.stdin.getpass` when `respond_to?(:getpass)`). If `Auth::Login` calls `$stdin.getpass("API key: ")`, it will bypass `runtime.stdin` and hang in tests!
- **[LOW] `FileStore` lockfile permissions and Windows `flock` (`01-04-T1`):**
  `File.open(lock_file, File::RDWR | File::CREAT, 0o600)` with `flock(File::LOCK_EX)` works on POSIX, but should ensure the lockfile itself is created with `0600` and `flock` is always released in an `ensure` block.

### 4. Suggestions
- **Specify exact hidden-prompt mechanics on `runtime.stdin` in `01-04-T2`:** Instruct `Auth::Login` to print the prompt to `runtime.stderr` and read the secret via `runtime.stdin.respond_to?(:getpass) ? runtime.stdin.getpass : runtime.stdin.noecho(&:gets)`, ensuring `FakeTTY` in tests is 100% deterministic and never touches `/dev/tty`.
- **Include `user` in `cli/test/fixtures/api/usage.json` from the start (`01-03-T3`)** and add a separate fixture `usage_legacy_no_user.json` in `01-04-T2` to test the `user: null` + warning fallback.
- **Extend the environment-blocker handling in `01-04-T3` to cover `bin/rails test` if PostgreSQL is unreachable** in the execution environment, so the executor knows how to handle a missing test DB without violating `AGENTS.md` ("do not automatically run migrations").

### 5. Risk Assessment
**Overall Risk: MEDIUM.** The `IO#getpass` `/dev/tty` behavior in Ruby's `io/console` is a frequent cause of hung test suites if not routed through `runtime.stdin`, and `01-04-T3` crosses from the standalone `cli/` gem into the Rails server test suite.

---

## Plan 01-05: `sure doctor`, Shell Completion, Output Hardening (CSV/NDJSON/Fields, Non-TTY Safety)

### 1. Summary
Plan 01-05 completes Phase 1 with output hardening (CSV formula injection defense, terminal escape sanitization, field selection), the 9-step non-short-circuiting `sure doctor` command, static shell completion generation (`bash`, `zsh`, `fish`), and a dedicated non-TTY safety regression suite (`SAFE-05`).

### 2. Strengths
- **Non-short-circuiting `Doctor::Runner` with prerequisite skipping (`01-05-T2`):** Runs all independent checks, marks dependent checks as `SKIP` rather than cascading false failures when credentials or connectivity are missing, and returns the first failed check's D-13 exit code.
- **Nuanced CSV injection mitigation (`01-05-T1`, T-05-01):** Specifically protects negative numbers (`-12.34`) from being corrupted into `'-12.34` while still single-quote prefixing non-numeric text cells starting with `=`, `+`, `-`, or `@`.
- **macOS `/bin/bash` 3.2 compatibility (`01-05-T3`):** Explicitly forbids Bash 4+ features (`declare -A`, `mapfile`) and verifies the generated script with `bash -n`.

### 3. Concerns
- **[MEDIUM] `Doctor` connectivity check (#4) vs. `HTTP::Client` retry and error raising (`01-05-T2`):**
  In `01-05-T2`, Check 4 ("Connectivity/TLS via `GET /api/v1/usage`: 200/401/403 prove reachability; 404/5xx/TLS failure fails") and Check 8 ("Clock skew from the HTTP `Date` header") need the HTTP response headers (`Date`) and status code even when `/api/v1/usage` returns `401` or `403`. However, in `01-03-T1`, `HTTP::Client#request` raises `Sure::Errors::AuthenticationError` on 401/403 (via Faraday's `raise_error` middleware), which discards the `HTTP::Response` object unless `Sure::Errors::Error` preserves `status` and `headers` (or `HTTP::Client` exposes a raw probe / attaches `response` to `Sure::Errors::Error`).
- **[MEDIUM] Redundant work with `01-03-T2` (`01-05-T1`):**
  As noted in the Plan 01-03 review, `01-05-T1` re-specifies creating `Output::Csv`, `Output::Ndjson`, and `Output::FieldSelection` which were already created in `01-03-T2`.
- **[LOW] `sure doctor` when `config.yml` or `--server` is missing (`01-05-T2`):**
  If a user runs `sure doctor` before ever logging in or configuring a server, `Sure::CLI::Context#profile` (from `01-02-T2`) immediately raises `UsageError` ("missing server") before `Doctor::Runner` even starts Check 1! `Commands::Doctor` must construct `Doctor::Runner` without forcing eager `Context#profile` / `Context#api_key` resolution, so Check 1 (config file permissions), Check 2 (server URL), and Check 3 (credential presence) can run and report `FAIL` / `SKIP` cleanly in the doctor checklist.

### 4. Suggestions
- **Ensure `Commands::Doctor` does not eagerly call `context.profile` or `context.client` before starting `Doctor::Runner` (`01-05-T2`):** Have `Doctor::Runner` invoke `Config::Loader`, `Config::Resolver`, and `Auth::ApiKeyProvider` inside Checks 1–3, catching `Sure::Errors::Error` to record structured `Doctor::Result` failures (`status: :fail`, `fix: ...`) and skipping downstream checks.
- **Attach `http_status` and `headers` (or `date_header`) to `Sure::Errors::Error` in `Errors::Mapper` (`01-03-T1` / `01-05-T2`)** so `Doctor::Runner` can still mark Check 4 (Connectivity/TLS) as `PASS` and Check 8 (Clock skew) from the `Date` header when `/api/v1/usage` returns 401 or 403.

### 5. Risk Assessment
**Overall Risk: MEDIUM.** The interaction between `Doctor::Runner` and exceptions raised by `Config::Resolver` / `HTTP::Client` (especially on missing server config or 401 responses) is the main integration hazard in Wave 5.

---

## Cross-Plan & Phase-Level Assessment

### Requirement Coverage (All 17 Phase 1 Requirements)
| Requirement | Covered By | Assessment |
|---|---|---|
| **FOUND-01** (Gem install & `sure` executable) | 01-01-T0, 01-01-T1 | Complete. Temp `GEM_HOME` smoke test included. |
| **FOUND-02** (`--version`, `help`, examples) | 01-01-T2, 01-01-T3 | Complete (needs Thor shell stdout bridge for StringIO tests). |
| **FOUND-03** (Named profiles & precedence) | 01-02-T1, 01-02-T2 | Complete. |
| **FOUND-04** (Path prefix, CA bundle, `--insecure`) | 01-02-T2, 01-03-T1 | Complete (add relative CA path check). |
| **FOUND-05** (TTY tables vs. piped JSON) | 01-03-T2, 01-05-T1 | Complete. |
| **FOUND-06** (`--json`, `--csv`, `--ndjson`, `--fields`) | 01-03-T2, 01-05-T1 | Complete (deduplicate between 01-03 and 01-05). |
| **FOUND-07** (Exit codes 0–9, stderr errors, no backtraces) | 01-01-T2, 01-03-T1 | Complete. |
| **FOUND-08** (`sure doctor` checklist) | 01-05-T2 | Complete (ensure non-raising config/401 handling). |
| **FOUND-09** (`sure api METHOD PATH`) | 01-03-T3 | Complete. |
| **FOUND-10** (`bash`, `zsh`, `fish` completion) | 01-05-T3 | Complete. |
| **AUTH-01** (`auth login` prompt, file, stdin) | 01-04-T2 | Complete. |
| **AUTH-02** (OS keychain + `0600` file fallback + warning) | 01-04-T1, 01-04-T2 | Complete. |
| **AUTH-03** (`auth status` with user, scopes, rate limit) | 01-04-T2, 01-04-T3 | Complete (includes additive server `user` field). |
| **AUTH-08** (`SURE_API_KEY` env without persistence) | 01-02-T3, 01-04-T2 | Complete. |
| **AUTH-09** (Zero secret leakage in logs/errors/output) | 01-03-T1, 01-04-T1 | Complete. |
| **SAFE-05** (Never prompt when stdin is not a TTY) | 01-03-T3, 01-04-T2, 01-05-T3 | Complete. |
| **SAFE-06** (Write commands preflight `read_write` scope) | 01-04-T2 | Complete. |

### Walking Skeleton & MVP Alignment
- **Genuinely satisfied:** By the end of Wave 3 (`01-03`), a user can run `SURE_API_KEY=... sure api GET /api/v1/accounts` through the real Faraday pipeline, and Wave 4 (`01-04`) adds persistent login. Domain commands (`accounts list`, `transactions add`) are properly kept out of Phase 1 runtime code and represented only as `status: planned` catalog entries.
- **No scope creep:** Removing `pastel` in `01-01-T1` in favor of a tiny stdlib ANSI helper and using stdlib `TCPServer` instead of `webrick` keeps the runtime footprint minimal.

### Top 5 Actionable Fixes Before Execution
1. **`01-01-T2`:** Define `doctor` and `completion` as top-level commands on `Sure::CLI::Application` (not Thor `subcommand` classes, which would require `sure doctor run`) and wire a custom Thor shell to `Runtime.current.stdout`/`stderr` so `help` output is captured in StringIO tests.
2. **`01-01-T1`:** Either create a minimal `cli/config/operations.yml` in Task 1 or ensure `sure.gemspec` uses `Dir[...]` so `gem build sure.gemspec` in Task 1 does not fail before Task 2 creates the file.
3. **`01-03-T2` & `01-05-T1`:** Deduplicate the `Output::Csv`, `Output::Ndjson`, and `Output::FieldSelection` tasks — put the CSV formula-escaping and table control-character escaping directly into `01-03-T2` or defer those three classes cleanly to `01-05-T1`.
4. **`01-04-T2`:** Specify that `Auth::Login` reads hidden prompts through `runtime.stdin` (`noecho` / stubbable `getpass`) and prints prompts to `runtime.stderr`, never calling global `$stdin.getpass` which accesses `/dev/tty` directly.
5. **`01-05-T2`:** Ensure `Doctor::Runner` catches `UsageError` from missing config/server in Checks 1–2 and inspects HTTP status/headers on 401/403 responses in Checks 4 & 8 rather than letting `Context` or `HTTP::Client` abort the checklist early.

---

## Consensus Summary

### Agreed Strengths

- The plans are unusually security-conscious: one Faraday pipeline, `include_request: false`, no logger middleware, GET/HEAD-only retries, redirect refusal, and explicit redaction.
- The CLI is cleanly separated from Rails, uses only root-locked gems, and drops `pastel` in favor of a small stdlib ANSI helper.
- The walking skeleton is genuinely proven end-to-end by Wave 3 with a real local `TCPServer` request through `sure api`, while domain commands stay deferred to Phase 2.
- Credential handling validates before persisting, rolls back a failed config write, verifies macOS keychain writes, and falls back to an atomic `0600` file with a one-time warning.
- Doctor is non-short-circuiting, completion is catalog-driven, and CSV formula protection preserves numeric negatives.
- All 17 Phase 1 requirements are mapped to plans, and the deliberate roadmap reconciliations (no `--api-key` argv flag, `sure api` instead of `accounts list`) are documented.

### Agreed Concerns (highest priority)

1. **AUTH-09 redaction is not closed (HIGH).** `Auth::Credential` is a `Data` value whose default `inspect` includes `secret`; the redactor only masks 64-hex key shapes, so a non-64-hex active key echoed by the server may leak; `--raw` can print a response body containing a key; and `Runner#render_error` was created before `Redactor` existed. Thor's unknown-option error can also echo `--api-key=...` in Wave 1 before redaction lands.
2. **Output ownership is duplicated (HIGH/MEDIUM).** `01-03-T2` creates `Csv`, `Ndjson`, and `FieldSelection` and their tests, then `01-05-T1` re-owns the same files. This creates rework and unclear completion criteria.
3. **Thor dispatch and shell IO need an explicit contract (HIGH/MEDIUM).** Mounting `doctor` and `completion` as `subcommand` classes would require `sure doctor run` or treat `bash` as a subcommand; Thor's built-in `help` writes to the global shell, not the injected `Runtime` streams, so StringIO help tests may capture nothing.
4. **Doctor can abort before it diagnoses (MEDIUM).** `Commands::Doctor` must not eagerly resolve `Context#profile`/`#client`; a missing server or config would raise before Check 1. On 401/403, `raise_error` discards the response status/headers needed for connectivity and clock-skew checks unless `Errors::Error` preserves them.
5. **Toolchain and Rails test provisioning are unresolved (HIGH).** Ruby 3.4.9/Bundler 2.6.7 are absent on the planning host and the devcontainer path is unconfirmed. `01-04-T3` needs a migrated PostgreSQL test database and rswag regeneration; AGENTS.md forbids automatic migrations.
6. **`sure api` semantics need one decision (MEDIUM).** Clarify whether a TTY write prompts `[y/N]` or always requires `--yes`; tighten the path boundary to exactly `/api/v1` or `/api/v1/` (reject `/api/v10`); define table rendering for arbitrary JSON payloads with no static columns.
7. **Config/credential filesystem edges remain (MEDIUM).** Specify relative CA-bundle resolution and readability, Windows guards for POSIX permission checks, config read-modify-write locking, lockfile permission/race handling, and the keychain→file fallback state table.
8. **Hidden-prompt injection (MEDIUM).** `Auth::Login` must print through `runtime.stderr` and read through `runtime.stdin` (`getpass`/`noecho`), never `$stdin.getpass`, or the FakeTTY test can hang on `/dev/tty`.

### Divergent Views

- **User payload size:** GPT-6 Luna recommends omitting `id` from the additive `/usage` user object as unnecessary personal data; Gemini 4 Argon accepts the shape because it matches the existing `mobile_user_payload`. The user already approved the additive field; minimize to `email`, `first_name`, `last_name` unless a consumer needs `id`.
- **Overall risk:** GPT-6 Luna rates `01-02` and `01-03` HIGH; Gemini 4 Argon rates the same plans LOW/MEDIUM. Both converge on the same concrete fixes, so treat the severity difference as calibration, not disagreement.
- **Catalog sequencing:** GPT-6 Luna flags the Task 2 minimal-catalog → Task 3 expanded-catalog handoff as a drift risk; Gemini 4 Argon accepts it.

### Recommended Replan Priorities

1. Close AUTH-09: redact the active credential by value in every path, override `Credential#inspect`/`#to_s`, require explicit `--raw` acknowledgement/redaction, wire `Redactor` into `Runner`, and prevent Thor from echoing rejected `--api-key` values.
2. Fix Thor dispatch: make `doctor` and `completion` top-level commands (or define `default_task`/argument delegation), and bridge Thor's shell to injected `Runtime` stdout/stderr.
3. Deduplicate output work: either finish CSV/NDJSON/fields in `01-03` and make `01-05` hardening-only, or keep `01-03` to JSON/table and move all three formatters to `01-05`.
4. Make Doctor non-raising: build checks from `Config::Loader`/`Resolver`/`ApiKeyProvider` directly, preserve HTTP status and headers on errors, reuse one `/usage` response, and define the fresh-install state.
5. Add a concrete toolchain/DB provisioning step (devcontainer or Ruby 3.4.9 + Postgres/Redis), or mark the Rails test/rswag task as a blocking human checkpoint with an explicit fallback.
6. Tighten `sure api`: exact `/api/v1` boundary, TTY prompt vs `--yes` decision, and dynamic table inference for arbitrary payloads.
7. Harden config/credential filesystem details: CA path resolution/readability, Windows guards, config locking, lockfile races, and fallback state transitions.
