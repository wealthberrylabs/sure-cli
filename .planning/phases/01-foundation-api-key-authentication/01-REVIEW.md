---
phase: 01-foundation-api-key-authentication
reviewed: 2026-11-01T02:20:00Z
depth: standard
files_reviewed: 65
files_reviewed_list:
  - app/controllers/api/v1/usage_controller.rb
  - cli/config/operations.yml
  - cli/lib/sure.rb
  - cli/lib/sure/auth/api_key_provider.rb
  - cli/lib/sure/auth/command_runner.rb
  - cli/lib/sure/auth/credential.rb
  - cli/lib/sure/auth/credential_key.rb
  - cli/lib/sure/auth/file_store.rb
  - cli/lib/sure/auth/login.rb
  - cli/lib/sure/auth/logout.rb
  - cli/lib/sure/auth/mac_keychain_store.rb
  - cli/lib/sure/auth/scope_preflight.rb
  - cli/lib/sure/auth/secret_service_store.rb
  - cli/lib/sure/auth/status.rb
  - cli/lib/sure/auth/store.rb
  - cli/lib/sure/auth/store_factory.rb
  - cli/lib/sure/catalog.rb
  - cli/lib/sure/catalog/loader.rb
  - cli/lib/sure/catalog/operation.rb
  - cli/lib/sure/catalog/validator.rb
  - cli/lib/sure/cli.rb
  - cli/lib/sure/cli/application.rb
  - cli/lib/sure/cli/base.rb
  - cli/lib/sure/cli/commands/api.rb
  - cli/lib/sure/cli/commands/auth.rb
  - cli/lib/sure/cli/commands/completion.rb
  - cli/lib/sure/cli/commands/doctor.rb
  - cli/lib/sure/cli/context.rb
  - cli/lib/sure/cli/runner.rb
  - cli/lib/sure/cli/runtime.rb
  - cli/lib/sure/cli/shell.rb
  - cli/lib/sure/completion/generator.rb
  - cli/lib/sure/config.rb
  - cli/lib/sure/config/atomic_file.rb
  - cli/lib/sure/config/loader.rb
  - cli/lib/sure/config/paths.rb
  - cli/lib/sure/config/profile.rb
  - cli/lib/sure/config/resolver.rb
  - cli/lib/sure/doctor/check.rb
  - cli/lib/sure/doctor/result.rb
  - cli/lib/sure/doctor/runner.rb
  - cli/lib/sure/errors.rb
  - cli/lib/sure/errors/error.rb
  - cli/lib/sure/errors/exit_codes.rb
  - cli/lib/sure/errors/mapper.rb
  - cli/lib/sure/http/auth_middleware.rb
  - cli/lib/sure/http/client.rb
  - cli/lib/sure/http/connection.rb
  - cli/lib/sure/http/envelope.rb
  - cli/lib/sure/http/pagination.rb
  - cli/lib/sure/http/rate_limit.rb
  - cli/lib/sure/http/response.rb
  - cli/lib/sure/http/url_builder.rb
  - cli/lib/sure/output.rb
  - cli/lib/sure/output/base.rb
  - cli/lib/sure/output/column.rb
  - cli/lib/sure/output/csv.rb
  - cli/lib/sure/output/field_selection.rb
  - cli/lib/sure/output/json.rb
  - cli/lib/sure/output/ndjson.rb
  - cli/lib/sure/output/result.rb
  - cli/lib/sure/output/selector.rb
  - cli/lib/sure/output/table.rb
  - cli/lib/sure/redactor.rb
  - cli/lib/sure/version.rb
  - spec/requests/api/v1/usage_spec.rb
findings:
  critical: 5
  warning: 11
  info: 6
  total: 22
status: issues_found
---

# Phase 1: Code Review Report

**Reviewed:** 2026-11-01T02:20:00Z
**Depth:** standard
**Files Reviewed:** 65
**Status:** issues_found

## Summary

