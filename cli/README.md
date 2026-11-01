# Sure CLI

A first-party command-line client for [Sure](https://github.com/we-promise/sure),
the self-hosted personal finance app.

The CLI is a client of an existing Sure server: it uses the same `/api/v1` HTTP
API, `X-Api-Key` authentication, family tenancy, authorization rules, and
server-calculated financial semantics as the web, desktop, and mobile clients. It
does **not** connect to Postgres and it does **not** load Rails, ActiveSupport, or
ActiveRecord.

## Install from source

The gem is built and installed locally until the release phase publishes it:

```bash
cd cli
bundle install
gem build sure.gemspec

gem_home=$(mktemp -d)
GEM_HOME="$gem_home" gem install --local sure-0.1.0.gem --no-document
"$gem_home/bin/sure" --version
```

`gem install` into a temporary `GEM_HOME` proves the packaged file list is
self-contained without touching your system gems.

## Phase 1 command surface

```text
sure --version                 Print the CLI version
sure help                      List command groups
sure help auth login           Show catalog-backed examples

sure auth login                Store an API key for a profile
sure auth logout               Delete the local credential
sure auth status               Show the active profile and key metadata

sure api METHOD PATH           Call any Sure /api/v1 endpoint
sure doctor                    Diagnose config, credentials, and connectivity
sure completion SHELL          Generate bash, zsh, or fish completion
```

API keys are supplied through a hidden prompt, `--api-key-file`,
`--api-key-stdin`, or `SURE_API_KEY`. The CLI never accepts a key as a plain
`--api-key` argument, so keys do not leak into process lists or shell history.

## Safety properties

The CLI is designed to be safe to drive from scripts and agents, where stdout is
a pipe rather than a terminal.

- **Redaction covers every output format.** The active credential is masked in
  `--json`, `--table`, `--csv`, and `--ndjson` as well as `--raw` and error text.
  This matters because a non-TTY caller defaults to `--json`, and a server is
  free to echo a credential in any field. `sure api GET /api/v1/whatever --json`
  will print `[REDACTED]`, not your key.
- **Secrets never travel in argv.** Login reads the key from a hidden prompt,
  `--api-key-file`, `--api-key-stdin`, or `SURE_API_KEY`. There is no
  `--api-key` flag.
- **Credentials are private by default.** The OS keychain is preferred; the file
  fallback is written `0600` and warns once per profile.
- **Reads and writes are distinguished.** `sure api` refuses
  `POST`/`PUT`/`PATCH`/`DELETE` without `--yes` when stdin is not a TTY, and a
  key without `read_write` scope fails the scope preflight before any write
  request leaves the process.
- **Paths stay inside the API.** `sure api` accepts only paths under `/api/v1`
  and rejects absolute URLs, fragments, traversal, and percent-encoded
  separators after two rounds of decoding.

## Exit codes

Exit codes are semantic and stable, so a script can branch without parsing
output.

| Code | Meaning |
| --- | --- |
| 0 | Success |
| 1 | General error / a failed `doctor` check |
| 2 | Usage error (bad flag, rejected path, missing input) |
| 3 | Authentication or insufficient scope |
| 4 | Not found |
| 5 | Validation error |
| 6 | Rate limited |
| 7 | Partial failure |
| 8 | Network or server error |
| 9 | Timeout |
| 130 | Interrupted |

## Development

```bash
cd cli
bundle install
bundle exec rake test     # Minitest
bundle exec rake lint     # RuboCop (rails-omakase style)
bundle exec rake build    # gem build sure.gemspec
```

Runtime dependencies are pinned to the versions already locked by the root
Rails application (`thor`, `faraday`, `faraday-retry`, `terminal-table`, `csv`),
so the CLI does not introduce a second dependency generation into the monorepo.

## License

AGPL-3.0-only, consistent with the Sure repository. See [LICENSE](LICENSE).
