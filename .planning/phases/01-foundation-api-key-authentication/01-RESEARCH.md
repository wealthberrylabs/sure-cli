# Phase 1: Foundation & API-Key Authentication - Research

**Researched:** 2026-10-31
**Domain:** Standalone Ruby gem CLI foundation, named profiles, API-key credential storage, Faraday transport, output/exit contracts, and doctor diagnostics for Sure `/api/v1`
**Overall confidence:** HIGH for the checked-in API/contracts and repo versions; MEDIUM for cross-platform keychain behavior and the missing user identity field in `GET /api/v1/usage`

<user_constraints>
## User Constraints

### Implementation Decisions

#### Command Grammar & Naming

- **D-01:** Commands are **noun-first plural**: `sure accounts list`, `sure transactions add`, `sure budgets show`. Every domain gets a plural noun command group with verbs underneath.
- **D-02:** Ship a **small, documented set of high-frequency aliases**: `tx` → `transactions`, `acct` → `accounts`, `cf` → `cashflow`. Aliases are discoverable in help, not hidden. Generated copy-commands should prefer canonical full names to keep shared commands unambiguous.
- **D-03:** Reporting commands live at the top level (`sure cashflow`, `sure balance-sheet`, `sure budgets`) and are also reachable through a `sure reports <name>` alias group.
- **D-04:** Destructive commands use **`delete` only**. Do not add an `rm` alias. `delete` always goes through the Phase 3 preview/confirmation framework; Phase 1 only establishes the naming convention.

#### Credential Storage & Login UX

- **D-05:** Credentials are **keychain-first**: macOS Keychain via `security`, Linux Secret Service via `secret-tool`. When no keychain is available, fall back to an atomic **0600** file in a **0700** directory.
- **D-06:** The plaintext fallback is **automatic with a one-time warning per profile**, and `sure doctor` reports the active storage mode. Do not require a separate opt-in flag.
- **D-07:** `sure auth login` accepts a key through a **hidden prompt** by default, plus `--api-key-file`, `--api-key-stdin`, and `SURE_API_KEY`. Do **not** provide a `--api-key` argv flag, so keys never appear in process lists or shell history.
- **D-08:** `sure auth logout` deletes the credential locally and explains that the API key must be revoked in **Sure Settings → API Keys**. The public API has no API-key revocation endpoint, so do not pretend logout revokes it.
- **D-09:** `sure auth status` reports the active profile, server URL, user, key name, scopes, authentication method, and rate-limit tier. It must never print the key itself.
- **D-10:** API keys use Sure's existing `read` and `read_write` scopes. The CLI preflights the scope before any write command and fails with an actionable message instead of sending a request that will 403.

#### Output Contract & Exit Codes

- **D-11:** Default output is **a table on a TTY and JSON when stdout is piped**. `--table`, `--json`, `--csv`, and `--ndjson` override the default explicitly.
- **D-12:** JSON output uses a stable envelope:
  ```json
  {
    "data": …,
    "meta": {
      "schema_version": 1,
      "pagination": { … },
      "as_of": "…",
      "rate_limit": { … },
      "warnings": [ … ]
    }
  }
  ```
  Raw server payloads are available only when explicitly requested (for example `--raw`), never as the default contract.
- **D-13:** Exit codes are semantic and stable:
  - `0` success
  - `1` general error
  - `2` usage/option error
  - `3` authentication or insufficient scope
  - `4` not found
  - `5` validation/conflict
  - `6` rate limited
  - `7` partial batch failure
  - `8` network/TLS/server unavailable
  - `9` timeout
- **D-14:** Data goes to **stdout**; errors, warnings, and progress go to **stderr**. Color is enabled only on a TTY, honors `NO_COLOR` and `--no-color`, and is disabled when piped. `--quiet` suppresses non-error output; `--verbose` adds request IDs and timings.
- **D-15:** The CLI never prompts when stdin is not a TTY. It exits nonzero with an actionable message directing the user to the relevant flag or environment variable.
- **D-16:** Field selection (`--fields`) and machine formats apply to every command group from the start, so later commands do not need a second output layer.

### the agent's Discretion

The planner may decide these without another user round-trip:

- Exact YAML config schema and key names; profile precedence should be flag > environment > profile > defaults.
- HTTP timeout defaults and retry policy. Recommended starting point: 5s open, 30s read; retry only idempotent `GET`/`HEAD`; bounded backoff with jitter; honor `Retry-After` and `X-RateLimit-*`.
- Keychain service/account naming and the precise atomic-write implementation.
- Table columns and help text wording, as long as they follow the output contract.
- The order and exact checks in `sure doctor` (connectivity, auth, scope, TLS, clock skew, config permissions, server capability).
- Whether aliases appear in generated copy-commands; D-02 recommends canonical names.
- Raw `sure api` safety: at minimum require confirmation for `DELETE`/`PATCH`/`POST` on a TTY, support `--dry-run`, and redact auth headers. Do not build a server-side allowlist in Phase 1.

### Deferred Ideas (OUT OF SCOPE)

None — discussion stayed within phase scope.

### Phase Requirements

| ID | Description | Research Support |
|----|-------------|------------------|
| FOUND-01 | User can install the CLI as a Ruby gem and run `sure` from any shell. | Standalone `cli/` gem, gemspec file allowlist, `exe/sure`, temp-`GEM_HOME` install smoke test. |
| FOUND-02 | User can run `sure --version`, `sure help`, and per-command help with examples. | Thor `version` mapping, `help` command, catalog-backed long descriptions/examples, no-config startup. |
| FOUND-03 | User can define named server profiles and switch with `--profile`, `SURE_PROFILE`, or a default. | `Config::Paths`, `Config::Loader`, `Config::Resolver`, `auth login --profile`, precedence table. |
| FOUND-04 | User can target a server URL with a path prefix, custom CA bundle, or explicit insecure opt-in. | `HTTP::UrlBuilder` prefix-preserving join, Faraday `ssl.ca_file`, `--insecure`, doctor warnings. |
| FOUND-05 | User sees readable tables on a TTY and stable JSON when stdout is piped. | `Output::Selector` TTY detection, `Output::Table`, `Output::Json`, injected IO. |
| FOUND-06 | User can force `--json`, `--csv`, `--ndjson`, and `--fields` output for scripting. | Formatter classes and `Output::FieldSelection` with validation. |
| FOUND-07 | User gets deterministic exit codes, errors on stderr, and no Ruby backtraces for expected failures. | `Errors::ExitCodes`, `Errors::Mapper`, single `CLI::Runner` boundary, error JSON on stderr. |
| FOUND-08 | User can run `sure doctor` to check connectivity, auth, scope, TLS, clock skew, config permissions, and server compatibility. | `Doctor::Runner` non-short-circuiting checks against `/api/v1/usage` and `/api/v1/accounts?per_page=1`. |
| FOUND-09 | User can call any endpoint through `sure api METHOD PATH` with normal auth, tenancy, and redaction. | `Commands::Api`, `/api/v1`-only path validation, `Auth::ScopePreflight`, `--raw`/`--dry-run`. |
| FOUND-10 | User can install bash, zsh, and fish completion generated from the command catalog. | `Completion::Generator`, `config/operations.yml`, snapshot tests. |
| AUTH-01 | User can log in with an API key via hidden prompt, `--api-key-file`, or stdin, without editing files. | `Auth::Login`, `io/console#getpass`, stdin/file/env inputs, no `--api-key`. |
| AUTH-02 | User credentials are stored in the OS keychain when available, with a `0600` atomic file fallback and a one-time warning. | `Auth::MacKeychainStore`, `Auth::SecretServiceStore`, `Auth::FileStore`, `Config::AtomicFile`, warning marker. |
| AUTH-03 | User can inspect `sure auth status` to see server, profile, user, key name, scopes, and rate-limit tier. | `Auth::Status` from `/usage`; **current API lacks a user field** — see contract gap. |
| AUTH-08 | CI and automation can supply a key through `SURE_API_KEY` without persisting it. | `Auth::ApiKeyProvider` environment source, precedence over stored credential, `auth logout` warning. |
| AUTH-09 | The CLI never prints, logs, or includes API keys, bearer tokens, or refresh tokens in errors, debug output, or copyable commands. | `Redactor`, `raise_error include_request: false`, no header/body logging, argv/env scrub for child commands. |
| SAFE-05 | The CLI never prompts when stdin is not a TTY; it fails with an actionable message instead. | `Runtime.stdin.tty?` checks, explicit login inputs, `sure api` `--yes`, exit 2. |
| SAFE-06 | Write commands preflight the credential scope and refuse `read`-only keys before starting. | `Auth::ScopePreflight`, cached scopes from login/status, `/usage` fallback, `read_write` check. |

</user_constraints>

## Standard Stack

The CLI is a standalone gem inside `cli/`. It uses its own `Gemfile`, `Gemfile.lock`, `sure.gemspec`, tests, and lint configuration. It must not load Rails, ActiveSupport, ActiveRecord, or the root Rails bundle. Runtime code is plain Ruby 3.4 plus Thor/Faraday and small presentation gems.

### Runtime

| Gem / Tool | Version | Already in root `Gemfile.lock`? | Purpose | Provenance |
|------------|---------|--------------------------------|---------|------------|
| Ruby | 3.4.9p82 | Yes — `RUBY VERSION` | Runtime; matches `.ruby-version` and the server | `[VERIFIED: codebase: .ruby-version, Gemfile.lock]` |
| Thor | 1.5.0 | Yes — line 843 | Command tree, subcommands, aliases, help, option parsing | `[VERIFIED: codebase: Gemfile.lock:843]` |
| Faraday | 2.14.3 | Yes — line 224 | HTTP client, JSON middleware, TLS, timeouts, middleware pipeline | `[VERIFIED: codebase: Gemfile.lock:224]` |
| faraday-retry | 2.3.2 | Yes — line 234 | Bounded retries, jitter, `Retry-After`/`X-RateLimit-Reset` handling | `[VERIFIED: codebase: Gemfile.lock:234]` |
| terminal-table | 4.0.0 | Yes — line 841 | Human-readable TTY tables; Unicode width via `unicode-display_width` 3.1.4 | `[VERIFIED: codebase: Gemfile.lock:841-861]` |
| pastel | 0.8.0 | **No** | Explicit TTY color enable/disable; no global monkeypatching | `[VERIFIED: RubyGems API: pastel 0.8.0, 118M downloads, source piotrmurach/pastel]`, `[CITED: .planning/research/STACK.md]` |
| csv | 3.3.5 | Yes — line 173 | CSV generation; Ruby 3.4 bundled gem, must be declared | `[VERIFIED: codebase: Gemfile.lock:173]` |
| json | 2.21.2 | Yes — line 370 | Stable JSON parsing/generation; default gem | `[VERIFIED: codebase: Gemfile.lock:370]` |
| io-console | Ruby default | No — default gem, not in the lockfile | Hidden API-key prompt via `IO#getpass` / `noecho` | `[CITED: .planning/research/STACK.md]`, `[ASSUMED: Ruby 3.4 default gem]` |
| Bundler | 2.6.7 | Yes — `BUNDLED WITH` | Isolated dependency resolution and gem build tasks | `[VERIFIED: codebase: Gemfile.lock]` |

**Not in Phase 1 runtime:** `oauth2`, `webrick`, `launchy` (Phase 5 OAuth), `faraday-multipart`, `vcr`, `faraday-openapi`, `tty-prompt`, `keyring`, `libsecret`, `system_keychain`, `completely`. Do not add them to the Phase 1 gemspec.

`pastel 0.8.0` pulls `tty-color 0.6.0` (small, stable, no runtime deps); `terminal-table 4.0.0` uses root-locked `unicode-display_width 3.1.4`; `faraday 2.14.3` uses root-locked `faraday-net_http 3.4.4`. `[VERIFIED: RubyGems API: tty-color; codebase: Gemfile.lock]`

### Development / Test

| Gem / Tool | Version | Already in root `Gemfile.lock`? | Purpose | Provenance |
|------------|---------|--------------------------------|---------|------------|
| Minitest | 5.27.0 | Yes — line 437 | Unit, command, and integration tests; repo already uses Minitest | `[VERIFIED: codebase: Gemfile.lock:437]` |
| WebMock | 3.25.1 | Yes — line 894 | HTTP stubbing at the Faraday boundary; header/status/retry assertions | `[VERIFIED: codebase: Gemfile.lock:894]` |
| Rake | 13.4.2 | Yes — line 658 | `test`, `lint`, `build` tasks | `[VERIFIED: codebase: Gemfile.lock:658]` |
| RuboCop | 1.76.1 | Yes — line 717 | Ruby lint/format | `[VERIFIED: codebase: Gemfile.lock:717]` |
| rubocop-rails-omakase | 1.1.0 | Yes — line 741 | Repo-consistent style configuration; development only | `[VERIFIED: codebase: Gemfile.lock:741]` |
| Bundler | 2.6.7 | Yes — `BUNDLED WITH` | Build/install/release tasks | `[VERIFIED: codebase: Gemfile.lock]` |

