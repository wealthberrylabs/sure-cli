# Stack Research

**Domain:** First-party Ruby CLI for a self-hosted Rails JSON API (Sure `/api/v1`)
**Researched:** 2026-10-31
**Confidence:** HIGH for core runtime, HTTP, testing, and release; MEDIUM for cross-platform OS keychain and Homebrew packaging

Scope: a separate gem under `cli/`, Ruby 3.4.9, no Rails runtime dependency, 110 documented operations, API key first and OAuth loopback second. Versions below were checked against RubyGems and upstream sources on 2026-10-31. Confidence marks: HIGH = version and API verified; MEDIUM = version verified but platform/packaging risk.

## Recommended Stack

### Core Technologies

| Technology | Version | Purpose | Why Recommended |
|------------|---------|---------|-----------------|
| Ruby | 3.4.9 | Runtime | Matches `.ruby-version` and the Sure server; one toolchain, current Prism/YJIT, no cross-runtime matrix. **HIGH** |
| Thor | 1.5.0 | CLI framework | Nested commands, class options, aliases, hidden commands, enum validation, generated help. Rails/Bundler pedigree; pure Ruby; `>= 2.6` Ruby. **HIGH** |
| Faraday | 2.15.1 | HTTP transport | Middleware pipeline (JSON, auth, redaction, retry), `net_http` adapter, no native extensions. Already the server's HTTP convention. **HIGH** |
| faraday-retry | 2.4.0 | Retries | Mature retry middleware; handles `Retry-After` and `RateLimit-Reset` with 429. Restrict methods to keep writes safe. **HIGH** |
| oauth2 | 2.1.0 | OAuth token exchange/refresh | Small, spec-faithful OAuth 2.0/2.1 client; supports public clients with `auth_scheme: :request_body` and nil secret. PKCE is still application code. **MEDIUM-HIGH** |
| webrick | 1.9.2 | Loopback callback server | Pure-Ruby HTTP server for `127.0.0.1` callback; no Rack/Puma needed. Removed from stdlib since Ruby 3.0, so declare it. **HIGH** |
| terminal-table | 4.0.0 | Human-readable tables | Maintained (2025), Unicode width via `unicode-display_width 3.3.0`, simple alignment/truncation. **HIGH** |
| pastel | 0.8.0 | Terminal color | Tiny, stable, explicit enable/disable; wrap with `NO_COLOR` and TTY detection. **HIGH** |
| csv | 3.3.7 | CSV output | Bundled gem in Ruby 3.4 (not a default gem); declare `~> 3.3` and stream large exports. **HIGH** |
| json | stdlib | Machine output | Stable serialization; define an explicit serializer instead of dumping arbitrary hashes. **HIGH** |

### Supporting Libraries

| Library | Version | Purpose | When to Use |
|---------|---------|---------|-------------|
| launchy | 3.1.1 | Open the browser for OAuth | OAuth login on macOS/Linux/WSL; print the URL as a fallback for headless/SSH. |
| tty-spinner | 0.9.3 | Progress indicator | Only for long sync/import/chat polling on a TTY; write to `$stderr`, never stdout. Optional. |
| io-console | stdlib | Hidden secret input | API key and confirmation prompts via `IO#getpass`; no prompt framework needed. |
| securerandom / digest / openssl | stdlib | PKCE and state | Generate verifier/challenge and CSRF `state`; use `pack("m0")` to avoid a `base64` dependency. |
| zeitwerk | 2.8.3 | Autoloading | Optional, but useful once command/resource files exceed ~20; lazy-load so `sure --version` stays fast. |
| base64 | 0.3.0 | Only if needed | Ruby 3.4 promoted it to a bundled gem; prefer `Array#pack("m0")` instead of adding it. |

### Development Tools

