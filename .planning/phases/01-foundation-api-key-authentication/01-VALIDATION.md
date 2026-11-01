---
phase: 1
slug: foundation-api-key-authentication
status: ready
nyquist_compliant: true
wave_0_complete: false
created: 2026-10-31
---

# Phase 1 — Validation Strategy

> Per-phase validation contract for feedback sampling during execution.

---

## Test Infrastructure

| Property | Value |
|----------|-------|
| **Framework** | Minitest 5.27.0 (root-locked) + WebMock 3.25.1 + Rake 13.4.2 |
| **Config file** | `cli/Rakefile`, `cli/test/test_helper.rb` (created in Wave 0) |
| **Quick run command** | `cd cli && bundle exec rake test` |
| **Full suite command** | `cd cli && bundle exec rake test && bundle exec rubocop && gem build sure.gemspec` |
| **Estimated runtime** | ~60 seconds |

Ruby 3.4.9 and Bundler 2.6.7 are required. This planning host does not have Ruby
installed, so the first execution task must confirm the toolchain (repo
devcontainer or a local Ruby 3.4.9) before running tests.

---

## Sampling Rate

- **After every task commit:** Run the focused test file named in the task's `<verify>` block.
- **After every plan wave:** Run `cd cli && bundle exec rake test`.
- **Before `/gsd-verify-work`:** Full suite, RuboCop, and a temporary-`GEM_HOME` install must be green.
- **Max feedback latency:** 60 seconds.

---

## Per-Task Verification Map

| Task ID | Plan | Wave | Requirement | Threat Ref | Secure Behavior | Test Type | Automated Command | File Exists | Status |
|---------|------|------|-------------|------------|-----------------|-----------|-------------------|-------------|--------|
| 01-01-T0 | 01 | 1 | FOUND-01 | — | Exact Ruby 3.4.9/Bundler 2.6.7 toolchain confirmed | preflight | `ruby -v \| grep -q 3.4.9 && bundle -v \| grep -q 2.6.7` | ❌ W0 | ⬜ pending |
| 01-01-T1 | 01 | 1 | FOUND-01 | T-01-01 / T-01-SC | Gem allowlist excludes secrets; deps are root-locked | packaging | `cd cli && gem build sure.gemspec` | ❌ W0 | ⬜ pending |
| 01-01-T2 | 01 | 1 | FOUND-02 | T-01-02 | Unknown options rejected; no Rails load | unit/command | `cd cli && bundle exec ruby -Itest test/commands/version_help_test.rb` | ❌ W0 | ⬜ pending |
| 01-01-T3 | 01 | 1 | FOUND-02 | T-01-03 | Catalog YAML is data-only (no eval) | unit | `cd cli && bundle exec ruby -Itest test/unit/catalog_test.rb` | ❌ W0 | ⬜ pending |
| 01-02-T1 | 02 | 2 | FOUND-03 | T-02-01 | Config `0600`, dir `0700`, no symlinks | unit | `cd cli && bundle exec ruby -Itest test/unit/config/atomic_file_test.rb` | ❌ W0 | ⬜ pending |
| 01-02-T2 | 02 | 2 | FOUND-04 | T-02-02 | TLS verified by default; no userinfo/query in base URL | unit | `cd cli && bundle exec ruby -Itest test/unit/config/resolver_test.rb` | ❌ W0 | ⬜ pending |
| 01-02-T3 | 02 | 2 | AUTH-08 | T-02-03 | Env key never written to disk or argv | unit | `cd cli && bundle exec ruby -Itest test/unit/auth/api_key_provider_test.rb` | ❌ W0 | ⬜ pending |
| 01-03-T1 | 03 | 3 | FOUND-07, AUTH-09 | T-03-01, T-03-02 | Active key redacted by value; errors preserve status/headers; GET/HEAD retries only | unit | `cd cli && bundle exec ruby -Itest test/unit/http/client_test.rb` | ❌ W0 | ⬜ pending |
| 01-03-T2 | 03 | 3 | FOUND-07 | T-03-03 | Stable envelope; no raw payload default | unit | `cd cli && bundle exec ruby -Itest test/unit/output/json_test.rb` | ❌ W0 | ⬜ pending |
| 01-03-T3 | 03 | 3 | FOUND-09, AUTH-09 | T-03-04 | `/api/v1`-only paths; redacted dry-run | command/integration | `cd cli && bundle exec ruby -Itest test/commands/api_test.rb` | ❌ W0 | ⬜ pending |
| 01-04-T1 | 04 | 4 | AUTH-02 | T-04-01, T-04-02 | Secret via stdin only; atomic `0600` fallback | unit | `cd cli && bundle exec ruby -Itest test/unit/auth/file_store_test.rb` | ❌ W0 | ⬜ pending |
| 01-04-T2 | 04 | 4 | AUTH-01, AUTH-03, SAFE-06 | T-04-03 | No argv secret; scope preflight before writes | command | `cd cli && bundle exec ruby -Itest test/commands/auth_test.rb` | ❌ W0 | ⬜ pending |
| 01-04-T3 | 04 | 4 | AUTH-03 | T-04-04 | User object is authenticated, not profile-derived | Rails request | `cd /home/randy/sure-cli && bin/rails test test/controllers/api/v1/usage_controller_test.rb` | ❌ W0 | ⬜ pending |
| 01-05-T1 | 05 | 5 | FOUND-05, FOUND-06 | T-05-01 | CSV/NDJSON injection-safe; fields validated | unit | `cd cli && bundle exec ruby -Itest test/unit/output/formatters_test.rb` | ❌ W0 | ⬜ pending |
| 01-05-T2 | 05 | 5 | FOUND-08 | T-05-02 | Doctor never prints secrets; fixes are actionable | command | `cd cli && bundle exec ruby -Itest test/commands/doctor_test.rb` | ❌ W0 | ⬜ pending |
| 01-05-T3 | 05 | 5 | FOUND-10, SAFE-05 | T-05-03 | No prompts when stdin is not a TTY | command/snapshot | `cd cli && bundle exec ruby -Itest test/commands/completion_test.rb` | ❌ W0 | ⬜ pending |