**Use the root lock versions, not the newer versions quoted in `STACK.md`.** The root lock is the repository's executable truth: Faraday 2.14.3 (not 2.15.1), faraday-retry 2.3.2 (not 2.4.0), csv 3.3.5 (not 3.3.7), Minitest 5.27.0 (not 6.0.6), Bundler 2.6.7 (not 4.0.23). This avoids introducing a second dependency generation into the monorepo. `[VERIFIED: codebase: Gemfile.lock]`

### Packaging and Distribution

| Concern | Decision | Provenance |
|---------|----------|------------|
| Gem name | `sure`; executable `sure`; module `Sure` | `[VERIFIED: RubyGems API: sure and sure-cli both return 404 on 2026-10-31]`, `[CITED: .planning/research/STACK.md]` |
| Version | `0.1.0` for the first phase | `[ASSUMED]` |
| License | `AGPL-3.0-only` | `[CITED: .planning/PROJECT.md]` |
| Ruby floor | `>= 3.4.0` | `[VERIFIED: codebase: .ruby-version]` |
| Build | `gem build sure.gemspec` from `cli/`; `Bundler::GemHelper.tag_prefix = "cli-"` for later `cli-v0.1.0` tags | `[CITED: .planning/research/STACK.md]` |
| Containers/Homebrew | Deferred to Phase 8; not a Phase 1 dependency | `[CITED: .planning/ROADMAP.md]` |
| Completion | Generate static bash/zsh/fish scripts from `config/operations.yml`; do not add a completion gem | `[CITED: .planning/research/STACK.md]` |

### Installation

```bash
cd cli
bundle install
bundle exec rake test
bundle exec rubocop
gem build sure.gemspec
```

`cli/Gemfile`:

```ruby
source "https://rubygems.org"

gemspec
ruby file: File.expand_path("../.ruby-version", __dir__)
```

`cli/sure.gemspec` runtime dependencies:

```ruby
spec.add_dependency "thor", "~> 1.5"
spec.add_dependency "faraday", "~> 2.14"
spec.add_dependency "faraday-retry", "~> 2.3"
spec.add_dependency "terminal-table", "~> 4.0"
spec.add_dependency "pastel", "~> 0.8"
spec.add_dependency "csv", "~> 3.3"
```

Gemspec file allowlist and executable:

```ruby
spec.files = Dir[
  "lib/**/*.rb",
  "exe/*",
  "config/operations.yml",
  "README.md",
  "CHANGELOG.md",
  "LICENSE"
]
spec.bindir = "exe"
spec.executables = ["sure"]
spec.require_paths = ["lib"]
spec.required_ruby_version = ">= 3.4.0"
spec.license = "AGPL-3.0-only"
```

This allowlist is mandatory: a plain `git ls-files` in a monorepo would ship Rails files. Development dependencies (`minitest`, `webmock`, `rake`, `rubocop`, `rubocop-rails-omakase`) belong in the gemspec or `cli/Gemfile`, never in the root bundle. `Bundler::GemHelper.tag_prefix = "cli-"` belongs in `cli/Rakefile`.

**Package provenance:** every declared runtime gem except `pastel` already exists in the root lockfile. `pastel 0.8.0` is a real, stable, widely used gem with a source repository; it is the only new direct runtime dependency (and it pulls `tty-color 0.6.0`). No package is speculative. `sure` is unclaimed on RubyGems as of the research date; use it rather than inventing a different gem name.

## Architecture Patterns

### Architectural Responsibility Map

| Capability | Primary Tier | Secondary Tier | Rationale |
|------------|-------------|----------------|-----------|
| Command grammar, aliases, help | CLI interface | Catalog | Thor owns argv and help; catalog owns examples/metadata. |
| Profile/server/TLS selection | CLI configuration | OS environment | Config resolves non-secret settings; environment/flag overrides are explicit. |
| API-key acquisition | CLI auth | TTY/stdin/file/keychain | Secret enters only through prompt, stdin, file, or `SURE_API_KEY`; never argv. |
| Credential persistence | OS keychain | 0600 file | Keychain is preferred; file fallback keeps headless/CI usable with warning. |
| HTTP auth and transport | HTTP pipeline | Faraday | One pipeline injects `X-Api-Key`, sets TLS/timeouts, retries GET/HEAD only. |
| Error/exit-code mapping | Error boundary | CLI runner | One mapper prevents per-command drift; commands never call `exit`. |
| Output selection/formatting | Presentation | Catalog/presenters | TTY/pipe selection and explicit flags choose one formatter. |
| Doctor diagnostics | CLI diagnostics | HTTP/auth/config | Non-short-circuiting checks report all failures with fixes. |
| Raw API escape hatch | CLI interface | HTTP/auth | `sure api` uses the same pipeline and `/api/v1` path scope; no bypass. |
| Completion generation | Presentation/tooling | Catalog | Static scripts derive from the same catalog as help. |

### Recommended Project Structure

```text
cli/
├── sure.gemspec
├── Gemfile
├── Gemfile.lock
├── Rakefile
├── .rubocop.yml
├── README.md
├── CHANGELOG.md
├── LICENSE
├── exe/
│   └── sure
├── bin/
│   └── sure
├── config/
│   └── operations.yml
├── dist/
│   └── command_catalog.json          # generated; Phase 7 consumes
├── lib/
│   ├── sure.rb
│   └── sure/
│       ├── version.rb
│       ├── cli.rb
│       ├── cli/
│       │   ├── application.rb
│       │   ├── base.rb
│       │   ├── runner.rb
│       │   ├── runtime.rb
│       │   ├── context.rb
│       │   └── commands/
│       │       ├── auth.rb
│       │       ├── doctor.rb
│       │       ├── api.rb
│       │       └── completion.rb
│       ├── catalog.rb
│       ├── catalog/
│       │   ├── operation.rb
│       │   ├── loader.rb
│       │   └── validator.rb
│       ├── config.rb
│       ├── config/
│       │   ├── paths.rb
│       │   ├── loader.rb
│       │   ├── profile.rb
│       │   ├── resolver.rb
│       │   └── atomic_file.rb
│       ├── auth.rb
│       ├── auth/
│       │   ├── credential.rb
│       │   ├── credential_key.rb
│       │   ├── store.rb
│       │   ├── file_store.rb
│       │   ├── mac_keychain_store.rb
│       │   ├── secret_service_store.rb
│       │   ├── store_factory.rb
│       │   ├── command_runner.rb
│       │   ├── api_key_provider.rb
│       │   ├── login.rb
│       │   ├── logout.rb
│       │   ├── status.rb
│       │   └── scope_preflight.rb
│       ├── http/
│       │   ├── client.rb
│       │   ├── connection.rb
│       │   ├── response.rb
│       │   ├── url_builder.rb
│       │   ├── rate_limit.rb
│       │   ├── envelope.rb
│       │   ├── pagination.rb
│       │   └── auth_middleware.rb
│       ├── errors.rb
│       ├── errors/
│       │   ├── error.rb
│       │   ├── exit_codes.rb
│       │   └── mapper.rb
│       ├── redactor.rb
│       ├── output.rb
│       ├── output/
│       │   ├── result.rb
│       │   ├── column.rb
│       │   ├── selector.rb
│       │   ├── base.rb
│       │   ├── json.rb
│       │   ├── table.rb
│       │   ├── csv.rb
│       │   ├── ndjson.rb
│       │   └── field_selection.rb
│       ├── doctor/
│       │   ├── runner.rb
│       │   ├── check.rb
│       │   └── result.rb
│       └── completion/
│           └── generator.rb
└── test/
    ├── test_helper.rb
    ├── unit/
    ├── commands/
    ├── integration/
    ├── fixtures/
    │   ├── api/
    │   └── config/
    └── support/
        ├── fake_tty.rb
        ├── fake_store.rb
        ├── fake_command_runner.rb
        └── cli_helper.rb
```

### Plan-to-Module Map

| Plan | Deliverable | Primary modules |
|------|-------------|-----------------|
| 01-01 | Gem skeleton, executable, version, help, initial operation catalog | `sure.gemspec`, `Gemfile`, `exe/sure`, `Sure::CLI::Application` (`#version`), `Sure::CLI::Base`, `Sure::CLI::Runner`, `Sure::CLI::Runtime`, `Sure::Catalog` |
| 01-02 | Config, named profiles, server URL/path/TLS, precedence | `Sure::Config::Paths`, `Loader`, `Profile`, `Resolver`, `AtomicFile`, `Sure::HTTP::UrlBuilder` |
| 01-03 | Faraday pipeline, errors, exit codes, redaction, pagination base | `Sure::HTTP::Client`, `Connection`, `Response`, `RateLimit`, `Envelope`, `Pagination`, `Sure::Errors::*`, `Sure::Redactor` |
| 01-04 | Credential store and auth login/status/logout | `Sure::Auth::*`, `Sure::CLI::Commands::Auth`, `Sure::Auth::ScopePreflight` |
| 01-05 | Doctor, raw API, completion, base output formatters | `Sure::Doctor::*`, `Sure::CLI::Commands::Doctor`, `Api`, `Completion`, `Sure::Output::*`, `Sure::Completion::Generator` |

### Command Lifecycle and Class Layout

Use one root Thor application, one base class, one command class per command group, and one process-boundary runner. Commands stay thin: resolve context, perform one service call, render one `Output::Result`. No command performs HTTP, formatting, or `exit` directly. All command output goes through `runtime.stdout`/`runtime.stderr`; only Thor's built-in help uses Thor's shell (tests may use `capture_io` for `help`).

```ruby
module Sure
  def self.run(argv, stdin: $stdin, stdout: $stdout, stderr: $stderr,
               env: ENV, cwd: Dir.pwd, clock: Time)
    CLI::Runner.new(stdin:, stdout:, stderr:, env:, cwd:, clock:).call(argv)
  end
end

class Sure::CLI::Runner
  def call(argv)
    Sure::CLI::Runtime.with(@runtime) do
      Sure::CLI::Application.start(argv, debug: true)
    end
    Sure::Errors::ExitCodes::SUCCESS
  rescue Sure::Errors::Error => e
    render_error(e)
  rescue Thor::Error => e
    render_usage_error(e)
  rescue Interrupt
    Sure::Errors::ExitCodes::INTERRUPTED
  end
end
```

`Application.start(argv, debug: true)` is deliberate. Thor 1.5's `start` normally catches `Thor::Error`, prints it, and exits with status 1; `debug: true` re-raises so `Sure::CLI::Runner` can map it to exit 2. Also define `self.exit_on_failure? = false` so Thor never calls `exit` inside the library. `[VERIFIED: Thor v1.5.0 lib/thor/base.rb start implementation]`

```ruby
class Sure::CLI::Application < Sure::CLI::Base
  def self.exit_on_failure? = false

  check_unknown_options!
  map %w[--version -v] => :version

  class_option :profile, type: :string, desc: "Profile name"
  class_option :server, type: :string, desc: "Sure server URL (base URL, not /api/v1)"
  class_option :ca_bundle, type: :string, desc: "PEM CA bundle"
  class_option :insecure, type: :boolean, default: false, desc: "Disable TLS verification (dangerous)"
  class_option :json, type: :boolean, default: false
  class_option :table, type: :boolean, default: false
  class_option :csv, type: :boolean, default: false
  class_option :ndjson, type: :boolean, default: false
  class_option :fields, type: :string, desc: "Comma-separated field list"
  class_option :color, type: :boolean, default: true, desc: "Color output (--no-color disables)"
  class_option :quiet, type: :boolean, default: false
  class_option :verbose, type: :boolean, default: false

  class_exclusive :json, :table, :csv, :ndjson
  class_exclusive :quiet, :verbose

  desc "version", "Print the CLI version"
  def version
    runtime.stdout.puts "sure #{Sure::VERSION}"
  end

  subcommand "auth", Sure::CLI::Commands::Auth
  subcommand "doctor", Sure::CLI::Commands::Doctor
  subcommand "api", Sure::CLI::Commands::Api
  subcommand "completion", Sure::CLI::Commands::Completion
end
```

`Sure::CLI::Base` provides `runtime`, `context`, `config`, `profile`, `output`, and `client` helpers, and calls `check_unknown_options!` in every command class. `Sure::CLI::Context` resolves config/profile/credential/output once per command. `Sure::CLI::Runtime` wraps injected IO, env, cwd, clock, and `Runtime.current` for Thor's instance model. Tests inject a fake runtime instead of touching real `STDIN`/`STDOUT`. `check_unknown_options!` is required so a forbidden `--api-key` is rejected rather than silently ignored.

