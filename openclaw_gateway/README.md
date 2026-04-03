# OpenClaw Gateway

Run [OpenClaw](https://github.com/openclaw/openclaw) on Home Assistant OS (**amd64 / x86_64** hosts) with Home Assistant ingress onboarding, add-on-owned Gateway supervision, and supported browser runtime modes.

## Features

- 🦞 **OpenClaw Gateway** — AI agent with messaging, automation, and more
- 🧭 **Ingress Onboarding** — Complete first-run setup from the add-on panel
- 🖥️ **Configurable Ingress UI** — Use the embedded Control UI after setup or switch the panel to the terminal UI
- 🌐 **Browser Runtime Modes** — `node_host` by default, opt-in local Chromium, `remote_cdp`, or `off`
- 📅 **Google Workspace CLI** — Optional `gog_account` and `gog_keyring_password` options let `gog` use stored Google auth non-interactively from the Control UI and SSH shells
- 🔁 **Add-on-Owned Reloads** — The add-on watches semantic config changes and reloads the live Gateway child itself
- 🔑 **Auto Token Bootstrap** — Ingress injects the generated gateway token on first dashboard load
- 🔓 **Ingress Device-Auth Bypass** — Token auth stays on, but browser device identity is bypassed for the ingress UI
- 🔒 **SSH Tunnel** — Optional secure remote access for OpenClaw.app or the CLI
- 📦 **Persistent Storage** — All data survives add-on updates
- 🛠️ **Included Tools** — pnpm (global), Claude Code CLI (`claude`), Codex CLI (`codex`), Gemini CLI (`gemini`), Playwright Chromium cache under `/config/openclaw/.cache/ms-playwright`, gog (Google Workspace), gh (GitHub), hass-cli

## Quick Start

1. Add this repository to Home Assistant
2. Install **OpenClaw Gateway** from the Add-on Store
3. Start the add-on and open the add-on panel to run onboarding
4. Optionally configure your SSH public key for tunnel access

`ingress_ui_mode` defaults to `auto`, which means:

- no `openclaw.json` yet: the add-on panel stays on the onboarding terminal
- config exists: the add-on panel switches to the embedded Control UI

Set `ingress_ui_mode=tui` if you want the add-on panel to stay on `openclaw tui` after setup.

`browser_runtime_mode` defaults to `node_host`, which means:

- `node_host`: supported default for browser access from a paired node host
- `local`: opt-in baked-in headless Chromium inside the add-on container
- `remote_cdp`: connect to an explicit remote Chromium CDP endpoint
- `off`: disable browser runtime management

The add-on is also the canonical runtime supervisor for the Gateway in Home Assistant.
It writes runtime truth to `/config/openclaw/.openclaw/addon-runtime-status.json` and applies reloads itself instead of relying on upstream daemon/service restart semantics.

## Links

- [Documentation](https://docs.openclaw.io)
- [GitHub](https://github.com/openclaw/openclaw)
- [Discord](https://discord.com/invite/openclaw)
