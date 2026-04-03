# OpenClaw Home Assistant Add-ons

This repository contains Home Assistant add-ons for OpenClaw.

## Add-ons

### openclaw_gateway

OpenClaw Gateway for Home Assistant OS (**amd64 / x86_64** only) with ingress onboarding, add-on-owned Gateway supervision, supported browser runtime modes, and optional SSH tunnel support.

**Included tools:**

- **gog** — Google Workspace CLI (Gmail, Calendar, Drive, Contacts, Sheets, Docs). See [gogcli.sh](https://gogcli.sh)
- **gh** — GitHub CLI

## Installation

1. Go to **Settings → Add-ons → Add-on Store → ⋮ → Repositories**
2. Add this repository:

   ```
   https://github.com/shmulik323/openclaw-ha-addon
   ```

3. Find **OpenClaw Gateway** in the add-on store and install it

## Configuration

| Option | Description |
| --- | --- |
| `port` | Gateway WebSocket port, default `18789` |
| `verbose` | Enable verbose logging |
| `ingress_ui_mode` | `auto` (default), `control_ui`, or `tui` for the add-on panel |
| `browser_runtime_mode` | `node_host` (default), `local`, `remote_cdp`, or `off` |
| `browser_remote_cdp_url` | Remote CDP URL when using `browser_runtime_mode=remote_cdp` |
| `browser_remote_cdp_profile` | Profile name used for `remote_cdp` mode |
| `repo_url` | OpenClaw source repository |
| `branch` | Branch to checkout, optional |
| `github_token` | GitHub token for private repositories |
| `ssh_port` | SSH server port for tunnel access, default `2222` |
| `ssh_authorized_keys` | Public keys for SSH access |

First-run onboarding is available directly from the add-on panel in Home Assistant.
By default, the panel uses onboarding on first boot and then switches to the embedded Control UI.
Set `ingress_ui_mode=tui` if you prefer the terminal UI after setup.

The add-on is also the canonical runtime supervisor for the live Gateway process in Home Assistant.
It watches semantic config changes, writes runtime truth to `/config/openclaw/.openclaw/addon-runtime-status.json`, and applies reloads itself instead of relying on upstream daemon/service restart semantics.

## Links

- [OpenClaw](https://github.com/openclaw/openclaw)
- [gog CLI](https://gogcli.sh)
- [GitHub CLI](https://cli.github.com)