### Operation Catalog Shape

`cli/config/operations.yml` is the machine-readable source for help examples, completion, and Phase 7 copy-commands. The YAML is loaded with `YAML.safe_load_file(..., aliases: false)`; no ERB, no Ruby evaluation. `Catalog::Loader` resolves the file relative to the gem root (`lib/sure/catalog/loader.rb` → `../../../config/operations.yml`), not the current directory, so both `exe/sure` and an installed gem work from any shell.

```yaml
schema_version: 1
commands:
  auth.login:
    path: [auth, login]
    summary: "Store an API key for a profile"
    description: |
      Validates the key against GET /api/v1/usage, then stores it in the OS
      keychain or a 0600 credential file.
    risk: local_write
    status: implemented
    aliases: []
    arguments: []
    options:
      - name: api-key-file
        type: string
        description: "Read the key from a file"
      - name: api-key-stdin
        type: boolean
        description: "Read the key from stdin"
    examples:
      - "sure auth login --server https://sure.example.com"
      - "printf '%s' \"$SURE_API_KEY\" | sure auth login --api-key-stdin"
    api:
      method: null
      path: null
    version_added: "0.1.0"

  api:
    path: [api]
    summary: "Call a Sure /api/v1 endpoint"
    risk: destructive
    status: implemented
    aliases: []
    arguments:
      - name: method
        required: true
      - name: path
        required: true
    options:
      - name: data
        type: string
      - name: raw
        type: boolean
      - name: dry-run
        type: boolean
      - name: "yes"
        type: boolean
    examples:
      - "sure api GET /api/v1/accounts"
      - "sure api GET '/api/v1/accounts?per_page=5' --json"
      - "sure api POST /api/v1/tags --data '{\"tag\":{\"name\":\"trip\"}}' --dry-run"
    api:
      method: null
      path: "/api/v1/*"
    version_added: "0.1.0"
```

`Catalog::Validator` must fail when an implemented catalog entry has no matching Thor command, when a Thor command has no catalog entry, or when paths are duplicated. Planned entries use `status: planned` and are excluded from help/completion until implemented. Do not add empty command groups for future `accounts`/`transactions` domains merely to activate aliases; D-02 aliases become active when those groups exist.

Each `Commands::*` class looks up its catalog entry at definition time (`Sure::Catalog.fetch("auth.login")`) to populate `desc`, `long_desc` examples, and option descriptions. The validator compares Thor's command tree with the catalog so help/examples/completion cannot drift.

The catalog test fixture should include planned `accounts.list` and `transactions.add` entries with canonical full names and realistic examples. Mark them `status: planned`; they validate the schema and future help shape but must not appear in Phase 1 help or completion because those commands are not implemented until Phases 2–3. This preserves the reference examples without shipping dead commands.

### Configuration Layers

`Config::Paths` resolves:

1. `XDG_CONFIG_HOME` when set and absolute → `$XDG_CONFIG_HOME/sure`
2. Windows `%APPDATA%` → `%APPDATA%\sure`
3. `~/.config/sure` otherwise

Files:

```text
config.yml          # non-secret profiles/settings; mode 0600
credentials.json    # only when file fallback is active; mode 0600
credentials.lock    # flock target; mode 0600
```

Directory mode is `0700`. Refuse symlinked config directories/files and files not owned by the current user. Never store secrets in `config.yml`.

```yaml
schema_version: 1
default_profile: default
profiles:
  default:
    server_url: https://sure.example.com/sure
    ca_bundle: null
    tls_verify: true
    open_timeout: 5
    read_timeout: 30
    output: null
    read_only: false
    credential_store: keychain    # keychain | file, set after successful login
    scopes: [read]                # cached from /usage; non-secret
    plaintext_warning_shown: false
```

Resolution precedence:

| Setting | CLI flag | Environment | Profile | Default |
|---------|----------|-------------|---------|---------|
| Profile | `--profile` | `SURE_PROFILE` | `default_profile` | `"default"` |
| Server | `--server` | `SURE_SERVER` | `profiles.<p>.server_url` | none — error 2 |
| CA bundle | `--ca-bundle` | `SURE_CA_BUNDLE` | `profiles.<p>.ca_bundle` | system trust |
| TLS verify | `--insecure` | `SURE_INSECURE` | `profiles.<p>.tls_verify == false` | `true` |
| Output | `--json`/`--table`/`--csv`/`--ndjson` | `SURE_OUTPUT` | `profiles.<p>.output` | table on TTY, JSON on pipe |
| Color | `--no-color` | `NO_COLOR` | — | TTY only |
| API key | — | `SURE_API_KEY` | credential store | none — error 3 |

`Config::Resolver` returns an immutable `Config::Profile` with a `source` map for diagnostics. `--server` on ordinary commands is ephemeral; `sure auth login --server ...` writes the server URL into the selected profile only after the key validates. `sure auth logout` keeps the profile/server URL and deletes only the credential. Phase 1 does not add a `sure config` command group; profiles are created/updated by `sure auth login` and can be edited in `config.yml`.

`SURE_INSECURE` accepts only `1/true/yes/on` or `0/false/no/off`; anything else is exit 2. `SURE_OUTPUT` accepts only `table|json|csv|ndjson`; anything else is exit 2. `--ca-bundle` and `--insecure` together are exit 2. TLS is verified by default. `--insecure` and non-loopback `http://` print a one-line stderr warning but are allowed for self-hosted setups.

### Request Pipeline

Every command uses one `Sure::HTTP::Client`. The pipeline is:

```text
command -> Context -> Auth::ApiKeyProvider -> HTTP::Client
  -> HTTP::UrlBuilder (prefix-preserving)
  -> Faraday connection
       request :json
       request :retry
       auth middleware (X-Api-Key only)
       net_http adapter (open/read timeouts, TLS)
       response :json (preserve_raw: true)
       response :raise_error (include_request: false)
  -> HTTP::Response (status, parsed body, raw body, headers, request_id, rate_limit, duration)
  -> Output::Result / Errors::Mapper
```

```ruby
Faraday.new do |f|
  f.request :json
  f.request :retry,
    max: 2,
    interval: 0.5,
    interval_randomness: 0.5,
    backoff_factor: 2,
    max_interval: 10,
    retry_statuses: [429, 502, 503, 504],
    methods: %i[get head],
    rate_limit_retry_header: "Retry-After",
    rate_limit_reset_header: "X-RateLimit-Reset"

  f.use Sure::HTTP::AuthMiddleware, auth_provider

  f.response :json,
    content_type: /\bjson$/,
    preserve_raw: true,
    parser_options: { allow_nan: true }
  f.response :raise_error, include_request: false

  f.adapter :net_http
  f.options.open_timeout = profile.open_timeout
  f.options.timeout = profile.read_timeout
  f.ssl.verify = profile.tls_verify
  f.ssl.ca_file = profile.ca_bundle if profile.ca_bundle
end
```

Critical details:

- `include_request: false` prevents Faraday's `RaiseError` from attaching request headers — including `X-Api-Key` — to exceptions.
- `methods: %i[get head]` overrides Faraday Retry's default idempotent list (`delete`, `get`, `head`, `options`, `put`). Never retry POST/PUT/PATCH/DELETE.
- `max_interval: 10` caps `Retry-After`/`X-RateLimit-Reset` waits. If the server says 3,500 seconds, faraday-retry returns the 429 response instead of sleeping; mapper emits exit 6 with the reset hint.
- `X-RateLimit-Reset` from Sure is **seconds remaining**, not an epoch. `Retry-After` is also seconds remaining. Do not call `Time.at` on them.
- `parser_options: { allow_nan: true }` handles self-hosted `/usage` responses that serialize `NoopApiRateLimiter`'s `Float::INFINITY`. Normal JSON output must not emit `Infinity`/`NaN`: `Output::Json` recursively replaces non-finite numbers with `nil` and adds a warning. `--raw` is the only exact passthrough.
- Do not add a Faraday logger middleware. `--verbose` logs method, sanitized path, status, duration, and request ID to stderr; never headers, query values that look like secrets, or bodies.
- Do not follow redirects. A 3xx is an error (exit 8); the key must never be forwarded to a redirect target.
- `User-Agent: sure-cli/<version>` and `Accept: application/json`; no family/tenant ID is ever sent. Tenancy is derived server-side from the key.

`Sure::Redactor` is a leaf module used by every error/verbose/support path. It owns `SENSITIVE_HEADERS = %w[authorization x-api-key proxy-authorization]`, `redact_headers`, `redact_value`, and `scrub_env`. It must mask `Bearer ...`, `X-Api-Key: ...`, `api_key=...`, JSON keys such as `api_key`/`access_token`/`refresh_token`/`secret`, and 64-hex key-shaped strings. It is applied to server `message` text, Thor errors, exception messages, verbose lines, and `sure api --dry-run` output. It never logs request bodies by default.

`Response#rate_limit` parses `X-RateLimit-Limit`, `X-RateLimit-Remaining`, `X-RateLimit-Reset`, and `Retry-After` into integers or `nil`. It must tolerate missing headers, `"Infinity"`, and self-hosted `tier: "noop"`.

`HTTP::Envelope.normalize(payload, collection_key: nil)` normalizes the API's two collection shapes:

```json
{"accounts": [], "pagination": {"page": 1, "per_page": 25, "total_count": 0, "total_pages": 0}}
```

```json
{"data": [], "meta": {"current_page": 1, "next_page": 2, "total_pages": 3, "total_count": 51, "per_page": 25}}
```

`next_page` may be absent (syncs, exports, accounts). Derive it from `page < total_pages`; otherwise stop. `per_page` is 1–100 (server default 25). Phase 1 only needs the adapter and two tests; full `--all` streaming is Phase 2.

### Credential Store

```ruby
Sure::Auth::Credential      # kind, secret, server_url, created_at
Sure::Auth::CredentialKey   # service, account, origin_fingerprint, profile
Sure::Auth::Store           # read(key) -> Credential?; write(key, cred); delete(key); mode; location
Sure::Auth::FileStore
Sure::Auth::MacKeychainStore
Sure::Auth::SecretServiceStore
Sure::Auth::StoreFactory
Sure::Auth::CommandRunner
```

`StoreFactory` selects `FileStore` when `profiles.<p>.credential_store == "file"`, selects the platform keychain when it is `"keychain"`, and otherwise auto-detects keychain then file. A keychain write failure switches the profile to `file` and warns once; a keychain read failure may use the file copy only when one exists. Login writes the actual selected mode back to config.

Store naming:

- Service: `sure-cli`
- Account: `"#{profile}@#{Digest::SHA256.hexdigest(normalized_origin)[0, 16]}"`
- macOS label: `"Sure CLI: #{profile} (#{host})"`
- Linux Secret Service attributes: `service=sure-cli profile=<profile> origin=<fingerprint>`
- File JSON key: the same `profile@fingerprint` string

macOS:

```ruby
# Read: secret goes to stdout, never argv.
Open3.capture3(clean_env, "security", "find-generic-password",
               "-a", account, "-s", "sure-cli", "-w")

# Write: valueless -w at end, secret on stdin; verify by read-back.
Open3.capture3(clean_env, "security", "add-generic-password", "-U",
               "-a", account, "-s", "sure-cli", "-w",
               stdin_data: secret)
```

The valueless `-w` behavior is **not documented by Apple** and has varied by macOS release. `MacKeychainStore#write` must read back and compare; if write/read-back fails or hangs (2-second timeout), fall back to `FileStore`. Strip exactly one trailing newline from `find-generic-password -w` output. Never use `security ... -w "$secret"` or put the secret in an argument array.

Linux:

```ruby
Open3.capture3(clean_env, "secret-tool", "store", "--label", label,
               "service", "sure-cli", "profile", profile, "origin", fingerprint,
               stdin_data: secret)

Open3.capture3(clean_env, "secret-tool", "lookup",
               "service", "sure-cli", "profile", profile, "origin", fingerprint)

Open3.capture3(clean_env, "secret-tool", "clear",
               "service", "sure-cli", "profile", profile, "origin", fingerprint)
```

`secret-tool` reads the password from stdin and adds a newline on TTY lookup. Strip exactly one trailing newline, not arbitrary whitespace. It needs a running Secret Service (GNOME Keyring/KWallet). If `secret-tool` is absent or `DBUS_SESSION_BUS_ADDRESS` is unusable, fall back to file.

`Auth::CommandRunner` must scrub `SURE_API_KEY` (and any future token env vars) from the child environment. Preserve only what the helper needs (`PATH`, `HOME`, `USER`, `LOGNAME`, `TMPDIR`, and `DBUS_SESSION_BUS_ADDRESS` for `secret-tool`). The keychain helper must never receive the secret through `ENV` or argv. Use `Open3.capture3` with an explicit minimal environment; no shell string interpolation.