The phase delivers a real walking skeleton: a Thor-based CLI with a single argv
boundary, an immutable per-command `Context`, keychain-first credential storage
with a 0600 file fallback, an flock-backed config writer, a single Faraday
pipeline with origin pinning, semantic exit codes, four output formats, a
non-short-circuiting `doctor`, and the additive `user` payload on
`GET /api/v1/usage` with matching Minitest and rswag coverage.

Baseline verification: `cli/bundle exec rake test` → 281 runs / 1217 assertions /
0 failures; `bin/rails test test/controllers/api/v1/usage_controller_test.rb` → 7
runs / 146 assertions / 0 failures. The Minitest suite is green and therefore
does not exercise most of what is below — the credential prompt is double-tested
through a fake TTY, the completion scripts are only snapshot-compared, and the
argv boundary is only tested with flags *after* the command.

Adversarial probing against a local HTTP server (login, status, api, doctor,
logout) found five defects that break or undermine shipped behaviour:

1. The interactive login prompt echoes the API key in cleartext.
2. Any global option placed before the command silently prints help and exits 0 —
   including `sure --json doctor`, which masks real doctor failures in CI.
3. `sure auth login` cannot use a custom CA bundle or `--insecure` and silently
   ignores both, so login is impossible against a private-CA self-hosted server.
4. `CredentialKey` drops the server URL path prefix, so two deployments on the
   same origin share one credential slot and a key can be sent to the wrong path.
5. The generated zsh completion re-enters itself and cannot work as installed.

The security posture of the parts that do work is good (no secrets in argv,
scrubbed child environment, origin-pinned auth header, 0600/0700 files, flocked
atomic writes, ANSI/CSV-formula neutralisation), so the findings below are
concentrated in three seams: the Thor argv boundary, the login-specific profile
the CLI builds for itself instead of going through `Config::Resolver`, and the
store-fallback contract.

## Critical Issues

### CR-01: Interactive `sure auth login` echoes the API key in cleartext

**File:** `cli/lib/sure/auth/login.rb:182-199` (with `cli/lib/sure/cli.rb:1-14`)
**Issue:** `prompt_secret` only hides input if `runtime.stdin` responds to
`getpass` or `noecho`. Those methods come from `io/console`, which is never
required anywhere in the gem, so on a real terminal both `respond_to?` checks are
false and login falls through to `runtime.stdin.gets`, i.e. a plain echoed read.
Verified two ways:

```
$ bundle exec ruby -Ilib -e 'require "sure"; p $stdin.respond_to?(:getpass); p $stdin.respond_to?(:noecho)'
false
false
```

and with a PTY running the real command:

```
API key: KEY-THAT-SHOULD-NOT-ECHO-0123456789
--- key echoed back in transcript? true ---
```

The key is written to the terminal, stays in scrollback, and is visible to screen
sharing/recording. The suite misses this because `test/support` injects a fake
TTY that implements `getpass`, so the third branch is never taken.

**Fix:**
```ruby
# cli/lib/sure/auth/login.rb
require "io/console"   # at the top of the file

def prompt_secret
  unless tty?(runtime.stdin)
    raise Errors::UsageError, FLAG_GUIDANCE
  end

  runtime.stderr.print(PROMPT)
  runtime.stderr.flush if runtime.stderr.respond_to?(:flush)

  raw =
    if runtime.stdin.respond_to?(:getpass)
      runtime.stdin.getpass
    elsif runtime.stdin.respond_to?(:noecho)
      runtime.stdin.noecho { runtime.stdin.gets }
    else
      # Never fall back to an echoed read for a secret.
      raise Errors::UsageError, "cannot read a hidden API key on this terminal; " \
                                "use --api-key-file, --api-key-stdin, or SURE_API_KEY"
    end

  normalize_secret(raw)
end
```
Add a regression test using a real `PTY` (or a `StringIO` without `getpass`/
`noecho`) asserting the CLI raises instead of calling `gets`.

### CR-02: A global option before the command silently prints help and exits 0

