[![Ask DeepWiki](https://img.shields.io/badge/Ask-DeepWiki-blue)](https://deepwiki.com/we-promise/sure)
[![View performance data on Skylight](https://badges.skylight.io/typical/s6PEZSKwcklL.svg)](https://oss.skylight.io/app/applications/s6PEZSKwcklL)
[![Dosu](https://raw.githubusercontent.com/dosu-ai/assets/main/dosu-badge.svg)](https://app.dosu.dev/a72bdcfd-15f5-4edc-bd85-ea0daa6c3adc/ask)
[![Pipelock Security Scan](https://github.com/we-promise/sure/actions/workflows/pipelock.yml/badge.svg)](https://github.com/we-promise/sure/actions/workflows/pipelock.yml)

<picture>
  <source media="(prefers-color-scheme: dark)" srcset="https://raw.githubusercontent.com/we-promise/sure/main/docs/screenshots/dashboard-dark.webp">
  <img alt="The Sure dashboard in two columns (cashflow, net worth, spending and outflows) beside the AI assistant answering a question about savings" src="https://raw.githubusercontent.com/we-promise/sure/main/docs/screenshots/dashboard-light.webp">
</picture>

<p align="center">
  <!-- Keep these links. Translations will automatically update with the README. -->
  <a href="https://readme-i18n.com/de/we-promise/sure">Deutsch</a> | 
  <a href="https://readme-i18n.com/es/we-promise/sure">Español</a> | 
  <a href="https://readme-i18n.com/fr/we-promise/sure">Français</a> | 
  <a href="https://readme-i18n.com/ja/we-promise/sure">日本語</a> | 
  <a href="https://readme-i18n.com/ko/we-promise/sure">한국어</a> | 
  <a href="https://readme-i18n.com/pt/we-promise/sure">Português</a> | 
  <a href="https://readme-i18n.com/ru/we-promise/sure">Русский</a> | 
  <a href="https://readme-i18n.com/zh/we-promise/sure">中文</a>
</p>

# Sure: The personal finance app for everyone

<b>Get
involved: [Discord](https://discord.gg/36ZGBsxYEK) • [Website](https://sure.am) • [Issues](https://github.com/we-promise/sure/issues)</b>

> [!IMPORTANT]
> This repository is a community fork of the now-abandoned Maybe Finance project. <br />
> Learn more in their [final release](https://github.com/maybe-finance/maybe/releases/tag/v0.6.0) doc.

## Backstory

The [Maybe Finance](https://github.com/maybe-finance/maybe) (archived/abandoned repo) team spent most of 2021–2022 building a full-featured personal finance and wealth management app. It even included an “Ask an Advisor” feature that connected users with a real CFP/CFA — all included with your subscription.

The business end of things didn't work out, and so they stopped developing the app in mid-2023.

After spending nearly $1 million on development (employees, contractors, data providers, infra, etc.), the team open-sourced the app. Their goal was to let users self-host it for free — and eventually launch a hosted version for a small fee.

They actually did launch that hosted version … briefly.

That also didn’t work out — at least not as a sustainable B2C business — so now here we are: hosting a community-maintained fork to keep the codebase alive and see where this can go next.

Join us!

## Hosting Sure

Sure is a fully working personal finance app that can be [self hosted with Docker](docs/hosting/docker.md).
Sure can be accessed from a browser, the macOS desktop app, the mobile app, API
clients, and LLM agents. See [Sure Clients](docs/clients.md) for an overview.

## Sure CLI (added in this fork)

This fork ships a first-party command-line client, `sure`, in [`cli/`](cli/README.md).
It is a client of the same `/api/v1` HTTP API the web, desktop, and mobile apps
use: it does not connect to Postgres and does not load Rails, ActiveSupport, or
ActiveRecord, so authentication, family tenancy, authorization, and financial
semantics stay on the server.

Phase 1 (`0.1.0`) covers the auth lifecycle plus a raw API escape hatch:

| Command | Purpose |
| --- | --- |
| `sure auth login` | Validate an API key against `GET /api/v1/usage`, then store it |
| `sure auth status` | Show the active profile and API key metadata |
| `sure auth logout` | Delete the local credential |
| `sure api METHOD PATH` | Call any `/api/v1` endpoint |
| `sure doctor` | Diagnose config, credentials, connectivity, TLS, clock skew, and key scope |
| `sure completion SHELL` | Generate bash, zsh, or fish completion |

Install and run it from source:

```bash
cd cli
bundle install
gem build sure.gemspec
gem_home=$(mktemp -d)
GEM_HOME="$gem_home" gem install --local sure-0.1.0.gem --no-document
"$gem_home/bin/sure" --version
```

Design constraints worth knowing before you script against it:

- **The key never enters argv.** `auth login` reads the API key from a hidden prompt, `--api-key-file`, `--api-key-stdin`, or `SURE_API_KEY`. There is no plain `--api-key` flag, so a key cannot leak into process lists or shell history.
- **Credentials are private by default.** The OS keychain is preferred, with a `0600` file fallback that warns once.
- **Output is redacted in every format.** The active credential is masked in `--json`, `--table`, `--csv`, and `--ndjson` as well as `--raw` and error text, because non-TTY callers default to JSON.
- **Writes are explicit.** `sure api` refuses `POST`/`PUT`/`PATCH`/`DELETE` without `--yes` on a non-TTY, and a key without `read_write` scope fails before any write request leaves the process.
- **Exit codes are stable and semantic.** `0` success, `2` usage error, `3` authentication or scope failure, `8` network or server error, and so on; the full ladder is in [cli/README.md](cli/README.md#exit-codes).

The CLI is **not** part of upstream `we-promise/sure`; it is maintained here.
See [cli/README.md](cli/README.md) for the full command surface and development
workflow, and [Sure Clients](docs/clients.md) for how it fits alongside the
other clients.

## Forking and Attribution

This repo is a community fork of the archived Maybe Finance repo.
You’re free to fork it under the AGPLv3 license — but we’d love it if you stuck around and contributed here instead.

To stay compliant and avoid trademark issues:

- Be sure to include the original [AGPLv3 license](https://github.com/maybe-finance/maybe/blob/main/LICENSE) and clearly state in your README that your fork is based on Maybe Finance but is **not affiliated with or endorsed by** Maybe Finance Inc.
- "Maybe" is a trademark of Maybe Finance Inc. and therefore, use of it is NOT allowed in forked repositories (or the logo)

## Performance Issues

With data-heavy apps, inevitably, there are performance issues. We've set up a public dashboard showing the problematic requests seen on the demo site, along with the stacktraces to help debug them.

[https://www.skylight.io/app/applications/s6PEZSKwcklL/recent/6h/endpoints](https://oss.skylight.io/app/applications/s6PEZSKwcklL/recent/6h/endpoints)

Any contributions that help improve performance are very much welcome.

## Local Development Setup

**If you are trying to _self-host_ the app, [read this guide to get started](docs/hosting/docker.md).**

The instructions below are for developers to get started with contributing to the app.

### Requirements

- See `.ruby-version` file for required Ruby version
- PostgreSQL >9.3 (latest stable version recommended)
- Redis > 5.4 (latest stable version recommended)

### Getting Started
```sh
cd sure
cp .env.local.example .env.local
bin/setup
bin/dev

# Optionally, load demo data
rake demo_data:default
```

Visit http://localhost:3000 to view the app.

If you loaded the optional demo data, log in with these credentials:

- Email: `user@example.com`
- Password: `Password1!`

For further instructions, see guides below.

### Setup Guides

- [Mac dev setup](https://github.com/we-promise/sure/wiki/Mac-Dev-Setup-Guide)
- [Linux dev setup](https://github.com/we-promise/sure/wiki/Linux-Dev-Setup-Guide)
- [Windows dev setup](https://github.com/we-promise/sure/wiki/Windows-Dev-Setup-Guide)
- Dev containers - visit [this guide](https://code.visualstudio.com/docs/devcontainers/containers)

### One-click Install

Render expects each button target branch to have a `render.yaml` at the repository root. The branch-ready Blueprint files live in `branches/<branch-name>/render.yaml` in a separate repo and can be copied to each corresponding branch root.

| Option | What it deploys | `latest` | `stable` |
| --- | --- | --- | --- |
| **Sure - No AI** | Sure web, Sidekiq worker, Render Postgres, and Render Key Value. AI tokens are intentionally blank. | [![Deploy to Render](https://render.com/images/deploy-to-render-button.svg)](https://render.com/deploy?repo=https://github.com/we-promise/sure-render-templates/tree/sure-no-ai-latest) | [![Deploy to Render](https://render.com/images/deploy-to-render-button.svg)](https://render.com/deploy?repo=https://github.com/we-promise/sure-render-templates/tree/sure-no-ai) |
| **Sure - Simple AI** | Sure with OpenAI-backed AI settings, pgvector-ready Postgres, Sidekiq, and Render Key Value. Render prompts for the OpenAI token. | [![Deploy to Render](https://render.com/images/deploy-to-render-button.svg)](https://render.com/deploy?repo=https://github.com/we-promise/sure-render-templates/tree/sure-simple-ai-latest) | [![Deploy to Render](https://render.com/images/deploy-to-render-button.svg)](https://render.com/deploy?repo=https://github.com/we-promise/sure-render-templates/tree/sure-simple-ai) |
| **Sure - External AI** | Sure with external assistant settings plus AlphaClaw, which manages the OpenClaw gateway on Render. | [![Deploy to Render](https://render.com/images/deploy-to-render-button.svg)](https://render.com/deploy?repo=https://github.com/we-promise/sure-render-templates/tree/sure-external-ai-latest) | [![Deploy to Render](https://render.com/images/deploy-to-render-button.svg)](https://render.com/deploy?repo=https://github.com/we-promise/sure-render-templates/tree/sure-external-ai) |

[![Run on PikaPods](https://www.pikapods.com/static/run-button.svg)](https://www.pikapods.com/pods?run=sure)

[![Deploy on Hostim](https://hostim.dev/img/deploy-button.svg)](https://console.hostim.dev/dashboard?preview=1&modal=1&template=sure)

## License and Trademarks

Maybe and Sure are both distributed under
an [AGPLv3 license](https://github.com/we-promise/sure/blob/main/LICENSE).
- "Maybe" is a trademark of Maybe Finance, Inc.
- "Sure" is not, and refers to this community fork.