File fallback:

```json
{
  "schema_version": 1,
  "credentials": {
    "default@a1b2c3d4e5f6a7b8": {
      "kind": "api_key",
      "secret": "...",
      "server_url": "https://sure.example.com/sure",
      "created_at": "2026-10-31T12:00:00Z"
    }
  }
}
```

`FileStore#write` takes an exclusive `flock`, re-reads, merges, writes a temp file in the same directory with mode 0600, `flush`/`fsync`, closes, `File.rename`, and fsyncs the directory (rescue unsupported platforms). Refuse symlink targets. `FileStore#read` refuses group/world-readable or symlinked files and raises a general config error with a `chmod 600` fix. `FileStore#delete` removes only the matching key and deletes the file when empty.

`Auth::Login` order is mandatory:

1. Resolve profile name and server URL.
2. Read key from `--api-key-file` > `--api-key-stdin` > `SURE_API_KEY` > hidden prompt (TTY only).
3. Cap input at 4 KiB, strip one trailing CR/LF, reject internal CR/LF/NUL and empty keys; never echo the value.
4. Build an ephemeral provider and call `GET /api/v1/usage`.
5. On 200, write the credential (keychain, then file fallback), then atomically update config with `server_url`, `scopes`, and `credential_store`.
6. If config write fails, delete the just-written credential and fail.
7. If file fallback was used and `plaintext_warning_shown` is false, print the one-time warning and set the marker.

`Auth::Logout` deletes the key from both the configured store and any file fallback copy, clears cached scopes, and prints the Settings → API Keys revocation guidance. If `SURE_API_KEY` is set, warn that it remains active in the shell.

`Auth::Status` calls `/usage`, reads `api_key.name`, `api_key.scopes`, rate-limit fields, and the optional user object. It shows `authentication_method: "api_key"` and `credential_source: "environment" | "keychain" | "file"`. It never reads or prints the secret.

```json
{
  "data": {
    "profile": "default",
    "server_url": "https://sure.example.com/sure",
    "user": {"email": "user@example.com", "first_name": "Ada", "last_name": "Lovelace"},
    "authentication_method": "api_key",
    "credential_source": "keychain",
    "api_key": {"name": "CLI laptop", "scopes": ["read"], "last_used_at": "2026-10-31T12:00:00Z", "created_at": "2026-10-30T09:00:00Z"},
    "rate_limit": {"tier": "standard", "limit": 100, "remaining": 96, "reset_in_seconds": 2314}
  },
  "meta": {"schema_version": 1, "as_of": "2026-10-31T12:00:01Z", "warnings": []}
}
```

If the server omits `user`, emit `"user": null` plus a warning in `meta.warnings`; do not substitute the profile name.

`Auth::ScopePreflight` is the only write guard:

```ruby
WRITE_METHODS = %w[POST PUT PATCH DELETE].freeze

def ensure!(method:)
  return unless WRITE_METHODS.include?(method)
  raise Errors::InsufficientScopeError, "Profile is read-only" if profile.read_only

  scopes = credential_source == :environment ? nil : profile.scopes
  scopes = fetch_scopes_from_usage if scopes.nil? || scopes.empty?
  return if scopes.include?("read_write")

  raise Errors::InsufficientScopeError,
        "This profile's API key is read-only (scopes: #{scopes.join(', ')}). " \
        "Create a read_write key in Sure Settings → API Keys and log in again."
end
```

Cached `scopes` from login/status avoid an extra `/usage` request; if absent, fetch once and persist. When the active credential comes from `SURE_API_KEY`, never trust the profile cache — fetch scopes for that environment key every time. A server-side 403 still maps to exit 3 because scope can change after login.

**Contract gap — user identity:** the current `UsageController#show` returns only `api_key` and `rate_limit`; it does **not** return a user. `[VERIFIED: codebase: app/controllers/api/v1/usage_controller.rb:6-24]` There is no readable `GET /api/v1/me`; `users/me` is DELETE-only, and `family_settings` returns family settings, not the user. `[VERIFIED: codebase: config/routes.rb:813,832-834; app/controllers/api/v1/family_settings_controller.rb:6-8]` Therefore D-09/AUTH-03 cannot be fully satisfied from the current API. The only truthful, non-fabricated fix is a small additive `user` object on the API-key branch of `GET /api/v1/usage` (`email`, `first_name`, `last_name`), following the existing `mobile_user_payload` shape. `[VERIFIED: codebase: app/controllers/api/v1/auth_controller.rb:489-494]` Plan 01-04 should include that additive server change plus Minitest/rswag coverage, or explicitly mark AUTH-03 partial rather than inventing a user from the profile or key name. Do not add a new endpoint; the existing `/usage` endpoint has `@current_user` available.

### Output Contract

```ruby
Sure::Output::Result = Data.define(:data, :meta, :columns, :footer)
Sure::Output::Column = Data.define(:key, :label, :align, :formatter)
Sure::Output::Base#render(result)
Sure::Output::Json
Sure::Output::Table
Sure::Output::Csv
Sure::Output::Ndjson
Sure::Output::Selector
Sure::Output::FieldSelection
```

`Output::Selector` chooses:

1. `--json`, `--table`, `--csv`, or `--ndjson` (mutually exclusive)
2. `SURE_OUTPUT`
3. `profiles.<p>.output`
4. `stdout.tty? ? :table : :json`

Color is enabled only when `stdout.tty?`, `options[:color]` is true, `NO_COLOR` is absent, and `TERM != "dumb"`. `--no-color` sets `options[:color]` false; JSON/CSV/NDJSON never color.

JSON is one compact document plus newline:

```json
{"data":{},"meta":{"schema_version":1,"as_of":"2026-10-31T12:00:00Z","warnings":[],"rate_limit":{"limit":100,"remaining":99,"reset_in_seconds":120,"tier":"standard"}}}
```

Always include `schema_version` and `warnings`; include `pagination`/`rate_limit`/`as_of` when applicable. Do not dump arbitrary server payloads in normal mode. `--raw` is only for `sure api` and emits the exact response body, no envelope. `Output::Json` recursively normalizes non-finite floats (`Infinity`, `NaN`) to `nil` and appends a warning so stdout is always valid JSON.

CSV uses `CSV.generate` with a header row; never hand-quote. NDJSON emits one JSON object per data item, one per line; if `--fields` is set, project each item. Table uses `Terminal::Table` with explicit columns and no color when piped.

`--quiet` suppresses progress and non-error warnings on stderr; it never suppresses the requested data. `--verbose` adds request IDs/timings to stderr but never headers or bodies. `--quiet`/`--verbose` are mutually exclusive; `--no-color` is compatible with both.

`--fields` is a comma-separated allowlist. Validate against `Result#columns` or the top-level object keys. Unknown fields are exit 2. Apply to JSON (project), table (select columns), CSV (select columns), and NDJSON (project each record). `--fields` with `--raw` is exit 2.

`auth login` and `auth logout` also render `Output::Result`; their `data` contains only non-secret facts such as `profile`, `server_url`, `credential_source`, `scopes`, and `deleted`. This keeps piped output valid JSON and never exposes the key. `doctor` returns `data.checks`.

### Exit-Code Mapping

