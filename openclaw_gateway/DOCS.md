# OpenClaw Gateway Documentation

This add-on runs the OpenClaw Gateway on Home Assistant OS, providing Home Assistant ingress onboarding and optional SSH tunnel access.

## Overview

- **Gateway** runs locally on the HA host (binds to loopback by default)
- **Ingress onboarding** lets you complete first-run setup from the add-on panel
- **SSH server** provides optional secure remote access for OpenClaw.app or the CLI
- **Persistent storage** under `/config/openclaw` survives add-on updates
- On first start, runs `openclaw setup` to create a minimal config

## Installation

1. In Home Assistant: **Settings → Add-ons → Add-on Store → ⋮ → Repositories**
2. Add: `https://github.com/shmulik323/openclaw-ha-addon`
3. Reload the Add-on Store and install **OpenClaw Gateway**

## Configuration

### Add-on Options

| Option                | Description                                                                  |
| --------------------- | ---------------------------------------------------------------------------- |
| `ssh_authorized_keys` | Your public key(s) for SSH access (required for tunnels)                     |
| `ssh_port`            | SSH server port (default: `2222`)                                            |
| `port`                | Gateway WebSocket port (default: `18789`)                                    |
| `repo_url`            | OpenClaw source repository URL                                               |
| `branch`              | Branch to checkout (uses repo's default if omitted)                          |
| `github_token`        | Token for private repository access                                          |
| `verbose`             | Enable verbose logging                                                       |
| `log_format`          | Log output format in the add-on Log tab: `pretty` or `raw`                   |
| `log_color`           | Enable ANSI colors for pretty logs (may be ignored in the UI)                |
| `log_fields`          | Comma-separated metadata keys to append (e.g. `connectionId,uptimeMs,runId`) |

### First Run

The add-on performs these steps on startup:

1. Clones or updates the OpenClaw repo into `/config/openclaw/openclaw-src`
2. Installs dependencies and builds the gateway
3. Starts the Home Assistant ingress proxy immediately
4. If no config exists, serves the onboarding UI through the add-on panel
5. Ensures `gateway.mode=local` if missing
6. Starts the gateway

After onboarding exits, the same ingress panel proxies the OpenClaw Control UI.
The add-on strips the upstream anti-framing headers on the ingress proxy only so
Home Assistant can keep rendering the Control UI inside its iframe-based add-on panel.
It also injects the generated gateway token into the URL fragment on first load so
the dashboard can connect without manual token entry after onboarding.
To make browser access through Home Assistant ingress actually connect, the add-on
also enables `gateway.controlUi.dangerouslyDisableDeviceAuth=true`. Token auth remains
enabled, but OpenClaw's per-device browser pairing/device-identity checks are bypassed
for this ingress-driven deployment model.

### OpenClaw Configuration

#### Recommended: Home Assistant ingress onboarding

On first boot, open the add-on page in Home Assistant and complete onboarding there.
The add-on now exposes the onboarding UI through ingress, so SSH is no longer required for initial setup.

#### Optional: SSH access

SSH into the add-on and run the configurator:

```bash
ssh -p 2222 root@<ha-host>
cd /config/openclaw/openclaw-src
pnpm exec openclaw onboard
```

Or use the shorter flow:

```bash
pnpm exec openclaw configure
```

The gateway auto-reloads config changes. Restart the add-on only if you change SSH keys or build settings:

```bash
ha addons restart local_openclaw
```

## Usage

### SSH Tunnel Access

The gateway listens on loopback by default. Access it via SSH tunnel:

```bash
ssh -p 2222 -N -L 18789:127.0.0.1:18789 root@<ha-host>
```

Then point OpenClaw.app or the CLI at `ws://127.0.0.1:18789`.

### Bind Mode

Configure bind mode via the OpenClaw CLI (over SSH), not in the add-on options.
Use `pnpm exec openclaw configure` or `pnpm exec openclaw onboard` to set it in `openclaw.json`.

## Data Locations

| Path                                         | Description            |
| -------------------------------------------- | ---------------------- |
| `/config/openclaw/.openclaw/openclaw.json`   | Main configuration     |
| `/config/openclaw/.openclaw/agent/auth.json` | Authentication tokens  |
| `/config/openclaw/workspace`                 | Agent workspace        |
| `/config/openclaw/openclaw-src`              | Source repository      |
| `/config/openclaw/.ssh`                      | SSH keys               |
| `/config/openclaw/.config`                   | App configs (gh, etc.) |

## Included Tools

- **gog** — Google Workspace CLI ([gogcli.sh](https://gogcli.sh))
- **gh** — GitHub CLI ([cli.github.com](https://cli.github.com))
- **hass-cli** — Home Assistant CLI

## Troubleshooting

### SSH doesn't work

Ensure `ssh_authorized_keys` is set in the add-on options with your public key.

### Ingress onboarding doesn't load

Open the add-on from Home Assistant, not by browsing directly to port `8099`.
The ingress listener is intended for Home Assistant's internal proxy only.

### Onboarding finishes but the Control UI stays blank

The Control UI must be rendered through the Home Assistant add-on panel, not by
connecting directly to the internal ingress port. If the panel still stays blank,
confirm the add-on log shows the latest `run.sh version=` line after updating.

### The Control UI loads but won't connect

Ingress relies on the Home Assistant host header and origin. The add-on now preserves
the full forwarded host and auto-seeds the generated token into the dashboard URL on
first ingress load. If the page still shows a disconnected gateway after updating,
refresh the add-on page once so the new token bootstrap script can run.

### Gateway won't start

Check logs:

```bash
ha addons logs local_openclaw -n 200
```

### Build takes too long

The first boot runs a full build and may take several minutes. Subsequent starts are faster.

## Security Notes

- For `bind=lan/tailnet/auto`, enable gateway auth in `openclaw.json`
- SSH access is exposed only through the configured add-on port mapping
- Consider firewall rules for the SSH port if exposed to LAN

## Links

- [OpenClaw](https://github.com/openclaw/openclaw) — Main repository
- [Documentation](https://docs.openclaw.io) — Full documentation
- [Community](https://discord.com/invite/openclaw) — Discord server
- [gog CLI](https://gogcli.sh) — Google Workspace CLI
- [GitHub CLI](https://cli.github.com) — GitHub CLI