| Tool | Version | Purpose | Notes |
|------|---------|---------|-------|
| Minitest | 6.0.6 | Tests | Repo standard. Requires Ruby >= 3.2. Minitest 6 is breaking: no `minitest/mock`, plugins are opt-in; require `minitest/autorun` in `test_helper.rb`. |
| WebMock | 3.34.0 | HTTP stubbing | Assert `X-Api-Key`, query params, retry counts, and timeout behavior at the HTTP layer. |
| VCR | 6.4.1 | Recorded API fixtures | Use sparingly for a few real flows; filter `Authorization`, `X-Api-Key`, tokens, and request bodies. |
| faraday-openapi | 0.8.3 | Client contract validation | Register `docs/api/openapi.yaml` and validate requests/responses in tests; disable in production. |
| Rake | 13.4.2 | Task runner | `test`, `lint`, `contract`, `catalog`, `release` tasks under `cli/`. |
| RuboCop | 1.92.2 | Lint/format | Repo consistency via `rubocop-rails-omakase` 1.1.0; add `rubocop-minitest` 0.41.0 optionally. |
| Bundler | 4.0.23 | Dependencies and release | Use `Bundler::GemHelper.tag_prefix = "cli-"` so the monorepo tag is `cli-vX.Y.Z`. |
| SimpleCov | 1.3.2 | Coverage | Optional; enforce a floor on `lib/sure/http`, `auth`, and `resources`. |
| bundler-audit | 0.9.3 | CVE scan | Optional CI job; Brakeman is not meaningful for a non-Rails client. |
| rubygems/release-gem | v1 | Trusted publishing | OIDC, no long-lived RubyGems token; use `working-directory: cli`. |
| Tebako | 0.15.9 | Standalone binaries | Optional release tool for macOS/Linux Homebrew assets; not needed for the gem or container. |
| completely | 0.8.0 | Bash completion generation | Bash only, so generate zsh/fish from the catalog or keep small templates. |

## Installation

```bash
cd cli
bundle install                 # isolated Gemfile, not the Rails bundle
bundle exec rake test
bundle exec rubocop
gem build sure.gemspec
```

Runtime dependencies in `sure.gemspec`: `thor ~> 1.5`, `faraday ~> 2.15`, `faraday-retry ~> 2.4`, `terminal-table ~> 4.0`, `pastel ~> 0.8`, `oauth2 ~> 2.1`, `webrick ~> 1.9`, `launchy ~> 3.1`, `csv ~> 3.3`. Keep development dependencies in the gemspec or `cli/Gemfile`; do not add any of these to the root Rails bundle.

## Decision Details

### CLI framework

- Thor 1.5.0, one command class per resource (`Accounts`, `Transactions`, …), nested via `subcommand`, with `class_option` for `--profile`, `--server`, `--json`, `--csv`, `--no-color`, `--yes`, `--dry-run`.
- Override `self.exit_on_failure?` to return true and map `Thor::Error` to exit code 2. Never let a Ruby backtrace reach the user; catch at the executable boundary.
- Commands stay thin: argv → params → one resource/operation call → one presenter. No HTTP, retries, or formatting inside commands.
- Drive help, completion, and the web catalog from the same `config/operations.yml`; Thor itself has no completion module, so generate scripts at build time.

### HTTP, retries, and pagination

- One Faraday connection per profile: `request :json`, `request :retry`, `response :raise_error`, plus auth/redaction middleware. Open timeout 5s, read timeout 30s (300s for streamed exports).
- `X-Api-Key` goes in the header only, never a query parameter or argv. OAuth uses `Authorization: Bearer`.
- Retry policy: `max: 2`, `interval: 0.5`, `backoff_factor: 2`, `retry_statuses: [429, 502, 503, 504]`, `methods: %i[get head]`, `rate_limit_reset_header: "X-RateLimit-Reset"`. Sure sends seconds remaining, not an epoch; self-hosted may omit the headers entirely. Honor `Retry-After`, cap the wait, and map 429 to exit 8.
- Do not retry POST/DELETE by default. Import chunks carry `client_chunk_id`; sync is single-flight. A retried write must be explicitly opt-in and idempotent.
- Pagination has two envelopes: `{accounts: [...], pagination: {page, per_page, total_count, total_pages}}` and `{data: [...], meta: {current_page, next_page, total_pages, ...}}`. Normalize in one adapter; `per_page` max is 100; do not assume stable page numbers—dedupe by id.
- `--all` streams pages and emits NDJSON; never buffer an unbounded collection. For bulk history, prefer the family export contract over page scraping.