**File:** `cli/lib/sure/cli/runner.rb:46-53` (boundary), `cli/lib/sure/cli/application.rb:21-35`
**Issue:** Thor 1.5's `retrieve_command_name` only shifts the first argv token if
it is a mapped alias or does not start with `-`; a leading class option therefore
becomes the "command name" and a `DynamicCommand` swallows everything. The
Runner does no argv normalisation, so any documented class option placed before
the command degrades into help text with a success status:

```
$ sure --json doctor ; echo $?
Usage:
  sure doctor
...
0
$ sure --profile x api GET /api/v1/accounts
{"error":"usage_error","message":"Could not find command \"api\".",...}
```

For `doctor` this is a silent false pass: a CI gate running `sure --json doctor`
gets exit 0 and never sees the failing check. `completion` advertises every
global flag at every position (see WR-04), and `sure help` lists them, so users
are actively steered into this form. Verified with the project CLI and reduced to
a bare Thor app (same result), so the fix belongs here, not upstream.

**Fix:** normalise argv before handing it to Thor, and reject rather than ignore:
```ruby
# cli/lib/sure/cli/runner.rb
GLOBAL_VALUE_FLAGS = %w[--profile --server --ca-bundle --fields].freeze
GLOBAL_BOOL_FLAGS  = %w[--json --table --csv --ndjson --quiet --verbose --color --no-color --insecure].freeze

def call(argv)
  @machine_output = machine_output?(argv)
  argv = hoist_global_options(argv)      # move leading class options after the command token
  Runtime.with(runtime) do
    reject_forbidden_api_key(argv)
    Application.start(argv, debug: true, shell: Shell.new(runtime))
  end
  Errors::ExitCodes::SUCCESS
rescue ...
end

def hoist_global_options(argv)
  leading, rest = argv.partition.with_index do |token, _i|
    # only the run of options before the first non-option token
  end
  ...
end
```
Minimum acceptable fix: if `argv.first.to_s.start_with?("-")` and the token is not
`--version`/`-v`/`--help`, raise `Errors::UsageError` naming the required
`<command> <flags>` ordering, so the failure is loud and exits 2.

### CR-03: `sure auth login` ignores CA bundle and TLS settings, so private-CA servers cannot log in

**File:** `cli/lib/sure/auth/login.rb:129-137`, `cli/lib/sure/cli/commands/auth.rb:23-30`
**Issue:** `Login` builds its own `Config::Profile` instead of going through
`Config::Resolver`, and omits `ca_bundle` and `tls_verify`, so the profile used
for the `/api/v1/usage` validation always has `tls_verify: true` and
`ca_bundle: nil`. `Commands::Auth` also declares no `--ca-bundle`/`--insecure`
options, and Thor accepts them anyway (inherited from the parent class options),
so they are *silently discarded*:

```
$ printf '%s' "$KEY" | sure auth login --server http://127.0.0.1:18081 \
    --ca-bundle /nonexistent/ca.pem --api-key-stdin
{"data":{...,"credential_source":"file"},"meta":{...}}   # exit 0, flag ignored
```

Consequences: (a) on a self-hosted instance behind a private CA or self-signed
cert, `sure auth login` fails TLS verification and there is no way to store a
key at all (FOUND-04 — "custom CA bundles and explicit insecure opt-in work" —
holds for `sure api`, not for login); (b) `--ca-bundle /nonexistent` is accepted
where `sure api` correctly exits 2, so the same flag has two different contracts;
(c) a profile that already carries `tls_verify: false` is honoured by every
command except the one that must run first.

**Fix:**
```ruby
# cli/lib/sure/cli/commands/auth.rb
class_option :ca_bundle, type: :string, desc: "PEM CA bundle"
class_option :insecure, type: :boolean, default: false, desc: "Disable TLS verification (dangerous)"

# cli/lib/sure/auth/login.rb
def build_profile(name, server_url, attributes)
  Config::Resolver.new(
    env: runtime.env,
    options: options.merge(profile: name, server: server_url),
    loader: loader,
    cwd: runtime.cwd,
    stderr: runtime.stderr
  ).resolve   # reuse one precedence + validation implementation
end
```
If reuse is undesirable, at minimum copy `ca_bundle`/`tls_verify` through and
validate the CA path with the same `File.file?`/`File.readable?` check the
resolver uses.

