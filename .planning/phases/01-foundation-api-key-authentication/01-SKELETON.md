# Walking Skeleton — Sure CLI

**Phase:** 1
**Generated:** 2026-10-31

## Capability Proven End-to-End

> A user installs the `sure` gem, authenticates with a Sure API key, and runs
> `sure api GET /api/v1/accounts` to receive the server's real accounts through
> one shared, redacted HTTP pipeline.

This is the thinnest capability that touches every layer Phase 1 owns: gem
packaging, command dispatch, config resolution, credential storage, HTTP
transport, error mapping, and output formatting. It deliberately stops short of
domain commands (`sure accounts list`), which belong to Phase 2.

## Architectural Decisions

| Decision | Choice | Rationale |
|---|---|---|
| Packaging | Standalone Ruby gem at `cli/` with `exe/sure` | Keeps the CLI out of the Rails runtime and matches the repo's separate `desktop/` and `mobile/` client packages. |
| Command framework | Thor 1.5.0 (root-locked) | Subcommands, aliases, option parsing, and generated help without a second argument parser. |
| HTTP layer | Faraday 2.14.3 + faraday-retry 2.3.2 (root-locked) | One middleware pipeline for auth, JSON, timeouts, TLS, and bounded GET/HEAD retries. |
| Config | YAML at `$XDG_CONFIG_HOME/sure/config.yml` (or `%APPDATA%\sure`), mode `0600`, directory `0700` | Non-secret profiles only; no credentials in config. |
| Credential storage | macOS Keychain / Linux Secret Service first, atomic `0600` file fallback with one-time warning | Meets AUTH-02 without requiring a keychain on headless servers. |
| Authentication | `X-Api-Key` header only; key supplied by hidden prompt, `--api-key-file`, `--api-key-stdin`, or `SURE_API_KEY` | Never places the key in argv or shell history (D-07). |
| Output | Table on a TTY, stable JSON envelope when piped; explicit `--json/--table/--csv/--ndjson/--fields` | Script-safe defaults with a documented `schema_version: 1` envelope (D-11, D-12, D-16). |
| Errors | One `Errors::Mapper` at the `CLI::Runner` boundary with semantic exit codes `0–9` | Commands never call `exit`; no Ruby backtraces for expected failures (D-13). |
| Deployment | `gem build sure.gemspec` + install into a temporary `GEM_HOME`; publish to RubyGems in a later release phase | Proves FOUND-01 locally without coupling Phase 1 to a release pipeline. |
| Directory layout | `cli/lib/sure/{catalog,cli,config,auth,http,errors,output,doctor,completion}` | Mirrors the responsibility map in `01-RESEARCH.md`; each module has one job. |

## Stack Touched in Phase 1

- [ ] Project scaffold (gemspec, Bundler, Rake test/lint/build tasks, RuboCop)
- [ ] Command routing — `sure --version`, `sure help`, `sure auth ...`, `sure api ...`, `sure doctor`, `sure completion`
- [ ] Real read — `GET /api/v1/usage` for login validation/status and `GET /api/v1/accounts` through `sure api`
- [ ] Real write — `sure auth login` persists a credential (keychain or `0600` file) and updates the profile atomically
- [ ] UI — terminal table on a TTY and JSON envelope on a pipe, with color only on a TTY
- [ ] Deployment — documented local full-stack run: `cd cli && bundle install && bundle exec rake test && gem build sure.gemspec`, then install the built gem into a temporary `GEM_HOME`

## Out of Scope (Deferred to Later Slices)

- `sure accounts list`, `sure transactions ...`, reports, budgets, and holdings (Phase 2)
- Any write command other than local credential/profile writes (Phase 3)
- Imports, sync, exports, and long-running job polling (Phase 4)
- Browser OAuth, PKCE, dynamic client registration, and token refresh (Phase 5)
- AI chats, streaming, and citations (Phase 6)
- Platform handoff, copyable command catalog endpoint, and `sure://` deep links (Phase 7)
- Publishing the gem to RubyGems, signing releases, and Homebrew packaging (Phase 8)
- A `sure config` command group — Phase 1 profiles are created/updated by `sure auth login` and edited in `config.yml`

## Subsequent Slice Plan

Each later phase adds one vertical slice on top of this skeleton without changing
its architectural decisions:

- Phase 2: read and report on accounts, transactions, cash flow, balance sheet, budgets, and holdings
- Phase 3: guarded writes with previews, confirmation, dry-run, and idempotency
- Phase 4: imports, sync, and exports with resumable jobs
- Phase 5: browser OAuth and credential refresh UX
- Phase 6: AI chats and assisted workflows
- Phase 7: platform handoff and copyable commands
- Phase 8: full parity, contract tests, hardening, and release

## Deliberate Roadmap Reconciliation

`ROADMAP.md` success criterion 3 names `sure --profile staging accounts list --json`.
Phase 1's locked context (D-01 scope, "does not add read/reporting commands") puts
domain read commands in Phase 2. Phase 1 therefore proves the same pipeline with
`sure --profile staging api GET /api/v1/accounts --json`; Phase 2 delivers
`accounts list` on top of the identical pipeline. The phase's goal — one truthful
API response through a shared, safe pipeline — is unchanged.

`ROADMAP.md` success criterion 2 names `sure auth login --api-key`. That flag is
forbidden by locked decision D-07 (no secret in argv). The implemented interface is
`--api-key-file`, `--api-key-stdin`, `SURE_API_KEY`, or the hidden prompt.