### Credential storage (MEDIUM)

- Non-secret config (`config.yml`: profiles, server URLs, default output) lives under `$XDG_CONFIG_HOME/sure` or `~/.config/sure`, mode 0644. Tokens never go in this file.
- macOS: Keychain generic password via `security`, service `sure-cli`, account = profile name. Pass the secret on stdin where the installed `security` supports it; if it insists on a TTY, use the file fallback rather than exposing the secret in argv.
- Linux: `secret-tool` (libsecret-tools) with attributes `service=sure-cli profile=<name>`; it reads the secret from stdin. Detect the binary; if no Secret Service daemon exists, use the file fallback.
- Windows: no dependable built-in Ruby Credential Manager binding. Use `%APPDATA%\sure\credentials.json` restricted with `icacls` to the current user; DPAPI encryption is a later enhancement.
- File fallback: directory 0700, file 0600, atomic write (temp in same directory → `fsync` → `rename`), refuse symlinks, `flock` around refresh. Warn once that the file is plaintext at rest.
- There is no maintained cross-platform Ruby keychain gem in 2026: `keyring` stopped in 2016 and `libsecret` is Linux-only. Shell adapters plus a `0600` fallback are the practical cross-platform choice.
- Do not add `keyring`, `system_keychain`, or `libsecret` gems; they are abandoned, platform-limited, or require native introspection libraries.

### OAuth loopback (MEDIUM-HIGH)

- Sure forces PKCE (`force_pkce`), supports only the authorization-code grant, and exposes DCR at `POST /register` with metadata at `/.well-known/oauth-authorization-server`.
- Bind `127.0.0.1` first, then register the exact redirect URI. Register a small port set (e.g. `8765`–`8769`) in one DCR call so a busy port does not force a second registration.
- Client name must not contain a standalone "Sure" word: separators are normalized, so `sure-cli` and `sure-terminal` are rejected. A single word such as `SureTerminal` is accepted. Send `grant_types: ["authorization_code"]` and `token_endpoint_auth_method: "none"`.
- Generate a 43–128 character verifier (`SecureRandom.urlsafe_base64(64)`), derive `S256` with `Digest::SHA256` and unpadded base64url, and compare `state` before exchanging the code.
- Exchange at `POST /oauth/token` with `client_id` only (`auth_scheme: :request_body`, nil secret). Do not use `/api/v1/auth/refresh`; refresh through `/oauth/token` with `grant_type=refresh_token` and persist the rotated token atomically.
- Store both access and refresh tokens; access tokens last one year but refresh proactively and re-authenticate on `invalid_grant`. Print the URL and accept a pasted code for headless/SSH.
- DCR currently assigns `read_write` unconditionally and advertises only that scope. A read-only CLI session requires a server change; use a `read` API key when least privilege matters.

### Output and testing

- Table on a TTY, JSON on a pipe; explicit `--json`, `--csv`, `--ndjson`, or `--table` wins. Color only on a TTY and only when `NO_COLOR`/`TERM=dumb` are absent.
- Stdout carries only the payload; warnings, prompts, and spinners go to stderr. `tty-spinner` is TTY-only and optional; `tty-prompt` is unnecessary.
- Money stays a server-provided decimal string. Never parse to `Float`, never recompute balances, budgets, cash flow, or classification; format only.
- Minitest 6.0.6 for unit and integration; WebMock for HTTP behavior; VCR for a few recorded flows with secrets filtered; `faraday-openapi` validates requests and responses against `docs/api/openapi.yaml` and the pinned snapshots. Because the spec has no `operationId`, map by method + path.
- CLI integration tests use `Open3.capture3` against `exe/sure` with a temp `HOME`/`XDG_CONFIG_HOME` and a WEBrick stub server. Assert JSON purity, exit codes, no prompt on a pipe, `--dry-run` makes no network call, and `EPIPE`/SIGINT behavior. Use `PTY.spawn` only for TTY-specific tests.
- Keep a small, tagged live suite against a Compose Sure + Postgres + Redis instance; run nightly and before release, never on every PR. Do not use RSpec or Aruba for CLI behavior.