### CR-04: `CredentialKey` ignores the server URL path prefix, cross-wiring deployments on one origin

**File:** `cli/lib/sure/auth/credential_key.rb:44-55`
**Issue:** `normalize_origin` returns only `scheme://host[:port]` and throws the
path away, although the plan requires "scheme+host+port+path prefix without a
trailing slash". The URL builder explicitly supports mounted prefixes
(`https://host/sure`), so two deployments on one host now share a slot:

```
account a: default@bf9de0d4e456217b   # https://sure.example.com/tenant-a
account b: default@bf9de0d4e456217b   # https://sure.example.com/tenant-b
collide: true
root vs /sure collide: true
```

Two consequences: `sure auth login --server https://host/tenant-b` overwrites the
credential stored for `/tenant-a`; and `AuthMiddleware#ensure_same_origin!` only
compares scheme/host/port, so a command run with `--server https://host/tenant-b`
will read the `/tenant-a` key and *send it* to the other deployment. That is a
credential-scope violation between tenants on shared hosting, not just a naming
collision.

**Fix:**
```ruby
def normalize_origin(value)
  uri = URI.parse(value.to_s)
  scheme = uri.scheme.to_s.downcase
  host = uri.host.to_s.downcase
  port = uri.port
  default_port = scheme == "https" ? 443 : 80
  port_suffix = port.nil? || port == default_port ? "" : ":#{port}"
  prefix = uri.path.to_s.sub(%r{/+\z}, "")
  "#{scheme}://#{host}#{port_suffix}#{prefix}"
rescue URI::InvalidURIError
  value.to_s
end
```
Add a test asserting `https://host/a` and `https://host/b` produce different
`account`/`origin_fingerprint` values.

### CR-05: Generated zsh completion re-enters its own function and cannot work

**File:** `cli/lib/sure/completion/generator.rb:77-101` (fixture: `cli/test/fixtures/completion/_sure:20-22`)
**Issue:** the generated script both defines `_sure()` and calls `_sure "$@"` at
the end. Installed as instructed (`sure completion zsh > ~/.zfunc/_sure`, per
`cli/config/operations.yml:185`), the file body *is* the body of the autoloaded
`_sure` function, so the trailing call re-invokes the definition it just
installed — unbounded recursion rather than completion. Sourced from `.zshrc`
instead, the call runs `compadd` outside a completion context, where it errors.
The correct pattern guards on how the file was loaded (`if [ "$funcstack[1]" =
"_sure" ]; then _sure "$@"; else compdef _sure sure; fi`), or simply drops both
the wrapper and the call and relies on `#compdef`. The snapshot test only proves
the bytes match the fixture, so the defect is baked into the snapshot.

**Fix:**
```ruby
def render_zsh
  root = words(root_commands.keys)
  auth = words(subcommands_for("auth"))
  # #compdef registers the file; the body must not call itself.
  <<~ZSH
    #compdef sure

    local -a commands

    if (( CURRENT == 2 )); then
      commands=(#{root})
      compadd -- $commands
      return
    fi

    case $words[2] in
      auth)
        if (( CURRENT == 3 )); then
          commands=(#{auth})
          compadd -- $commands
        fi
        ;;
    esac
  ZSH
end
```
Regenerate the fixture and add an assertion that the script contains no
`_sure "$@"` invocation.

## Warnings

### WR-01: `StoreFactory#read` hides a file-stored credential, and `auth logout` reports `deleted: false` while deleting it

**File:** `cli/lib/sure/auth/store_factory.rb:36-49`, `cli/lib/sure/auth/logout.rb:33-40`
**Issue:** when the keychain is available, `read` returns the keychain result
directly and only consults the file copy if the keychain *raises*. A nil result
is treated as "no credential". Verified with a fake keychain:

