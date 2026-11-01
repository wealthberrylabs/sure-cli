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