### Distribution and release

- Gem layout: `cli/sure.gemspec`, `cli/exe/sure`, `cli/lib/sure.rb`, `cli/lib/sure/cli/…`, `cli/test/…`, `cli/CHANGELOG.md`. The gem name `sure` is unclaimed on RubyGems as of 2026-10-31; fall back to `sure-cli` if that changes. License `AGPL-3.0-only`, `required_ruby_version >= 3.4`, and scope gemspec files to `cli/` so Rails files never ship.
- Container: multi-stage `ruby:3.4-slim`, install the built gem, run as a non-root user, `ENTRYPOINT ["sure"]`. Pin the base image digest and keep it free of build toolchains because the stack is pure Ruby.
- Homebrew: optional and lower priority. Prefer Tebako 0.15.9 macOS/Linux binaries in a tap formula; add `generate_completions_from_executable(bin/"sure", "completion")`. A gem-installing formula must vendor dependency resources because Homebrew sandboxes network access during install.
- Completions: `sure completion bash|zsh|fish` prints a script generated from the operation catalog; snapshot-test the output. Thor provides none itself.
- Release: tag `cli-vX.Y.Z` (`Bundler::GemHelper.tag_prefix = "cli-"`), run `rubygems/release-gem@v1` with `working-directory: cli`, `id-token: write`, and a `release` environment. Configure a RubyGems trusted publisher; include the contract snapshot hash in release notes. Filter CI on `cli/**` and `docs/api/openapi.yaml`, and pin action SHAs as the existing workflows do.

## Alternatives Considered

| Recommended | Alternative | When to Use Alternative |
|-------------|-------------|-------------------------|
| Thor 1.5.0 | dry-cli 1.4.1 | Use dry-cli if the team prefers immutable command objects and typed params over Thor's DSL. Both lack built-in completion; `dry-cli-completion` is still prerelease and only bash/zsh. Thor wins on Rails familiarity, nested command help, and 110-command ergonomics. |
| Thor 1.5.0 | GLI 2.22.2 | Only for legacy GLI code or its advanced option parser. Heavier, smaller community, and no benefit here. |
| Thor 1.5.0 | OptionParser (stdlib) | Only for a single-command, zero-dependency bootstrap tool. Hand-rolling help, aliases, validation, and completion for 110 operations is unjustified. |
| Faraday 2.15.1 | http.rb 6.0.4 | Use http.rb if raw throughput/persistent connections dominate and you accept `llhttp-ffi` native builds. Poor fit for a gem that must install cleanly everywhere. |
| Faraday 2.15.1 | Net::HTTP (stdlib) | Only if zero runtime gems is a hard requirement. You would rebuild timeouts, redirects, retries, and structured errors. |
| terminal-table 4.0.0 | tty-table 0.12.0 | Only if you specifically need tty-table's border styles. It is unmaintained since 2020 and its `strings` dependency pins `unicode-display_width < 3`. |
| pastel 0.8.0 | rainbow / tty-color | Only inside another tool's dependency tree. Pastel is the smallest explicit choice. |
| oauth2 2.1.0 | openid_connect 2.5.0 | Only if Sure exposes OIDC discovery/ID tokens. It does not; plain OAuth 2.0 with PKCE is enough. |
| oauth2 2.1.0 | Hand-rolled OAuth on Faraday | Use if you want zero extra runtime gems or exact control over the public-client token request. You then own refresh, error mapping, and token serialization. |
| Minitest 6.0.6 | RSpec 3.13.2 | Only if the team mandates RSpec. This repo uses RSpec/rswag for OpenAPI docs, not behavioral tests; mixing both in `cli/` adds no value. |
| faraday-openapi 0.8.3 | openapi_first 4.2.1 direct use | Use openapi_first directly if you need server-side Rack validation. For a Faraday client, faraday-openapi is the purpose-built wrapper. |
| WebMock + VCR | Live Sure instance per PR | Use a live Compose instance only as a tagged nightly/release smoke. Per-PR live tests are flaky and burn API-key rate limits. |
| Gem + container | Homebrew-first | Only if most users are macOS CLI-only and you can ship Tebako binaries. The gem/container path covers self-hosters and CI first. |