```
login mode: file                 # credential written to credentials.json
logout read (credential_present?) => nil
after delete, file still exists? false     # it was deleted anyway
read with keychain available (cred in file) => nil
```

So `sure auth logout` deletes a real credential and reports `"deleted": false`,
breaking its documented idempotency contract for scripts, and any command run in
that state fails with "no API key for profile; run `sure auth login`" while the
key sits in the 0600 file. Reachable whenever `credential_store` says `keychain`
but the credential is in the file (login itself recommends `credential_store:
keychain` in its fallback warning, and `SecretServiceStore#write` never verifies
the read-back the way `MacKeychainStore` does).

**Fix:** treat a nil keychain result as a miss and fall back:
```ruby
def read(key)
  return file_store.read(key) if mode == :file

  begin
    stored = keychain_store.read(key)
    stored || file_store.read(key)
  rescue StoreError => e
    ...existing fallback...
  end
end
```
and in `Logout`, compute `existed` from both backends (or have `StoreFactory#delete`
return whether anything was removed).

### WR-02: `--insecure` with a CA bundle from env/profile silently discards the CA

**File:** `cli/lib/sure/config/resolver.rb:118-145`
**Issue:** `reject_insecure_with_ca!` only rejects the combination when the CA came
from `--ca-bundle` (`present?(options[:ca_bundle])`). Verified:

```
$ SURE_CA_BUNDLE=/etc/ssl/certs/ca-certificates.crt sure api GET /api/v1/accounts --insecure
warning: TLS verification is disabled; the connection can be intercepted
{...}          # exit 0, CA silently ignored
$ sure api GET /api/v1/accounts --insecure --ca-bundle /etc/ssl/certs/ca-certificates.crt
{"error":"usage_error","message":"--ca-bundle and --insecure cannot be used together",...}
```
The plan requires "`--ca-bundle` and `--insecure` together exits 2" without
qualifying the source, and a silently dropped CA is exactly the misconfiguration
this guard exists to prevent.

**Fix:**
```ruby
def reject_insecure_with_ca!(ca_bundle)
  return if ca_bundle.nil?

  raise Errors::UsageError, "--ca-bundle and --insecure cannot be used together"
end
```

### WR-03: The redactor refuses secrets shorter than 4 characters while login accepts them

**File:** `cli/lib/sure/redactor.rb:15`, `cli/lib/sure/redactor.rb:38-44`, `cli/lib/sure/auth/api_key_provider.rb:50-63`
**Issue:** `register` silently skips any secret shorter than
`MIN_ACTIVE_SECRET_LENGTH = 4`, and nothing enforces a minimum key length on the
`SURE_API_KEY`/`--api-key-file`/stdin paths (only non-empty, ≤4096 bytes). A
server that echoes the key in an error body therefore leaks it verbatim:

```
$ SURE_API_KEY=abc SURE_SERVER=http://127.0.0.1:18082 sure auth status
{"error":"authentication_error","message":"authentication failed (401): bad key abc for you; ...", ...}
```
Real Sure keys are 64 hex characters, so exposure is limited, but "never print the
key" should not depend on the key's shape.

**Fix:** either refuse secrets below the redaction floor at the input boundary
(`validate_environment_key!`, `normalize_secret`) with an actionable usage error,
or lower/remove the floor and accept the false-positive redaction risk. Do both
consistently — do not accept a credential the redactor will not mask.

### WR-04: `auth` subcommands accept and ignore `--quiet`, `--verbose`, `--color`, `--ca-bundle`, `--insecure`