*Status: ⬜ pending · ✅ green · ❌ red · ⚠️ flaky*

---

## Wave 0 Requirements

- [ ] Toolchain — Ruby 3.4.9 and Bundler 2.6.7 confirmed by 01-01 Task 0 (repo devcontainer or local version manager)
- [ ] `cli/Gemfile` + `cli/Gemfile.lock` — resolve Thor 1.5.0, Faraday 2.14.3, faraday-retry 2.3.2, terminal-table 4.0.0, csv 3.3.5, Minitest 5.27.0, WebMock 3.25.1, Rake 13.4.2, RuboCop 1.76.1 (no pastel — stdlib ANSI only)
- [ ] `cli/test/test_helper.rb` — Minitest, WebMock enable/reset, `capture_io`, injected runtime, temporary `HOME`/`XDG_CONFIG_HOME` (01-01 Task 1)
- [ ] `cli/test/support/temp_config.rb` — isolated config directory (01-02 Task 1)
- [ ] `cli/test/support/local_http_server.rb` — stdlib TCPServer for the end-to-end API smoke test (01-03 Task 1)
- [ ] `cli/test/support/fake_tty.rb` — stdin/stdout TTY stubs for `sure api` confirmation (01-03 Task 3) and the hidden-prompt login test (01-04 Task 2)
- [ ] Devcontainer `db`/`redis` services + reachable test database for the additive `/usage` controller test and rswag regeneration (01-04 Task 3)
- [ ] `cli/test/support/fake_store.rb` — in-memory credential store (01-04 Task 1)
- [ ] `cli/test/support/fake_command_runner.rb` — keychain helper stub (01-04 Task 1)
- [ ] `cli/test/support/fake_keychain.rb` — keychain availability/failure stub (01-04 Task 1)
- [ ] `cli/test/fixtures/api/*.json` — usage, accounts collection, 401/429/500 error bodies (01-03/01-04)
- [ ] `cli/test/fixtures/config/*.yml` — valid profiles, invalid schema, bad URL (01-01/01-02)
- [ ] `cli/test/fixtures/completion/*` — bash/zsh/fish snapshots (01-05 Task 3)

---

## Manual-Only Verifications

| Behavior | Requirement | Why Manual | Test Instructions |
|----------|-------------|------------|-------------------|
| Real macOS Keychain read/write | AUTH-02, D-05 | `security` behavior varies by macOS release and needs a real login keyring | On macOS, run `sure auth login`, confirm `security find-generic-password -s sure-cli -a <account>` finds the item, then `sure auth status` and `sure auth logout` |
| Real Linux Secret Service read/write | AUTH-02, D-05 | Needs a running GNOME Keyring/KWallet session | On a desktop Linux session, run `sure auth login`, confirm `secret-tool lookup service sure-cli profile default` returns the key, then `sure auth logout` |
| Shell completion loads in a real shell | FOUND-10 | Completion is evaluated by the user's shell, not Ruby | `source <(sure completion bash)` then type `sure auth <TAB>`; repeat for zsh (`zsh -f`) and fish (`fish -c 'sure completion fish \| source'`) |

---

## Validation Sign-Off

- [x] All tasks have `<automated>` verify or Wave 0 dependencies
- [x] Sampling continuity: no 3 consecutive tasks without automated verify
- [x] Wave 0 covers all MISSING references
- [x] No watch-mode flags
- [x] Feedback latency < 60s
- [x] `nyquist_compliant: true` set in frontmatter

**Approval:** plan-side approved 2026-10-31; execution sign-off pending `wave_0_complete`.