## What NOT to Use

| Avoid | Why | Use Instead |
|-------|-----|-------------|
| `keyring` 0.4.1 | Abandoned in 2016; supports macOS and GNOME 2 only; no Windows Credential Manager or Secret Service; requires GIR/FFI and introspection libraries. | `security` on macOS, `secret-tool` on Linux, and a `0600` file fallback; see Credential storage above. |
| `system_keychain` 1.0.0, `ruby-keychain` 0.4.0 | macOS-only and effectively abandoned. | Cross-platform credential-store adapter. |
| `libsecret` 4.3.9 as a cross-platform dependency | Linux-only, needs native libsecret and GObject introspection; breaks clean gem/container/Homebrew installs. | Detect `secret-tool` at runtime; do not link libsecret. |
| `tty-table` 0.12.0 | Last release 2020; transitive `strings` caps `unicode-display_width` below 3, causing resolution drift. | `terminal-table` 4.0.0. |
| `tty-prompt` 0.23.1 | Last release 2021; pulls an interactive reader stack for what is mostly a yes/no or hidden secret. | `io/console#getpass` plus a plain confirmation; require `--yes` when not a TTY. |
| GLI 2.22.2 for a new CLI | Aging DSL, heavier internals, smaller ecosystem; no capability Thor lacks here. | Thor 1.5.0. |
| `OptionParser` for the full CLI | No command tree, aliases, type coercion, or help generation; 110 operations make hand-rolling untenable. | Thor, with OptionParser only inside a tiny standalone helper if ever needed. |
| `http.rb` 6.0.4 | Requires native `llhttp-ffi`; extra build/platform burden for a gem and slim container. | Faraday 2.15.1 with `net_http`. |
| `httparty` | Legacy API, weaker retry/error model; already present in the Rails app for other reasons. | Faraday + faraday-retry. |
| Faraday 1.x | EOL; incompatible with current faraday-retry/oauth2 expectations. | Faraday 2.15.x. |
| OAuth implicit, password, or device grants | Sure configures authorization code only; device grant is not configured, and implicit/password are OAuth 2.1 anti-patterns. | Authorization code + PKCE S256 + `state`. |
| `/api/v1/auth/refresh` | Mobile/device-specific rotating refresh endpoint, not the CLI OAuth contract. | `POST /oauth/token` with `grant_type=refresh_token`. |
| `openid_connect` 2.5.0 | Adds OIDC discovery/ID-token machinery Sure does not expose. | `oauth2` 2.1.0 plus manual PKCE. |
| `ruby-packer`, `traveling-ruby`, `ocra` | Dead or stale; no current Ruby 3.4 support. | Gem + container; Tebako 0.15.9 only if standalone binaries are needed. |
| `standard` 1.57.0 | Conflicts with the repo's `rubocop-rails-omakase` configuration and CI expectations. | RuboCop 1.92.2 + omakase 1.1.0. |
| Aruba/Cucumber 3.0.1 as the default CLI test harness | Slow, Gherkin-heavy, and awkward with Minitest 6 for a 110-command CLI. | Minitest + `Open3.capture3` + a WEBrick stub server. |
| `openapi3_parser` 0.10.1 | Stale (last release January 2025) compared with openapi_first/faraday-openapi. | `faraday-openapi` 0.8.3 in tests. |
| Generating the entire CLI from OpenAPI | `docs/api/openapi.yaml` has no `operationId` and has known gaps; codegen would produce commands the server does not support. | Declarative `config/operations.yml` catalog + hand-written Thor commands; validate against the spec. |
| API keys or tokens in `--api-key` argv, `config.yml`, or default env vars | Visible in shell history, process lists, logs, and crash reports; violates the project security constraint. | Prompt via `getpass`, OS keychain, or a `0600` credential file; env only for CI with an explicit warning. |