**File:** `cli/lib/sure/cli/commands/auth.rb:23-36`, `cli/lib/sure/cli/commands/auth.rb:53-64`
**Issue:** the `Auth` group redeclares a subset of the root class options, so the
rest are inherited just enough to pass `check_unknown_options!` but never appear
in the options hash used for rendering. Verified: `sure auth login --quiet`
still prints the plaintext-storage warning, `sure auth status --quiet` behaves
identically to no flag, and `--no-color`/`--verbose` are inert. Meanwhile
`cli/lib/sure/completion/generator.rb:14-18` advertises all of these as global
flags at every completion position, and `--bogus` correctly exits 2 — so the
behaviour is inconsistent rather than a deliberate "unsupported flag" decision.

**Fix:** stop redeclaring options per group and let the root `Application` own
them (Thor subcommands can read `options` passed down), or add the missing
class options to `Auth` and thread them into `Output::Selector` (which already
supports `quiet:`/`color:`).

### WR-05: `Context#output_format` duplicates output resolution and already disagrees with `Output::Selector`

**File:** `cli/lib/sure/cli/context.rb:82-84` (unused), `cli/lib/sure/output/selector.rb:28-52`
**Issue:** `Context#output_format` returns `profile.output || (tty? ? :table : :json)`.
The selector (the only thing that renders) resolves flags → `SURE_OUTPUT` →
profile → tty, and raises on conflicting flags. The context version is never
consumed by any command (`grep` finds only `inspect`), ignores `SURE_OUTPUT`, and
ignores `--json`/`--table`. Two answers to "what format is this command using"
that disagree today is a latent bug for the next phase that reaches for it.

**Fix:** delete `Context#output_format` and expose the selector's answer
(`selector.format`) if a caller ever needs it.

### WR-06: `read_only` is derived from a possibly absent field, and `persist!`'s `warning_shown` argument is inverted

**File:** `cli/lib/sure/auth/login.rb:61-73`, `cli/lib/sure/auth/login.rb:252-271`
**Issue:** `validate!` only requires a `Hash` body, then
`scopes = Array(usage.dig("api_key", "scopes"))` and
`"read_only" => !scopes.include?("read_write")`. A 2xx response that lacks
`api_key` (older server, proxy returning a JSON banner, wrong base URL that still
returns 200) yields `scopes: []` and permanently persists `read_only: true`, which
`ScopePreflight` trusts before any network call — writes then fail with "profile
is marked read-only … log in again" for a `read_write` key. Separately,
`persist!(name, server_url, scopes, mode, warning.nil?)` passes
`warning_shown = (warning.nil?)`, which is the negation of the parameter's name,
then assigns `"plaintext_warning_shown" => warning_shown ? previously_warned?(name) : true`.
The behaviour happens to be right; the naming is a trap for the next edit.

**Fix:** require the fields login depends on
(`body["api_key"].is_a?(Hash) && !body.dig("api_key", "scopes").nil?`) and fail
with an actionable error otherwise; rename the argument to `warned_already` or
pass `warning` and derive the flag inside `persist!`.

### WR-07: `auth logout` cannot remove a keychain credential when the profile has no `server_url`

**File:** `cli/lib/sure/auth/logout.rb:33-40`, `cli/lib/sure/auth/store_factory.rb:79-83`
**Issue:** with no resolvable origin, logout calls `store.delete_profile(name)`,
which only clears the *file* store (`FileStore#delete_profile`). The keychain item
is addressed by `profile@<origin-fingerprint>` (or the Secret Service
`service/profile/origin` triple), so it is unreachable and stays live in the OS
keychain forever, while logout reports `"deleted": false` and gives the user no
way to finish the job. A hand-broken `config.yml` (the exact case this branch
exists for) is precisely when this happens.

**Fix:** when the origin is unknown, enumerate every account for the profile
(`CredentialKey` fingerprints cannot be reversed, so iterate the file document's
keys *and* add a `delete_profile` that lists keychain items by the profile
attribute — e.g. `security dump-keychain`/`secret-tool search profile <name>`),
and report the number of removed entries.

### WR-08: HTTP 403 is reported as an authentication failure with the wrong remediation