| Condition | Error class | Exit |
|-----------|-------------|------|
| Success, including 204/empty body | — | 0 |
| Unexpected local error | `Errors::GeneralError` | 1 |
| Thor parse error, unknown option, invalid method/path, missing server, confirmation required | `Errors::UsageError` | 2 |
| 401, invalid/expired key, 403 `insufficient_scope`/`forbidden`, missing credential, read-only preflight | `Errors::AuthenticationError` / `InsufficientScopeError` | 3 |
| 404 | `Errors::NotFoundError` | 4 |
| 400, 409, 422 | `Errors::ValidationError` | 5 |
| 429 | `Errors::RateLimitedError` | 6 |
| Any batch item failed (reserved for Phase 3+) | `Errors::PartialFailureError` | 7 |
| Connection/TLS failure, 5xx, 3xx, malformed response | `Errors::NetworkError` | 8 |
| Timeout (408, 504, `Faraday::TimeoutError`, `Timeout::Error`) | `Errors::TimeoutError` | 9 |
| SIGINT | `Interrupt` boundary | 130 (shell signal convention, outside D-13's 0–9 semantic list) |

`sure doctor` returns the exit code of the **first failed check in check order**; warnings alone return 0. `sure auth logout` with no stored credential is idempotent success (0). `sure auth status` with no credential is 3. `sure api --dry-run` is 0 and makes no network request. `EPIPE` should exit 0 quietly (Thor already handles `Errno::EPIPE` in `start`). `[VERIFIED: Thor v1.5.0 lib/thor/base.rb]`

### Command Semantics

| Command | Behavior | Exit / failure |
|---------|----------|----------------|
| `sure --version`, `sure version` | Prints `sure 0.1.0`; no config/auth/Rails load | 0 |
| `sure help`, `sure help auth login` | Thor help plus catalog examples | 0; unknown command 2 |
| `sure auth login` | Hidden prompt by default; `--api-key-file`, `--api-key-stdin`, `SURE_API_KEY`; validates `/usage` before storing | 0; bad key 3; no TTY/no input 2; network 8 |
| `sure auth status` | Table/JSON: profile, server, user (if server exposes), key name, scopes, auth method, credential source, rate-limit tier | 0; no credential 3; API error mapped |
| `sure auth logout` | Deletes local credential; explains Server Settings revocation; warns about `SURE_API_KEY` | 0; store error 1 |
| `sure doctor` | Non-short-circuiting checklist with fixes; `--json` envelope | First failed check; 0 if only warnings |
| `sure api METHOD PATH` | `/api/v1`-only path, normal auth/tenancy/redaction; `--data` JSON; `--raw`; `--dry-run`; `--yes` for writes | 0; invalid path/method 2; write without `--yes` non-TTY 2; scope 3; HTTP mapped |
| `sure completion SHELL` | Static completion script from catalog for `bash`, `zsh`, or `fish` | 0; unsupported shell 2 |

`auth login` requires a server URL from `--server`, `SURE_SERVER`, or an existing profile. Do not prompt for a URL; if missing, exit 2 with an actionable message. `auth login` accepts read-only keys; it reports the scope rather than failing. `--api-key-file` and `--api-key-stdin` are mutually exclusive (exit 2); `--api-key-file -` is rejected in favor of `--api-key-stdin`; a group/world-readable source file produces a warning but is still read. Explicit input flags beat `SURE_API_KEY`, which beats the TTY prompt.

`sure api` path validation: must start with `/api/v1` after URI parsing; reject scheme/host, fragments, CR/LF, `..`, and percent-encoded traversal. `GET`/`HEAD` with `--data` are exit 2. It may contain a query string. No `--header` option (prevents overriding auth). Write methods (`POST`, `PUT`, `PATCH`, `DELETE`) require `--yes` on a TTY; non-TTY without `--yes` is exit 2. `--dry-run` prints method, fully joined URL, and JSON body; it does not read the credential, preflight scope, or make a request. `--raw` conflicts with output format flags and `--fields`. Normal `sure api` output sets `data` to the parsed response body and adds `http_status`, `request_id`, and `rate_limit` to `meta`.

### Completion Generator

`Completion::Generator#render(shell)` loads `Catalog`, filters `status: implemented`, and writes a static script to stdout. `SHELLS = %w[bash zsh fish]`. Bash must stay compatible with macOS `/bin/bash` 3.2 (no associative arrays, no `mapfile`); zsh starts with `#compdef sure`; fish uses `complete -c sure`. Include global flags, implemented command paths, and aliases from the catalog. No network calls and no secrets in scripts. Snapshot the three scripts and run `bash -n` when bash is available.

### Doctor Checks

| Order | Check | Failure code | Notes |
|-------|-------|--------------|-------|
| 1 | Config directory/file exists, not symlinked, owned by user, mode 0700/0600 | 1 | Report exact `chmod` fix |
| 2 | Profile name and server URL parse; scheme `http`/`https`; no userinfo/query/fragment; path prefix normalized | 2 | `http` non-loopback warns, not fail |
| 3 | Credential present from store or `SURE_API_KEY` | 3 | Report source and storage mode |
| 4 | Connectivity/TLS via `GET /api/v1/usage`: 200/401/403 proves reachability; 404/5xx/TLS error fails | 8 | Uses the real prefix path |
| 5 | Authentication: `/usage` returns 200 | 3 | 401/403 actionable |
| 6 | Scope: parse `api_key.scopes`; `read` is a warning for writes; missing/invalid is failure | 3 | `read_write` includes `read` |
| 7 | Server capability: `GET /api/v1/accounts?per_page=1` returns 200 with `accounts` + `pagination` | 8 | No version endpoint exists; this is the compatibility probe |
| 8 | Clock skew from HTTP `Date` header; >300s fails | 1 | Skip if header absent |
| 9 | Rate-limit tier/remaining from `/usage` or headers | 0 | `noop`/self-hosted → unlimited |

Doctor runs all independent checks even when an earlier one fails, so the user sees the whole checklist. Checks that depend on a failed prerequisite are `SKIP`, not secondary failures: without a credential, auth/scope/capability/rate-limit checks are skipped after the credential check fails; without connectivity, authenticated checks are skipped. Each check has `fix` text. `--json` returns `{data: {checks: [...]}, meta: {...}}`; human output uses `PASS`, `WARN`, `FAIL`, `SKIP` ASCII labels (no Unicode symbols).

### Anti-Patterns

- **Fat command classes** that build URLs, read credentials, print tables, and call `exit`. Use `Commands::*` → service → `Output::*`.
- **A second HTTP path** for `sure api` or doctor. Both must use `HTTP::Client`.
- **A second config parser** in commands. Only `Config::Resolver`.
- **Raw server JSON as the default.** Use `Output::Result`; `--raw` is opt-in.
- **Formatting money or recomputing totals.** Phase 1 formatters preserve values as-is.
- **A hardcoded localhost default server.** Missing server is an actionable error, not a silent send to the wrong host.
- **Retrying writes because faraday-retry defaults to DELETE/PUT.** Always set `methods: %i[get head]`.
- **Using `URI.join` with an absolute API path.** It drops the server's path prefix.

## Don't Hand-Roll

| Problem | Don't Build | Use Instead | Why |
|---------|-------------|-------------|-----|
| Command tree, aliases, help, option parsing | Hand-written `OptionParser` or argv scanner | Thor 1.5.0 | Nested commands, aliases, help, enums, exclusive options, Rails lineage |
| HTTP transport, JSON encode/decode, timeouts, TLS | `Net::HTTP` wrapper | Faraday 2.14.3 + `faraday-net_http` | Middleware, connection reuse, TLS options, parse errors |
| Retry/backoff/`Retry-After` | Custom loop around `Net::HTTP` | faraday-retry 2.3.2 | Jitter, backoff, status retries, header parsing, `max_interval` cap |
| JSON parsing/generation | String concatenation | stdlib `JSON` 2.21.2 | Escaping, UTF-8, stable serialization |
| CSV escaping | `join(",")` | stdlib `csv` 3.3.5 / `CSV.generate` | Quotes, commas, newlines, encoding |
| YAML parsing | `YAML.load` | `YAML.safe_load_file(..., aliases: false)` | No object deserialization, no alias bombs |
| Tables | `printf` column math | terminal-table 4.0.0 | Unicode width, alignment, truncation |
| Color | Hand-rolled ANSI | pastel 0.8.0 | Enable/disable, TTY-aware, no escape leaks |
| Hidden secret prompt | `stty -echo`, shell `read -s` | stdlib `io/console` `getpass`/`noecho` | Cross-platform, no subprocess, no echo |
| OS keychain access | `keyring`/`libsecret`/`system_keychain` gems | `security` on macOS, `secret-tool` on Linux | Those gems are abandoned or native-dependent; OS tools already exist |
| Atomic file writes | `File.write` in place | `Tempfile.create` in same dir + `fsync` + `File.rename` + `flock` | Crash safety, no partial credentials |
| URL joining with prefix | `URI.join` | `HTTP::UrlBuilder` using `URI` path concatenation | `URI.join` drops `/sure` when given `/api/v1/...` |
| HTTP date parsing | Regex/Split | `Time.httpdate` | RFC 7231 date formats |
| OS detection | `uname` shell call / `Etc.uname` | `RbConfig::CONFIG["host_os"]`, `Gem.win_platform?` | No subprocess, works on Windows |
| Shell completion | A cross-shell parser or `completely` (bash only) | Catalog-driven static templates | Small, deterministic, no new dependency; Thor has no completion module |
| ERB templates | ERB for scripts/help | Plain Ruby heredocs / catalog strings | No template dependency; no ERB in a CLI gem |
| Redirect handling | Manual `Location` follow | Do not follow redirects | Prevents forwarding `X-Api-Key` to another host |
| CLI exit handling | `exit` in commands | One `CLI::Runner` boundary | Stable codes, no backtraces, testable |

**Key insight:** the only genuinely app-specific logic is the Sure contract (paths, scopes, error strings, pagination envelopes, credential naming). Everything generic — parsing, HTTP, retries, tables, CSV, JSON, keychain plumbing, atomic writes — has a mature, already-proven implementation.

## Common Pitfalls

### Pitfall 1: Credential leakage through argv, env, logs, exceptions, or backtraces

**What goes wrong:** a key appears in `ps`, shell history, Thor's unknown-option message, Faraday exception details, debug logs, or a copied command. Faraday's `RaiseError` attaches request headers by default, including `X-Api-Key`, to the exception response. `[VERIFIED: Faraday v2.14.3 lib/faraday/response/raise_error.rb]`

**Why it happens:** a `--api-key` flag is convenient; logging middleware logs headers; `exception.inspect` includes request data; macOS `security` accepts `-w password` in argv.

**How to avoid:** no `--api-key` option at all; hidden prompt/stdin/file/`SURE_API_KEY` only; `f.response :raise_error, include_request: false`; no Faraday logger; `--verbose` logs only method, sanitized path, status, duration, request ID; run all error strings through `Redactor`; never pass the secret to `security` argv; use valueless `-w` with stdin and verify/fallback; `secret-tool` only via stdin; scrub `SURE_API_KEY` from child-process env; refuse to echo the key in `auth status` or `logout`.

**Warning signs:** a help screen or README shows `--api-key`; an exception message contains `headers`; a debug log contains `X-Api-Key`; a test can find the fake key in stdout/stderr.

### Pitfall 2: TTY detection and prompting in the wrong process

**What goes wrong:** the CLI prompts inside a pipe, hangs CI, or emits a table into `jq`. Tests pass because they use the process's real `STDIN`/`STDOUT` instead of injected IO.

**Why it happens:** `STDIN.tty?` is used instead of the runtime's stdin; `sure auth login --api-key-stdin` is confused with the default prompt; output uses `puts` without considering `stdout.tty?`.

**How to avoid:** `Runtime` carries injectable `stdin`, `stdout`, `stderr`; every TTY check uses `runtime.stdin.tty?` or `runtime.stdout.tty?`; default output is table only when stdout is a TTY; prompts and warnings go to stderr; when stdin is not a TTY, fail with exit 2 and name `--api-key-file`, `--api-key-stdin`, or `SURE_API_KEY`; `sure api` write confirmation requires `--yes` when non-TTY; `--api-key-stdin` is the explicit exception that reads a pipe.

**Warning signs:** a test hangs on a prompt; `sure auth status | jq` receives table characters; a pipe receives ANSI escapes.

### Pitfall 3: Exit-code drift, especially Thor's default exit 1

**What goes wrong:** an auth failure exits 1, a usage error exits 1, and scripts cannot distinguish them. Thor's default `start` catches `Thor::Error`, prints it, and exits 1; `exit_on_failure? true` also exits 1.

**Why it happens:** commands call `exit`; Thor errors are not mapped; server 403 is treated like a generic error; timeout and network failures share 1.

**How to avoid:** one `CLI::Runner` boundary; `Application.start(argv, debug: true)` to re-raise Thor errors; `exit_on_failure? false`; `Errors::Mapper` owns HTTP/status mapping; commands return data or raise typed errors; never `exit` in command/service code; map 401/403 → 3, 404 → 4, 400/409/422 → 5, 429 → 6, 5xx/TLS/connection → 8, timeout → 9; reserve 7 for batches. Test every code.

**Warning signs:** the same failure exits 1 in one command and 3 in another; a `rescue => e` in a command calls `abort`; a spec asserts only "nonzero".

### Pitfall 4: Path-prefixed server URLs are silently dropped

**What goes wrong:** `https://host/sure` becomes `https://host/api/v1/accounts`; every request 404s or, worse, hits a different app at the origin root.

**Why it happens:** `URI.join("https://host/sure", "/api/v1/accounts")` treats the second argument as an absolute path and replaces `/sure`.

**How to avoid:** `HTTP::UrlBuilder` parses the server once, strips trailing slashes, preserves the path prefix, and concatenates a validated relative API path: `prefix + path`; never use `URI.join` for API paths; do not accept a server URL ending in `/api/v1`; do not follow redirects; test `https://host/sure` + `/api/v1/accounts` explicitly.

**Warning signs:** requests work at the origin root but not under the documented mount; a `/sure/sure/api/v1` double prefix; a redirect followed to an unexpected host.

### Pitfall 5: TLS CA handling is wrong or leaks the key over insecure transport

**What goes wrong:** `--ca-bundle` is ignored because only `verify` is set; a relative CA path resolves from the wrong directory; `--insecure` is silently enabled by config; an HTTPS error becomes a generic exit 1.

**Why it happens:** Faraday uses `ssl.ca_file`, not `ca_path`, for a PEM bundle; config path resolution is ambiguous; insecure flags are easy to leave on.

**How to avoid:** set `f.ssl.verify = true` and `f.ssl.ca_file = expanded_path`; resolve profile-relative CA paths against the config directory and flag-relative paths against cwd; validate readability before the request; `--insecure` and `SURE_INSECURE` set `verify: false` only when explicitly true; warn on stderr and report in doctor; map `Faraday::SSLError`/`OpenSSL::SSL::SSLError` to 8 with a CA/`--insecure` hint; reject `--ca-bundle` + `--insecure` as exit 2.

**Warning signs:** a self-signed server works only with `--insecure` despite `--ca-bundle`; doctor says TLS pass while the request fails; the CA path is relative to the shell, not config.

### Pitfall 6: Keychain absence, locked keychains, and headless Linux

**What goes wrong:** login hangs on a locked keychain or a missing D-Bus session; the CLI claims keychain storage but the credential is in a file; logout leaves a stale copy; the macOS `security` command leaks the key in argv.

**Why it happens:** keychain tools are interactive and platform-specific; `secret-tool` needs a running Secret Service; macOS `security` is undocumented for stdin writes.

**How to avoid:** detect `security` on macOS and `secret-tool` + usable `DBUS_SESSION_BUS_ADDRESS` on Linux; wrap keychain commands in a 2-second timeout; write macOS key with valueless `-w` and verify by read-back; if anything fails, fall back to file, set `credential_store: file`, and warn once; `secret-tool` writes via stdin; logout deletes from both stores; doctor reports the actual mode; Windows uses the file fallback (DPAPI is v2).

**Warning signs:** CI hangs at `sure auth login`; `auth status` says keychain but `credentials.json` contains the key; `ps` shows a key; logout succeeds but the key still authenticates.

### Pitfall 7: Config and credential files are too permissive or non-atomic

**What goes wrong:** a 0644 `credentials.json` exposes the key; a symlink redirects the write; a crash leaves a truncated file; a concurrent write loses another profile.

**Why it happens:** `File.write` uses the process umask; `Dir.mkdir` defaults to 0755; symlinks are followed.

**How to avoid:** directory 0700, files 0600; `File.lstat` and refuse symlinks; verify ownership; use `flock` around read-modify-write; write a same-directory `Tempfile` with mode 0600, `fsync`, close, `rename`, and fsync the directory; run `chmod` after rename; doctor checks modes and prints the exact fix; never put secrets in `config.yml`.

**Warning signs:** `ls -l` shows 0644; doctor reports a permission failure; two profiles overwrite each other; a crash leaves `.tmp` files.

### Pitfall 8: `Retry-After` and `X-RateLimit-Reset` are misread

**What goes wrong:** the CLI treats the values as Unix epochs and sleeps for decades, or ignores them and hammers the server; a long reset is retried immediately; a write is retried.

**Why it happens:** many APIs use epoch timestamps; Sure uses seconds remaining. `[VERIFIED: codebase: app/controllers/api/v1/base_controller.rb:147-171]`

**How to avoid:** parse both as seconds; faraday-retry with `rate_limit_retry_header: "Retry-After"` and `rate_limit_reset_header: "X-RateLimit-Reset"`; `max_interval: 10`; if the reset exceeds the cap, do not retry and map 429 to exit 6 with a reset hint; retry only `GET`/`HEAD`; test `Retry-After: 0`, `Retry-After: 2`, and a 3,500-second reset.

**Warning signs:** tests that sleep for minutes; 429 response followed immediately by another request; a POST retried after timeout.

### Pitfall 9: Assuming one pagination envelope or unbounded `per_page`

**What goes wrong:** page 2 is `nil`; `next_page` is absent; a requested `per_page=500` returns 100; different collections use `accounts`/`transactions`/`data` keys; deduplication is missing.

**Why it happens:** the first endpoint tested uses `{accounts, pagination}`; imports/rules use `{data, meta}` with `next_page`; syncs/exports use `{data, meta}` without it. `[VERIFIED: codebase: app/views/api/v1/accounts/index.json.jbuilder:3-11; app/views/api/v1/imports/index.json.jbuilder:17-24; app/views/api/v1/syncs/index.json.jbuilder:7-12]`

**How to avoid:** one `Envelope` adapter with per-collection `collection_key`; parse both `pagination` and `meta`; derive `next_page` when absent; clamp `per_page` to 1–100; never auto-paginate into memory; dedupe by `id` in Phase 2; test two pages for each shape. The server clamps `per_page` to 100 and defaults to 25. `[VERIFIED: codebase: app/controllers/api/v1/base_controller.rb:242-254]`

**Warning signs:** page 2 nil errors; row count differs from `total_count`; `--all` grows memory without bound.

### Pitfall 10: Ruby 3.4 frozen-string and bundled-gem surprises

**What goes wrong:** `# frozen_string_literal: true` makes `<<` on a literal raise; `base64` is no longer a default gem; `csv` is bundled and may not be available unless declared; YAML `load` is unsafe; `Hash#except` from ActiveSupport is unavailable.

**Why it happens:** the CLI is plain Ruby, not Rails; developers copy server idioms.

**How to avoid:** `# frozen_string_literal: true` in every file; mutate only `String.new`/`+""`; declare `csv ~> 3.3`; use `JSON` not `to_json` monkeypatches; use `YAML.safe_load_file(..., aliases: false)`; use `slice`/`transform_keys`, not ActiveSupport `except`; avoid `base64` (use `pack("m0")` only if ever needed); prefer `Data.define`/immutable value objects.

**Warning signs:** `FrozenError` in string building; `LoadError: cannot load such file -- csv`; `NoMethodError: undefined method 'except'`.

### Pitfall 11: Windows portability assumptions

**What goes wrong:** `File.chmod` is a no-op, `security`/`secret-tool` are absent, backslash paths break, ANSI escapes appear in redirected output, and `SIGINT`/`EPIPE` differ.

**Why it happens:** the first implementation targets macOS/Linux and assumes POSIX.

**How to avoid:** use `Gem.win_platform?`; config under `%APPDATA%\sure`; file fallback with `icacls` inheritance removal when available, otherwise warn; don't promise POSIX 0600 on Windows; use `File::ALT_SEPARATOR`; strip `\r` from stdin; pastel detects Windows color support; completion is bash/zsh/fish only; document DPAPI as v2.

**Warning signs:** a Windows user cannot log in; config is world-readable; a table contains `\e[32m`.

### Pitfall 12: `sure api` becomes an unsafe shell or bypasses scope

**What goes wrong:** a user can call `/up` or an arbitrary host with the API key; a `DELETE` runs without confirmation on a pipe; a read-only key sends the write and gets a 403; `--dry-run` still sends.

**Why it happens:** an escape hatch looks like a raw HTTP client; path/host validation is omitted; scope preflight is skipped.

**How to avoid:** validate method against `GET/HEAD/POST/PUT/PATCH/DELETE`; require the path to normalize under `/api/v1`; reject schemes/hosts/fragments/`..`; no `--header`; confirm writes on TTY and require `--yes` on non-TTY; `--dry-run` makes zero requests; preflight `read_write` for writes using cached scopes or `/usage`; redact errors.

**Warning signs:** `sure api GET https://evil.example` sends the key; a POST happens without `--yes`; a read-only key gets a 403 after sending a body.

### Pitfall 13: Contract drift and undocumented endpoints

**What goes wrong:** the CLI assumes a version endpoint, a user endpoint, or stable `/usage`; `GET /api/v1/usage` and `POST /api/v1/sync` are routed but absent from OpenAPI; self-hosted `/usage` returns `Infinity`/`noop`; older servers lack fields.

**Why it happens:** `docs/api/openapi.yaml` is generated from current specs, not every deployment; `/usage` is a convenience endpoint. `[VERIFIED: codebase: config/routes.rb:813,820; docs/llm-guides/architecture.md:142-149]`

**How to avoid:** treat `/usage` as a tolerant, optional contract; parse missing fields as `nil`; render `noop` as unlimited; do not invent `GET /api/v1/meta` or `GET /api/v1/me`; doctor probes `/usage` + `/accounts`; map 404/403 on a capability probe to "unsupported on this server"; pin an OpenAPI snapshot later. If adding a `user` field, update the server contract/tests deliberately.

**Warning signs:** a new server field breaks `auth status`; self-hosted shows `Infinity`; doctor passes but a command 404s.

### Pitfall 14: Output contamination, EPIPE, and color leaks

**What goes wrong:** progress dots or warnings land in stdout and break `jq`; a closed pipe prints a backtrace; JSON contains ANSI; table output crashes on `LC_ALL=C`.

**Why it happens:** `puts` is used everywhere; color is enabled before checking the destination; `Errno::EPIPE` is unhandled.

**How to avoid:** stdout only data; stderr for prompts/warnings/progress/verbose; formatter selection before rendering; disable color for JSON/CSV/NDJSON and when `NO_COLOR` is present or `--no-color` is set; use `NO_COLOR` presence, not value; ASCII status labels; let Thor handle `EPIPE` as success; trap `Interrupt` at the boundary.

**Warning signs:** `sure ... --json | jq` fails; `head` produces a backtrace; a piped table contains escape codes.

### Pitfall 15: The stale roadmap `--api-key` wording

**What goes wrong:** an executor implements `sure auth login --api-key` because `ROADMAP.md` success criterion 2 says it, contradicting D-07 and the project's no-argv-secret constraint.

**Why it happens:** the roadmap uses shorthand from an earlier iteration.

**How to avoid:** D-07 is authoritative. There is no `--api-key` flag. Help, completion, tests, and docs must assert that `--api-key` is unknown (exit 2) and that the only inputs are hidden prompt, `--api-key-file`, `--api-key-stdin`, and `SURE_API_KEY`. Redact a submitted `--api-key=...` value from Thor's error message.

**Warning signs:** `sure auth login --help` shows `--api-key`; a test passes a key in argv; shell history contains a key.

### Pitfall 16: Login stores a credential before validating it

**What goes wrong:** a typo or revoked key is persisted; `auth status` then fails until logout; the keychain warning is shown for an unusable key.

**Why it happens:** storage is implemented before the `/usage` probe.

**How to avoid:** probe `/usage` with an ephemeral provider first; only then write the credential and config; if the config write fails, delete the credential; never write a partial credential record; report the server's 401/403 without echoing the key.

**Warning signs:** a bad key remains in the keychain after login failure; `auth status` immediately 401s after a "successful" login.

## Code Examples

### API-key authentication is header-only

```ruby
# Source: app/controllers/api/v1/base_controller.rb:108-126
api_key_value = request.headers["X-Api-Key"]
return false unless api_key_value

@api_key = ApiKey.find_by_value(api_key_value)
return false unless @api_key && @api_key.active?

@current_user = @api_key.user
# ...
@authentication_method = :api_key
@rate_limiter = ApiRateLimiter.limit(@api_key)
```

CLI equivalent: `Auth::ApiKeyProvider#header` returns `{ "X-Api-Key" => credential.secret }`. Never a query parameter, never `Authorization: Bearer` in Phase 1.

### Scopes are hierarchical: `read_write` includes `read`

```ruby
# Source: app/controllers/api/v1/base_controller.rb:197-217
case required_scope.to_s
when "read"
  has_access = scopes.include?("read") || scopes.include?("read_write")
when "write"
  has_access = scopes.include?("read_write")
else
  has_access = scopes.include?(required_scope.to_s)
end
```

CLI equivalent: `Auth::ScopePreflight` accepts `read` or `read_write` for reads, and only `read_write` for writes. A `read` key never sends a write.

### Usage response shape (current; no user field)

```json
{
  "api_key": {
    "name": "Test API Key",
    "scopes": ["read"],
    "last_used_at": "2026-10-31T12:00:00Z",
    "created_at": "2026-10-30T09:00:00Z"
  },
  "rate_limit": {
    "tier": "standard",
    "limit": 100,
    "current_count": 4,
    "remaining": 96,
    "reset_in_seconds": 2314,
    "reset_at": "2026-10-31T13:00:00Z"
  }
}
```

Source: `app/controllers/api/v1/usage_controller.rb:6-24`; route: `config/routes.rb:813`. The response counts the `/usage` request itself, so `auth status` and `doctor` consume quota. `[VERIFIED: codebase: test/controllers/api/v1/usage_controller_test.rb:44-50]`

### Rate-limit headers and 429 shape

```ruby
# Source: app/controllers/api/v1/base_controller.rb:147-171
response.headers["X-RateLimit-Limit"] = usage_info[:rate_limit].to_s
response.headers["X-RateLimit-Remaining"] = "0"
response.headers["X-RateLimit-Reset"] = usage_info[:reset_time].to_s
response.headers["Retry-After"] = usage_info[:reset_time].to_s

render_json({
  error: "rate_limit_exceeded",
  message: "Rate limit exceeded. Try again in #{usage_info[:reset_time]} seconds.",
  details: {
    limit: usage_info[:rate_limit],
    current: usage_info[:current_count],
    reset_in_seconds: usage_info[:reset_time]
  }
}, status: :too_many_requests)
```

Both `Retry-After` and `X-RateLimit-Reset` are **seconds remaining**, not epochs. The successful-response headers set `X-RateLimit-Remaining` to the actual remaining count.

### Error JSON shapes

```json
{"error":"unauthorized","message":"Access token or API key is invalid, expired, or missing"}
```

```json
{"error":"insufficient_scope","message":"This action requires the 'read' scope"}
```

```json
{"error":"record_not_found","message":"The requested resource was not found"}
```

```json
{"error":"validation_failed","message":"...","errors":["..."]}
```

```json
{"error":"rate_limit_exceeded","message":"...","details":{"limit":100,"current":100,"reset_in_seconds":2314}}
```

Sources: `app/controllers/api/v1/base_controller.rb:173-176,256-278`; `docs/api/openapi.yaml:209-232`. The CLI should use the server `message` when present, add its own actionable hint, and never dump an arbitrary 5xx body.

### Collection envelopes

```json
{
  "accounts": [],
  "pagination": {"page": 1, "per_page": 25, "total_count": 0, "total_pages": 0}
}
```

```json
{
  "data": [],
  "meta": {"current_page": 1, "next_page": 2, "prev_page": null, "total_pages": 3, "total_count": 51, "per_page": 25}
}
```

```json
{
  "data": [],
  "meta": {"page": 1, "per_page": 25, "total_count": 0, "total_pages": 0}
}
```

Sources: `app/views/api/v1/accounts/index.json.jbuilder:3-11`; `app/views/api/v1/imports/index.json.jbuilder:17-24`; `app/views/api/v1/syncs/index.json.jbuilder:7-12`; `docs/api/openapi.yaml:119-138,583-594`.

### API key format and scope validation

```ruby
# Source: app/models/api_key.rb:45-47,100-107
def self.generate_secure_key
  SecureRandom.hex(32)          # 64 lowercase hex characters
end

# scopes can only be ["read"] or ["read_write"]
```

CLI validation should reject empty/control characters and not require the exact 64-hex shape for future compatibility, but it must never log or echo the value.

### `GET /up` exists but is not the API contract

```ruby
# Source: config/routes.rb:1013-1015
get "up" => "rails/health#show", as: :rails_health_check
```

Doctor may use `/up` as an unauthenticated liveness check, but the preferred probe is `GET /api/v1/usage` because it exercises the same path prefix, TLS, and auth pipeline. Do not treat `/up` as a server-version endpoint.

### TTY-safe confirmation prior art

```sh
# Source: bin/sure-backup:382-389
if [ "$assume_yes" != true ]; then
  if [ -t 0 ]; then
    printf 'This REPLACES database %s ... Type "restore" to continue: ' ...
    read -r answer
  else
    die "refusing to restore without a TTY; pass --yes"
  fi
fi
```

The CLI should use the same shape: prompt on TTY, otherwise exit 2 with the exact `--yes` instruction. The existing script also sends secrets through private files (`bin/sure-backup:107-119`), not argv — the same principle as `credentials.json`/keychain stdin.

### CLI URL joining

```ruby
# Intended pattern; never use URI.join for API paths.
base = URI.parse(server_url)
prefix = base.path.sub(%r{/+\z}, "")
api_path = "/api/v1/accounts"
uri = base.dup
uri.path = "#{prefix}#{api_path}"
uri.query = URI.encode_www_form(query) unless query.empty?
```

For `server_url = "https://sure.example.com/sure"`, this yields `https://sure.example.com/sure/api/v1/accounts`.

### Faraday safety line

```ruby
# Required: do not attach request headers to exceptions.
f.response :raise_error, include_request: false
```

Without this, `Faraday::UnauthorizedError#response[:request][:headers]` contains the API key and can leak through logs or crash reports.

### CLI success envelope

```json
{
  "data": {"status": "ok"},
  "meta": {
    "schema_version": 1,
    "as_of": "2026-10-31T12:00:00Z",
    "warnings": []
  }
}
```

Write this to stdout only. Errors go to stderr as `{"error":"...","message":"...","details":{},"request_id":"...","exit_code":3}` in machine mode, or a concise human line otherwise.

## Validation Architecture

### Test Framework

| Property | Value |
|----------|-------|
| Framework | Minitest 5.27.0 (`minitest/autorun`) |
| Config file | `cli/test/test_helper.rb`; no Rails test helper |
| Quick run command | `cd cli && bundle exec ruby -Ilib -Itest test/unit/config/resolver_test.rb` |
| Full suite command | `cd cli && bundle exec rake test` |
| Lint | `cd cli && bundle exec rubocop` |
| Packaging | `cd cli && gem build sure.gemspec` |

`test_helper.rb` must:

- require `minitest/autorun`, `webmock/minitest`, and `sure`
- set `ENV["TZ"] = "UTC"` and a temporary `XDG_CONFIG_HOME`
- disable real network with `WebMock.disable_net_connect!(allow_localhost: false)`
- reset `Sure::CLI::Runtime.current` in `teardown`
- provide `run_cli(argv, stdin:, stdout:, stderr:)` returning `[exit_code, stdout, stderr]`
- provide fixture loading from `test/fixtures/api/*.json`

### Phase Requirements → Test Map

| Req ID | Behavior | Test Type | Automated Command | File Exists? |
|--------|----------|-----------|-------------------|--------------|
| FOUND-01 | Gem builds, installs into temp `GEM_HOME`, `sure --version` runs | packaging/smoke | `cd cli && gem build sure.gemspec`; temp install command below | ❌ Wave 0 |
| FOUND-02 | `--version`, `help`, per-command examples; no Rails load | unit/command | `bundle exec ruby -Itest test/commands/version_test.rb` | ❌ Wave 0 |
| FOUND-03 | `--profile` > `SURE_PROFILE` > default; profile creation on login | unit | `bundle exec ruby -Itest test/unit/config/resolver_test.rb` | ❌ Wave 0 |
| FOUND-04 | Prefix URL, CA file, insecure opt-in, invalid URL errors | unit | `bundle exec ruby -Itest test/unit/http/url_builder_test.rb` | ❌ Wave 0 |
| FOUND-05 | Table on TTY, JSON on pipe, injected IO | unit | `bundle exec ruby -Itest test/unit/output/selector_test.rb` | ❌ Wave 0 |
| FOUND-06 | `--json`/`--csv`/`--ndjson`/`--fields` override and validate | unit | `bundle exec ruby -Itest test/unit/output/format_test.rb` | ❌ Wave 0 |
| FOUND-07 | Status/error code map; no backtrace; stderr separation | unit/integration | `bundle exec ruby -Itest test/unit/errors/mapper_test.rb` | ❌ Wave 0 |
| FOUND-08 | Doctor checks, fixes, JSON, aggregate exit | command | `bundle exec ruby -Itest test/commands/doctor_test.rb` | ❌ Wave 0 |
| FOUND-09 | `sure api` GET/write/dry-run/raw/redaction | command | `bundle exec ruby -Itest test/commands/api_test.rb` | ❌ Wave 0 |
| FOUND-10 | Completion scripts for bash/zsh/fish from catalog | unit/snapshot | `bundle exec ruby -Itest test/commands/completion_test.rb` | ❌ Wave 0 |
| AUTH-01 | Hidden prompt, file, stdin login paths | unit/command | `bundle exec ruby -Itest test/unit/auth/login_test.rb` | ❌ Wave 0 |
| AUTH-02 | Keychain + file fallback, 0600/0700, atomic, warning once | unit | `bundle exec ruby -Itest test/unit/auth/store_test.rb` | ❌ Wave 0 |
| AUTH-03 | Status output includes server/profile/user/key/scopes/tier; no key | command | `bundle exec ruby -Itest test/commands/auth_test.rb` | ❌ Wave 0 |
| AUTH-08 | `SURE_API_KEY` works without persistence; logout warns | unit/command | `bundle exec ruby -Itest test/unit/auth/env_provider_test.rb` | ❌ Wave 0 |
| AUTH-09 | No secret in stdout/stderr/argv/verbose/exception | unit/security | `bundle exec ruby -Itest test/unit/redactor_test.rb` | ❌ Wave 0 |
| SAFE-05 | No prompt on non-TTY; actionable exit 2 | command | `bundle exec ruby -Itest test/commands/non_tty_test.rb` | ❌ Wave 0 |
| SAFE-06 | Read-only key refuses write before HTTP | unit | `bundle exec ruby -Itest test/unit/auth/scope_preflight_test.rb` | ❌ Wave 0 |

### Fake HTTP with WebMock

Use WebMock at the Faraday boundary; no live Sure server is needed for the default suite. Assert the exact auth header and path prefix:

```ruby
stub_request(:get, "https://sure.example.com/sure/api/v1/usage")
  .with(headers: { "X-Api-Key" => "fake_key_0123456789" })
  .to_return(status: 200, headers: { "Content-Type" => "application/json" }, body: usage_json)
```

Test cases:

- 200 usage, accounts page, 204 empty body
- self-hosted usage with `Infinity`/`noop` → valid JSON with `nil` limits and a warning
- 401, 403 `insufficient_scope`, 404, 400/409/422, 429, 500/502/503/504
- `to_timeout` and connection failure
- 429 with `Retry-After: 0` and `Retry-After: 3500` (the latter must not retry; exit 6)
- 503 then 200 (GET retried; POST not retried)
- redirect 301/302 (must not follow)
- assert the `Authorization` header is absent in Phase 1
- assert no request body for GET/HEAD

### Keychain Stubbing

Inject `Auth::CommandRunner` with `FakeCommandRunner`; never call real `security` or `secret-tool` in CI.

- `MacKeychainStore#write`: assert `argv` does not include the secret; `stdin_data` equals it; read-back verifies.
- `MacKeychainStore` write/read failure: assert fallback to `FileStore`, config mode becomes `file`, warning once.
- `SecretServiceStore`: assert `secret-tool store` gets `stdin_data`, `lookup` strips one newline, `clear` uses the same attributes.
- `CommandRunner`: assert `SURE_API_KEY` is removed from the child env.
- `Auth::Logout`: assert deletion from both keychain and file.
- `Auth::Status`: assert no secret appears in stdout/stderr.

### TTY Stubbing

Use `FakeTTY`/`FakePipe` objects with `tty?`, `getpass`, `gets`, and `write`, injected through `Runtime`. Do not use the real terminal in the default suite.

- login with no args + pipe → exit 2, message lists `--api-key-file`, `--api-key-stdin`, `SURE_API_KEY`
- login with fake TTY + `getpass` → credential stored, prompt on stderr
- `--api-key-stdin` + pipe → works
- `sure api POST` + pipe without `--yes` → exit 2, no POST request
- `sure api DELETE` + fake TTY + `n` → exit 2, no request
- `--verbose` + pipe → timing/request ID on stderr, pure JSON on stdout
- `NO_COLOR`/`--no-color`/pipe → no ANSI

### Integration and Fixtures

- **In-process CLI integration:** `Sure::CLI.run` with WebMock, temp `XDG_CONFIG_HOME`, and fake TTY. This exercises argv → Thor → context → HTTP → formatter → exit code without spawning a server.
- **Executable smoke:** `Open3.capture3` against `exe/sure --version`, `help`, `completion bash`, and `api GET /api/v1/accounts --dry-run`; no network.
- **Recorded response fixtures:** sanitized JSON under `test/fixtures/api/` for usage, accounts page, error shapes, and self-hosted `noop` usage. No VCR cassettes in Phase 1.
- **Optional live test:** `test/live/smoke_test.rb` guarded by `SURE_LIVE_SERVER` and a read-only `SURE_API_KEY`; excluded from the default `rake test`. Use only a seeded disposable instance. Do not run automatically.
- **No Rails/Rack server** in the CLI bundle. If a live local server is needed, use an external Compose Sure instance; do not add Rack/Puma to the gem.

### Exact Verification Commands

```bash
cd cli
bundle install
bundle exec rake test
bundle exec rubocop
gem build sure.gemspec
```

Package/install smoke:

```bash
cd cli
tmp="$(mktemp -d)"
GEM_HOME="$tmp/gems" \
  gem install --install-dir "$tmp/gems" --bindir "$tmp/bin" \
  ./sure-0.1.0.gem --no-document
GEM_HOME="$tmp/gems" "$tmp/bin/sure" --version
GEM_HOME="$tmp/gems" "$tmp/bin/sure" help
```

No-Rails check:

```bash
cd cli
ruby -Ilib -e 'require "sure"; abort "Rails loaded" if defined?(Rails); puts Sure::VERSION'
```

Completion syntax:

```bash
cd cli
ruby -Ilib exe/sure completion bash | bash -n
# zsh/fish syntax checks only when those shells are installed:
# ruby -Ilib exe/sure completion zsh | zsh -n
# ruby -Ilib exe/sure completion fish | fish -n
```

Security smoke:

```bash
cd cli

# The forbidden flag must fail on a command that would otherwise succeed,
# and its value must not be echoed.
if ruby -Ilib exe/sure api GET /api/v1/accounts \
     --server https://sure.example.com --api-key fake_key --dry-run \
     >/dev/null 2>&1; then
  echo "forbidden --api-key was accepted"; exit 1
fi
out=$(ruby -Ilib exe/sure api GET /api/v1/accounts \
        --server https://sure.example.com --api-key fake_key --dry-run 2>&1 || true)
case "$out" in
  *fake_key*) echo "API key was echoed in an error"; exit 1 ;;
esac

ruby -Ilib exe/sure auth login --help | grep -q -- "--api-key-file"
! ruby -Ilib exe/sure auth login --help | grep -Eq -- '--api-key([ =]|$)'
```

### Sampling Rate

- **Per task commit:** focused test file + `bundle exec rubocop` on changed files.
- **Per wave merge:** `bundle exec rake test` + `bundle exec rubocop`.
- **Phase gate:** full suite, gem build, temp install, `sure --version`/`help`/`completion bash`, and a manual `sure api GET /api/v1/accounts --dry-run`; optionally live smoke.
- **Before release:** live smoke against current and previous minor in Phase 8.

### Wave 0 Gaps

- [ ] `cli/` does not exist yet; create gem skeleton, `Gemfile`, `Gemfile.lock`, `sure.gemspec`, `Rakefile`, `.rubocop.yml`, `exe/sure`, `bin/sure`.
- [ ] `cli/test/test_helper.rb` — Minitest, WebMock, temp config, runtime reset.
- [ ] `cli/test/support/fake_tty.rb`, `fake_pipe.rb`, `fake_store.rb`, `fake_command_runner.rb`, `cli_helper.rb`.
- [ ] `cli/test/fixtures/api/usage.json`, `usage_self_hosted.json`, `accounts_page.json`, `error_401.json`, `error_403.json`, `error_404.json`, `error_422.json`, `error_429.json`.
- [ ] Install/provision Ruby 3.4.9 and Bundler 2.6.7 in the execution environment (see below).
- [ ] `cli/config/operations.yml` and catalog validator.
- [ ] No existing CLI test infrastructure to reuse; do not run root Rails tests for CLI unit behavior.

### Environment Availability

| Dependency | Required By | Available | Version | Fallback |
|------------|-------------|-----------|---------|----------|
| Ruby | Entire gem | ✗ in this research shell | — | None — must provision Ruby 3.4.9p82 |
| Bundler | Dependency/test tasks | ✗ in this research shell | — | Must install 2.6.7 |
| RubyGems | Build/install | ✗ in this research shell | — | Ships with Ruby |
| Git | Repo/release | ✓ | 2.47.3 | — |
| bash | Completion smoke | ✓ | `/usr/bin/bash` | — |
| zsh | Completion smoke | ✗ | — | Snapshot test; install later |
| fish | Completion smoke | ✗ | — | Snapshot test; install later |
| macOS `security` | Keychain-first on macOS | ✗ (Linux host) | — | `FileStore` |
| `secret-tool` | Keychain-first on Linux | ✗ | — | `FileStore` |
| Secret Service/D-Bus | `secret-tool` | ✗ (no `secret-tool`) | — | `FileStore` |
| OpenSSL CLI | TLS diagnostics | ✓ | 3.5.7 | Ruby's OpenSSL |
| WebMock | HTTP tests | via bundle | 3.25.1 | — |
| Live Sure server | Optional live smoke | ✗ | — | WebMock fixtures |

**Missing dependencies with no fallback:** Ruby/Bundler. The executor cannot run `bundle exec rake test`, `gem build`, or the smoke test until Ruby 3.4.9 and Bundler 2.6.7 are available. This is a blocking environment gap, not a code gap.

**Missing dependencies with fallback:** macOS/Linux keychain tools and zsh/fish. The file store and fixture/snapshot tests cover them; real keychain/completion-shell verification remains a manual/CI matrix check.

## Project Constraints (from AGENTS.md)

- Read `docs/llm-guides/architecture.md` and the relevant task guides before changing code. The API/auth conventions are authoritative.
- The CLI lives under `cli/` as its own gem. Do not add its dependencies to the root Rails `Gemfile` or load Rails/ActiveSupport/ActiveRecord at runtime.
- Keep code focused, readable, and consistent with nearby conventions: two-space Ruby indentation, `snake_case` methods/variables, `CamelCase` classes.
- Use `# frozen_string_literal: true`; keep comments about non-obvious intent/constraints, not implementation history.
- Prefer built-in Ruby/Rails patterns and established dependencies. A new dependency needs a strong reason; `pastel` is the only new runtime gem here.
- Use Minitest and fixtures for behavioral tests. Do not use RSpec for CLI behavior; RSpec/rswag is documentation-only on the server.
- Use WebMock/Mocha/VCR only where needed. Phase 1 uses WebMock and sanitized fixtures; no VCR.
- Run `bin/rails test` only for server changes; the CLI phase must use `cd cli && bundle exec rake test`. Do not run Rails tests for CLI-only changes.
- Do not start `rails server`, touch `tmp/restart.txt`, run `rails credentials`, or run migrations. Local live tests are explicit, external, and opt-in.
- Never commit secrets. API keys in fixtures must be fake and clearly test-only. `SURE_API_KEY` is a CI input, not a config value.
- If a server API change is made (for example the additive `user` field on `/usage`), follow the API consistency checklist: Minitest behavioral coverage, documentation-only rswag specs, and regenerate `docs/api/openapi.yaml` with `RAILS_ENV=test bundle exec rake rswag:specs:swaggerize`.
- Preserve family tenancy and authorization boundaries. The CLI never sends a family ID; the server derives it from the credential. Treat 401, 403, and 404 distinctly.
- Do not add CLI behavior that bypasses the API, connects to PostgreSQL, reads Rails internals, or executes commands on the server.
- Commits use imperative subjects of at most 72 characters. PRs explain the problem, behavior, and validation.
- The CLI is AGPLv3 (`AGPL-3.0-only`), consistent with the repository.
- Keep the diff focused. Do not modify root Rails code or OpenAPI unless the additive `/usage` user field is explicitly planned.

## Sources & Confidence

| # | Claim | Confidence | Provenance |
|---|-------|------------|------------|
| 1 | Ruby is 3.4.9p82; root Bundler is 2.6.7 | HIGH | `[VERIFIED: codebase: .ruby-version, Gemfile.lock RUBY VERSION/BUNDLED WITH]` |
| 2 | Thor 1.5.0, Faraday 2.14.3, faraday-retry 2.3.2, terminal-table 4.0.0, csv 3.3.5, json 2.21.2, Minitest 5.27.0, WebMock 3.25.1, Rake 13.4.2, RuboCop 1.76.1, rubocop-rails-omakase 1.1.0 are in the root lock | HIGH | `[VERIFIED: codebase: Gemfile.lock:173,224,234,370,437,658,717,741,841,843,894]` |
| 3 | `pastel 0.8.0` is real, stable, widely used (118M+ downloads), source `piotrmurach/pastel` | HIGH | `[VERIFIED: RubyGems API https://rubygems.org/api/v1/gems/pastel.json]`; `[CITED: .planning/research/STACK.md]` |
| 4 | `sure` and `sure-cli` are unclaimed gem names as of 2026-10-31 | HIGH | `[VERIFIED: RubyGems API both return 404 on 2026-10-31]` |
| 5 | Sure accepts `X-Api-Key` and OAuth2 bearer; scopes are `read`/`read_write` | HIGH | `[VERIFIED: codebase: docs/api/openapi.yaml:13-33; docs/clients.md:91-93]` |
| 6 | `read_write` includes `read`; writes require `read_write` | HIGH | `[VERIFIED: codebase: app/controllers/api/v1/base_controller.rb:197-217]` |
| 7 | Rate-limit headers and `Retry-After` are seconds remaining | HIGH | `[VERIFIED: codebase: app/controllers/api/v1/base_controller.rb:129-171]` |
| 8 | Managed tiers are 100/1,000/10,000 per hour; self-hosted uses `NoopApiRateLimiter` (`tier: noop`, `Infinity`) | HIGH | `[VERIFIED: codebase: app/services/api_rate_limiter.rb:3-7; app/services/noop_api_rate_limiter.rb:26-33]` |
| 9 | `GET /api/v1/usage` returns `api_key` + `rate_limit`, but **no user** | HIGH | `[VERIFIED: codebase: app/controllers/api/v1/usage_controller.rb:6-24]` |
| 10 | No readable `GET /api/v1/me`; `users/me` is DELETE-only; no version endpoint | HIGH | `[VERIFIED: codebase: config/routes.rb:813,832-834; app/controllers/api/v1/users_controller.rb:44-52; no /api/v1/meta route]` |
| 11 | API keys are 64 lowercase hex from `SecureRandom.hex(32)`; one scope only | HIGH | `[VERIFIED: codebase: app/models/api_key.rb:45-47,100-107]` |
| 12 | Error responses use `error`, optional `message`/`details`/`errors`; 429 details include reset seconds | HIGH | `[VERIFIED: codebase: docs/api/openapi.yaml:209-232; app/controllers/api/v1/base_controller.rb:147-163,256-278]` |
| 13 | Collections use two envelopes; `next_page` is absent in some shapes; per_page max 100/default 25 | HIGH | `[VERIFIED: codebase: app/views/api/v1/accounts/index.json.jbuilder:3-11; app/views/api/v1/imports/index.json.jbuilder:17-24; app/views/api/v1/syncs/index.json.jbuilder:7-12; app/controllers/api/v1/base_controller.rb:242-254]` |
| 14 | `GET /up` is an unauthenticated Rails health route | HIGH | `[VERIFIED: codebase: config/routes.rb:1013-1015]` |
| 15 | Faraday Retry can honor `Retry-After`/`X-RateLimit-Reset` and cap waits via `max_interval` | HIGH | `[VERIFIED: faraday-retry v2.3.2 lib/faraday/retry/middleware.rb:88-96,196-231]` |
| 16 | Faraday Retry defaults to retrying DELETE/PUT as well as GET/HEAD; override `methods` | HIGH | `[VERIFIED: faraday-retry v2.3.2 IDEMPOTENT_METHODS]` |
| 17 | Faraday `RaiseError` attaches request headers unless `include_request: false` | HIGH | `[VERIFIED: faraday v2.14.3 lib/faraday/response/raise_error.rb]` |
| 18 | Thor 1.5 `start` catches `Thor::Error` and exits 1 unless `debug: true`/`exit_on_failure? false` | HIGH | `[VERIFIED: Thor v1.5.0 lib/thor/base.rb start method]` |
| 19 | Thor has no built-in shell completion module | HIGH | `[CITED: .planning/research/STACK.md]`; `[VERIFIED: Thor v1.5.0 source/README]` |
| 20 | macOS `security add-generic-password -w` at end prompts; stdin behavior is not documented and version-dependent | MEDIUM | `[CITED: security(1) man page and community reports]`; must use read-back + file fallback |
| 21 | Linux `secret-tool store` reads the secret from stdin; `lookup`/`clear` use attributes | HIGH | `[CITED: secret-tool(1) man page]` |
| 22 | Keychain gems (`keyring`, `libsecret`, `system_keychain`) are abandoned/platform-limited | HIGH | `[CITED: .planning/research/STACK.md; .planning/research/PITFALLS.md]` |
| 23 | A 0600 file in a 0700 directory is the automatic headless fallback, with a one-time warning | HIGH | `[CITED: .planning/phases/01-.../01-CONTEXT.md D-05/D-06]` |
| 24 | Windows has no dependable Ruby Credential Manager binding; file fallback is required, DPAPI is v2 | MEDIUM | `[CITED: .planning/research/STACK.md; .planning/REQUIREMENTS.md EXP-06]` |
| 25 | Config/profile precedence is flag > environment > profile > default | HIGH | `[CITED: .planning/phases/01-.../01-CONTEXT.md Discretion]` |
| 26 | The roadmap's `sure auth login --api-key` wording conflicts with D-07 | HIGH | `[VERIFIED: codebase: .planning/ROADMAP.md:39 vs .planning/phases/01-.../01-CONTEXT.md D-07]` |
| 27 | AUTH-03's `user` requires an additive `user` field on `/usage` (or an explicit partial acceptance) | MEDIUM | `[VERIFIED: absence in usage_controller/routes]`; recommended shape from `auth_controller.rb:489-494`; `[ASSUMED: additive field is acceptable scope]` |
| 28 | Timeouts 5s open / 30s read, max 2 retries, 10s cap are reasonable starting points | MEDIUM | `[CITED: .planning/research/STACK.md; .planning/phases/01-.../01-CONTEXT.md Discretion]`; `[ASSUMED: exact numeric defaults]` |
| 29 | `sure api` `--data JSON`, `/api/v1`-only path, `--yes` for writes, `--dry-run` fulfill the escape-hatch contract | MEDIUM | `[CITED: .planning/research/FEATURES.md; CONTEXT.md Discretion]`; `[ASSUMED: exact flag shape]` |
| 30 | No live Sure server was contacted in this research; API claims come from checked-in code/spec | HIGH | `[VERIFIED: research session]` |

### Contract Gaps and Open Questions

1. **AUTH-03 user identity.** The API does not expose the user for an API key. Recommended resolution: add `user: { email, first_name, last_name }` to the API-key branch of `GET /api/v1/usage` (no new endpoint), or mark AUTH-03 partial and display `user: not exposed by this server`. Do not fabricate a user from the profile name or key name.
2. **macOS keychain stdin.** `security ... -w` at the end may prompt/read stdin on some macOS versions, but Apple does not document it. The implementation must read back and fall back to the file store on failure; never use `-w "$secret"`.
3. **Server version/compatibility.** There is no `GET /api/v1/meta` or version header. Doctor must probe `/usage` and `/accounts` and report "compatible" rather than inventing a version.
4. **Windows credential security.** POSIX 0600 does not exist on Windows. Phase 1 can use `%APPDATA%\sure` plus `icacls`; DPAPI encryption is explicitly v2.
5. **Execution environment.** The research shell has no Ruby/Bundler. The executor must provision Ruby 3.4.9p82 and Bundler 2.6.7 before validation can run.

### Assumptions

| # | Assumption | Risk if Wrong |
|---|------------|---------------|
| A1 | Gem version starts at `0.1.0`. | Low; changes release metadata only. |
| A2 | Exact YAML keys (`config.yml`, `credential_store`, `scopes`, `plaintext_warning_shown`) are acceptable under the discretion grant. | Low; schema can be renamed before release. |
| A3 | Keychain service `sure-cli` and account `profile@origin-fingerprint` are acceptable. | Low; migration/read fallback needed if renamed. |
| A4 | `--insecure` is sufficient explicit opt-in without a separate `--yes`. | Medium; may need `--yes` if security review requires it. |
| A5 | `sure api --data` takes a JSON string; no `--header` is needed in Phase 1. | Low; can add `--data-file`/`--header` later without breaking. |
| A6 | The additive `user` field on `/usage` is acceptable Phase 1 server scope. | Medium; otherwise AUTH-03 must be explicitly partial. |
| A7 | A 10-second retry cap is a good balance for interactive and CI use. | Low; tune after observing server resets. |
| A8 | `sure api` defaults to the normal table/JSON selector; `--raw` is opt-in. | Low; users can always use `--json`. |

### Confidence Breakdown

- **Standard stack:** HIGH — all runtime gems except pastel are pinned in the root lock; pastel is verified.
- **Architecture:** HIGH — follows the layered `cli/` design and checked-in API contracts.
- **Pitfalls:** HIGH — credential, retry, pagination, and output behavior are verified against controllers, views, and Faraday/Thor source.
- **Cross-platform keychain:** MEDIUM — macOS stdin behavior is undocumented; file fallback is mandatory.
- **AUTH-03 user identity:** MEDIUM — the current endpoint does not expose it; the additive field is a recommendation, not a current fact.
- **Environment availability:** HIGH — Ruby/Bundler are absent from the research shell and must be provisioned before execution.

**Research date:** 2026-10-31
**Valid until:** 2026-11-30 for stable repo/API facts; re-check RubyGems/keychain behavior before release.