## Stack Patterns by Variant

**If shipping the API-key MVP first:**
- Use Thor, Faraday, terminal-table, pastel, and the credential store only.
- Leave `oauth2`, `webrick`, and `launchy` out of the gemspec until Phase 5; this keeps the install surface small.
- Because API keys work on every deployment and need no server change.

**If enabling OAuth loopback:**
- Bind `127.0.0.1` first, then register the exact redirect URI via `POST /register`; do not register one port and listen on another.
- Send a `client_name` without a standalone "Sure" word (e.g. `SureTerminal`); separators do not help because the DCR endpoint normalizes and rejects `sure-cli` and `sure-terminal` too.
- Use authorization code + PKCE S256 + `state`; exchange at `/oauth/token` with `client_id` only (`token_endpoint_auth_method: none`), no secret.
- Request `read_write`: the current DCR controller assigns `read_write` unconditionally and advertises only that scope. A read-only OAuth grant requires a server change; use a `read` API key when least privilege matters.
- Store the refresh token atomically and refresh proactively; Doorkeeper issues one-year access tokens, which is not "permanent".

**If running headless, in a container, or in CI:**
- Use the file credential store (or an explicit CI token variable), `--json` by default when piped, `--no-color`, and `--yes`.
- Never prompt when `stdin` is not a TTY; fail with the usage/confirmation exit code instead.
- Because keychain daemons and browser launch are unavailable or unreliable there.

**If the server is an older minor:**
- Probe capabilities and fall back to documented endpoints; tolerate missing `/.well-known/oauth-authorization-server` by using `/oauth/authorize`, `/oauth/token`, and `/register` directly.
- Pin `config/openapi.snapshot.yaml` per CLI release and run contract tests against current and previous-minor snapshots.
- Because self-hosted users upgrade on their own schedule and the OpenAPI file is generated from current specs, not deployed versions.

**If output is piped or scripted:**
- Emit only the requested payload on stdout; send progress, warnings, prompts, and spinners to stderr.
- Default to JSON on a non-TTY, table on a TTY; explicit `--json`, `--csv`, `--ndjson`, or `--table` always wins.
- Use the architecture's stable exit codes (`0`, `2`–`10`, `130`) consistently across all commands.

## Version Compatibility