**File:** `cli/lib/sure/errors/mapper.rb:20`, `cli/lib/sure/errors/mapper.rb:79-98`
**Issue:** `AUTHENTICATION_STATUSES = [401, 403]`, so a tenancy or guest 403
(`Api::V1::BaseController#ensure_current_family_access`, `reject_guest_writes!`)
becomes `authentication_error` with the message
"insufficient permissions (403): …; create a read_write key in Sure Settings ->
API Keys". The user is told to mint a stronger key when the real cause is
authorization (resource in another family) or a guest account — and exit code 3
("authentication") is indistinguishable from an invalid key.

**Fix:** split 401 from 403:
```ruby
when 403
  "permission denied (403): #{server_message || 'this credential cannot perform that action'}"
```
with `InsufficientScopeError`/a new `ForbiddenError` (exit code of your choice) so
the existing `insufficient_scope` slug is used for 403s too.

### WR-09: `--fields` accepts column labels in table mode but only keys elsewhere

**File:** `cli/lib/sure/output/table.rb:59-65` vs `cli/lib/sure/output/json.rb:47-62`, `cli/lib/sure/output/csv.rb:43-59`, `cli/lib/sure/output/ndjson.rb:17-23`
**Issue:** `Table#filter_columns` validates against `[column.key, column.label]`
and matches either; the other three formatters validate only against keys (and
for JSON, only against `result.columns.map(&:key)`). For any command that supplies
`result.columns`, `--fields "Created At"` renders a table and exits 2 on `--json`
for the same value. Verified on the collection path that the inverse also bites:
`--fields accounts` against `/api/v1/accounts` fails with "available fields:
balance, id, name" because JSON/Ndjson/Csv validate against the *item* fields
while Table validates against the headings.

**Fix:** resolve `--fields` once against a canonical key list per format family
(keys + labels accepted, normalised to keys) before rendering, so all four
formatters agree on what is valid.

### WR-10: `sure api` accepts percent-encoded CR, LF, and NUL that the guard claims to reject

**File:** `cli/lib/sure/cli/commands/api.rb:80-113`
**Issue:** the raw path is rejected for literal `/[\r\n\0]/`, and the
double-decoded form is checked for `%2e`/`%2f`/`%5c` and `..`, but encoded
control characters are never checked in either form:

```
OK   "/api/v1/accounts%00" => "/api/v1/accounts%00"
OK   "/api/v1/accounts%0d%0aX-Evil:1" => "/api/v1/accounts%0d%0aX-Evil:1"
```
The value stays percent-encoded on the wire today (no raw header injection), so
this is not exploitable as-is — but the comment on line 78-79 states the guard
rejects "traversal, and encoded separators", and a server or proxy that decodes
once more turns it into a real control character.

**Fix:**
```ruby
if decoded.match?(/[\r\n\0]/) || raw.match?(/[\r\n\0]/) ||
   raw.match?(FORBIDDEN_ENCODINGS) || decoded.match?(FORBIDDEN_ENCODINGS) || decoded.include?("..")
  raise Errors::UsageError, "path must not contain traversal, encoded separators, or control characters"
end
```

### WR-11: `usage_controller_test` clears a different Redis than the limiter uses

**File:** `test/controllers/api/v1/usage_controller_test.rb:17,22,83`
**Issue:** setup/teardown use `Redis.new` (localhost:6379/0) while
`ApiRateLimiter` reads `ENV.fetch("REDIS_URL", ...)`. With a non-default
`REDIS_URL` (CI containers, shared dev DB) the cleanup silently targets the wrong
server, so rate-limit counters leak between tests and between suites, and each
call leaks a connection that is never closed.

**Fix:**
```ruby
def redis
  @redis ||= Redis.new(url: ApiRateLimiter.redis_url)
end
```
and close it in teardown, or drop the manual cleanup and let the tests use a
unique API key per test (they already create one in setup).

## Info

### IN-01: Dead code and unused surface