| Package A | Compatible With | Notes |
|-----------|-----------------|-------|
| ruby 3.4.9 | all recommended gems | Ruby 3.4 promotes `csv`, `base64`, `bigdecimal`, `drb` to bundled gems; `webrick` has been a gem since Ruby 3.0. Declare `csv` and `webrick`. The URI parser is RFC 3986, so normalize server URLs carefully. |
| thor 1.5.0 | Ruby >= 2.6 | Pure Ruby; no native build. No built-in shell completion in Thor 1.5; generate completions from the command catalog. |
| faraday 2.15.1 | Ruby >= 3.0 | Uses the `net_http` adapter; avoids native `llhttp-ffi`. |
| faraday-retry 2.4.0 | Faraday 2.x | Default retry methods include DELETE/PUT; override to `%i[get head]` for financial writes. 429 + `Retry-After` is supported. |
| oauth2 2.1.0 | Faraday 2.x, Ruby >= 2.2 | Public client: `auth_scheme: :request_body`, nil secret. PKCE is not generated by the gem; implement verifier/challenge yourself. |
| webrick 1.9.2 | Ruby >= 2.4 | Pure Ruby; bind only to loopback and shut down after one callback. |
| terminal-table 4.0.0 | unicode-display_width 3.3.0 | Constraint is `>= 1.1.1, < 4`; do not pin the old 2.x line. |
| pastel 0.8.0 | Ruby >= 2.0 | Stable; explicitly disable for `NO_COLOR`, `TERM=dumb`, `--no-color`, and non-TTY. |
| csv 3.3.7 | Ruby 3.4 bundled gem | Ruby 3.4 ships a 3.3.x copy; declare `~> 3.3` and stream with `CSV.new(io)` for exports. |
| minitest 6.0.6 | Ruby >= 3.2 | Breaking vs 5.x: `minitest/mock` extracted, plugin loading opt-in, `assert_equal(nil, ...)` rejected. Require `minitest/autorun`. |
| webmock 3.34.0 | Minitest 6 | Intercepts at the HTTP layer; works with Faraday adapters. |
| vcr 6.4.1 | Minitest 6 | Configure `filter_sensitive_data` for `Authorization`, `X-Api-Key`, and refresh tokens. |
| faraday-openapi 0.8.3 | Faraday >= 2.9, < 3; openapi_first 4.x; Ruby >= 3.2 | Test-only. Call `Faraday::Openapi.enabled = false` outside tests. |
| rubocop 1.92.2 + omakase 1.1.0 | Ruby >= 2.7 | Dev-only. Omakase pulls `rubocop-rails`; acceptable in `cli/` but never a runtime dependency. |
| bundler 4.0.23 | Ruby 3.4 | Set `Bundler::GemHelper.tag_prefix = "cli-"` before release so tags do not collide with server `v*` tags. |
| tebako 0.15.9 | macOS/Linux | Optional standalone binary packaging; not a Windows solution. |

Minitest 6 is the current major; if a reporter or plugin lags, pin `minitest 5.27.0` (the Rails app's version) without changing the test style.

## Sources

- RubyGems API — exact versions and release dates checked 2026-10-31 for every gem above (https://rubygems.org/api/v1/gems).
- `docs/api/openapi.yaml` — 110 operations, `apiKeyAuth`/`oauth2`, two pagination envelopes (`pagination` and `meta`), no `operationId`.
- `app/controllers/api/v1/base_controller.rb` — `X-Api-Key`, scope hierarchy, `X-RateLimit-*`, and `Retry-After` headers.
- `config/initializers/doorkeeper.rb` — `force_pkce`, `use_refresh_token`, one-year access tokens, `read`/`read_write` scopes.
- `app/controllers/oauth_registration_controller.rb` and `oauth_metadata_controller.rb` — `/register` DCR, loopback/private-use redirect rules, reserved "Sure" client names, fixed `read_write` scope, S256-only metadata.
- Thor v1.5.0 release notes — https://github.com/rails/thor/releases/tag/v1.5.0 (no completion module in the 1.5 tree).
- Faraday Retry README — retry methods, statuses, `Retry-After` behavior.
- oauth2 2.1.0 README/CHANGELOG and `OAuth2::Strategy::AuthCode` — PKCE explicitly left to the application.
- Minitest 6.0.0 History — breaking changes and Ruby >= 3.2 floor.
- faraday-openapi 0.8.3 README — request/response validation against OpenAPI 3.0/3.1.
- RubyGems Trusted Publishing guide — OIDC release flow and `rubygems/release-gem@v1`.
- Bundler 4.0.23 `GemHelper` source — `tag_prefix` support for monorepo tags.
- Homebrew Formula Cookbook — `libexec`, `bin.install_symlink`, `generate_completions_from_executable`, sandbox/network constraints.
- Tebako 0.15.9 — https://www.tebako.org (macOS/Linux standalone packaging).
- Ruby 3.4.0 release notes — bundled gems and stdlib changes.

---

*Stack research for: Sure CLI*
*Researched: 2026-10-31*