**Files:** `cli/lib/sure/output/table.rb:18-23` (`color` accepted, never used —
`--color`/`--no-color` has no effect), `cli/lib/sure/output/result.rb:7` (`footer`
is never set by any command, though `Table` renders it), `cli/lib/sure/http/rate_limit.rb:53-55`
(`reset?` unused), `cli/lib/sure/http/envelope.rb` + `pagination.rb` (loaded by
`cli/lib/sure.rb` but only exercised by tests), `cli/lib/sure/redactor.rb:50-56,76-97`
(`redact_headers`/`scrub_env` only used by tests; `CommandRunner` re-implements
scrubbing as `PRESERVED_ENV`), `app/controllers/api/v1/usage_controller.rb:36-41`
(the `else` branch is unreachable — `authenticate_request!` renders 401 before the
action runs).
**Fix:** delete now or document each as a deliberate Phase 2 placeholder; either
way stop shipping two implementations of the same policy (`scrub_env` vs
`PRESERVED_ENV`, `Context#output_format` vs `Selector`).

### IN-02: `Catalog::Validator` is only wired into tests

**File:** `cli/lib/sure/catalog/validator.rb`
**Issue:** nothing in `lib/` invokes `Validator.validate!`, so a packaging error or
a command added without a catalog entry is only caught by `rake test`, not by the
installed gem.
**Fix:** run `Validator.validate!(Catalog.default)` once from `Sure.run` behind a
cheap memoised guard (or in `rake build`) so the packaged gem fails loudly instead
of silently missing help/completion entries.

### IN-03: Rate-limit schema drifts from the self-hosted response

**Files:** `app/controllers/api/v1/usage_controller.rb:21-28`, `spec/swagger_helper.rb:200-211`, `cli/lib/sure/output/json.rb:110-120`
**Issue:** self-hosted instances use `NoopApiRateLimiter`, whose `rate_limit` and
`remaining` are `Float::INFINITY`; ActiveSupport encodes those as `null`, while
the OpenAPI schema declares `limit`/`remaining` as non-nullable integers. Also
`meta.rate_limit` is emitted as `{}` (not omitted) whenever the server sends no
rate-limit headers, because `RateLimit#to_h` compacts nils.
**Fix:** document `limit`/`remaining` as `nullable: true`, and omit `rate_limit`
from `meta` when `to_h` is empty.

### IN-04: `--api-key-file` does not expand `~` while `--ca-bundle` does

**File:** `cli/lib/sure/auth/login.rb:201-208` vs `cli/lib/sure/config/resolver.rb:110-116`
**Issue:** `File.file?("~/key.txt")` is false, so a tilde path fails with "API key
file ~/key.txt does not exist" while `--ca-bundle ~/ca.pem` works.
**Fix:** `File.expand_path(path)` before the existence check (matching
`Resolver#expand_ca_bundle`).

### IN-05: `reject_forbidden_api_key` false-positives on argv values, and misses single-dash forms

**File:** `cli/lib/sure/cli/runner.rb:70-78`
**Issue:** the scan is position-independent, so `sure api POST /api/v1/x --data
'--api-key=...'` is rejected even though the token is a JSON payload, and
`-api-key`/`--API_KEY` (any case variant) is not matched at all.
**Fix:** only inspect tokens in option position (before the first `--` argument
separator), and compare case-insensitively against the known spellings.

### IN-06: Secret inputs are read unbounded before the 4 KiB cap is applied

**File:** `cli/lib/sure/auth/login.rb:156-173`
**Issue:** `runtime.stdin.read` and `File.read(path)` slurp the whole source, then
`normalize_secret` enforces `MAX_BYTES = 4096`. A 2 GB file or an endless stdin
pipe is fully buffered before rejection. The plan explicitly asked for a bounded
read.
**Fix:** `runtime.stdin.read(MAX_BYTES + 1)` / `File.read(path, MAX_BYTES + 1)`
and reject when `bytesize > MAX_BYTES`.

---

_Reviewed: 2026-11-01T02:20:00Z_
_Reviewer: the agent (gsd-code-reviewer)_
_Depth: standard_
