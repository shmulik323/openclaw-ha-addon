# OpenClaw Gateway Documentation

This add-on runs the OpenClaw Gateway on Home Assistant OS with Home Assistant ingress onboarding, add-on-owned runtime supervision, supported browser runtime modes, and optional SSH tunnel access.

## Overview

- **Gateway** runs locally on the Home Assistant host and is supervised by the add-on itself
- **Ingress onboarding** lets you complete first-run setup from the add-on panel
- **Config reloads** are applied by the add-on supervisor through semantic config watching
- **Browser runtime modes** support `node_host` by default, opt-in local Chromium, `remote_cdp`, or `off`
- **SSH server** provides optional secure remote access for OpenClaw.app or the CLI
- **Persistent storage** under `/config/openclaw` survives add-on updates

### Supported platform

The store build targets **amd64 (x86_64)** only. It is not published for ARM Home Assistant hosts (Raspberry Pi, Apple Silicon HA VMs, etc.); use a generic OpenClaw install on those platforms instead.

## Installation

1. In Home Assistant, go to **Settings → Add-ons → Add-on Store → ⋮ → Repositories**
2. Add `https://github.com/shmulik323/openclaw-ha-addon`
3. Reload the Add-on Store and install **OpenClaw Gateway**

## Configuration

### Add-on Options

| Option | Description |
| --- | --- |
| `ssh_authorized_keys` | Public key(s) for optional SSH access |
| `ssh_port` | SSH server port, default `2222` |
| `port` | Gateway WebSocket port, default `18789` |
| `verbose` | Enable verbose Gateway logs |
| `log_format` | Add-on log formatting: `pretty` or `raw` |
| `log_color` | Enable ANSI colors in pretty log mode |
| `log_fields` | Comma-separated metadata keys to append in pretty log mode |
| `ingress_ui_mode` | `auto` (default), `control_ui`, or `tui` for the add-on panel |
| `browser_runtime_mode` | `node_host` (default), `local`, `remote_cdp`, or `off` |
| `browser_remote_cdp_url` | Remote CDP URL used when `browser_runtime_mode=remote_cdp` |
| `browser_remote_cdp_profile` | Remote CDP profile name, default `ha_remote` |
| `gog_account` | Default Google account email for `gog` commands |
| `gog_keyring_password` | Password used to unlock `gog` token storage non-interactively |
| `repo_url` | OpenClaw source repository URL |
| `branch` | Branch to checkout, optional |
| `github_token` | Token for private repository access |
| `ha_token` | Optional manual Home Assistant API token override |

### First Run

The add-on performs these steps on startup:

1. Clones or updates the OpenClaw repo into `/config/openclaw/openclaw-src`
2. Installs dependencies and builds the gateway
3. Starts the Home Assistant ingress proxy immediately
4. If no config exists yet, serves the onboarding terminal UI through the add-on panel
5. Reconciles add-on-owned runtime fields into `openclaw.json`
6. Starts and supervises the Gateway child
7. Watches semantic config and supported add-on option changes, then reloads the child through the add-on supervisor

After onboarding exits, `ingress_ui_mode=auto` switches the panel to the embedded Control UI once `openclaw.json` exists. Set `ingress_ui_mode=tui` to keep the add-on panel on `openclaw tui` instead.

## Runtime Supervision

This add-on is the actual control plane for the live Gateway process in Home Assistant.

Important consequence:

- `openclaw gateway restart` is not the runtime control plane for this deployment
- the add-on supervisor owns the live child process and reload behavior

The add-on:

- watches semantic `openclaw.json` changes instead of raw file bytes
- includes selected add-on options in the runtime digest
- reloads the live Gateway child through `SIGUSR1`
- writes runtime truth to `/config/openclaw/.openclaw/addon-runtime-status.json`

The runtime status file includes supervisor PID, child PID, config and option digests, browser mode, browser launch validation state, reload state, and the last reload result or error.

## Browser Runtime Modes

`browser_runtime_mode` controls how the add-on manages browser support.

### `node_host`

This is the default mode.

- Browser capability is expected from a remote OpenClaw node host
- Local browser absence is expected here
- This is the safest default for Home Assistant because the add-on does not need to launch a local browser unless you opt in

### `local`

This mode is supported but opt-in in this release.

- The add-on image ships **Debian Chromium** at `/usr/bin/chromium` for the reconciled `openclaw` profile
- **Playwright-managed Chromium** is also installed after `pnpm install` into `PLAYWRIGHT_BROWSERS_PATH` (default `/config/openclaw/.cache/ms-playwright`), matching upstream’s optional browser bundle. The bundle is refreshed when `playwright-core`’s version changes; first run can take several minutes for `install-deps` + download.
- The add-on reconciles:
  - `browser.enabled=true`
  - `browser.defaultProfile="openclaw"`
  - `browser.executablePath="/usr/bin/chromium"`
  - `browser.headless=true`
  - `browser.noSandbox=true`
- The add-on validates launch by running `openclaw browser start --browser-profile openclaw` after the Gateway becomes ready

`browser.noSandbox=true` is a Home Assistant add-on container compatibility choice in this environment. It is not a general OpenClaw recommendation for other installs.

OpenClaw features that expect Playwright’s downloaded Chromium will use the persistent path above via the `PLAYWRIGHT_BROWSERS_PATH` environment variable set in add-on `config.json`.

### `remote_cdp`

This mode is supported for explicit remote Chromium endpoints.

- Set `browser_remote_cdp_url`
- The add-on writes the selected profile and CDP URL into `openclaw.json`
- The add-on then reloads the Gateway child with the new effective runtime config

### `off`

Disables browser runtime management in the add-on.

## Ingress Behavior

After onboarding exits in `auto` or `control_ui` mode, the same ingress panel proxies the OpenClaw Control UI.

The add-on ingress proxy:

- strips upstream anti-framing headers only for the Home Assistant ingress path
- injects the generated gateway token into the dashboard URL fragment on first load
- preserves Home Assistant forwarded host and proto headers
- seeds the exact ingress WebSocket URL into the Control UI bootstrap
- enables `gateway.controlUi.dangerouslyDisableDeviceAuth=true` so ingress browser sessions can connect with token auth

Token auth remains enabled. The add-on is only bypassing OpenClaw's browser device-identity checks for this ingress deployment model.

## OpenClaw Configuration

### Recommended: Home Assistant ingress onboarding

On first boot, open the add-on page in Home Assistant and complete onboarding there.
SSH is no longer required for initial setup.

### Optional: SSH access

```bash
ssh -p 2222 root@<ha-host>
cd /config/openclaw/openclaw-src
pnpm exec openclaw onboard
```

Prefer `pnpm exec` (or `node scripts/run-node.mjs …`) from this directory; the add-on strips pnpm-only `.npmrc` keys after clone so plain `npm exec` does not warn, but pnpm remains the supported package manager for OpenClaw.

You can also use:

```bash
pnpm exec openclaw configure
```

If onboarding offers **Anthropic Claude CLI** authentication, the `claude` binary is installed in the image. Run `claude auth login` once in SSH or the ingress terminal before choosing that path, or pick an API-key-based option instead.

For **Google Gemini CLI OAuth**, the `gemini` command is installed globally; complete the browser OAuth step from the prompt (open the URL on your own machine, then paste the redirect URL back into the terminal). OpenClaw discovers it only via `PATH`; this add-on sets `PATH` in `config.json` and symlinks `gemini` into `/usr/bin` so Home Assistant’s container environment still finds it. If you still see “Gemini CLI not found”, rebuild/restart the add-on on **0.5.6+** or run `export PATH="/usr/local/bin:$PATH"` before `npm exec openclaw …`.

The add-on auto-reloads semantic config changes through its own supervisor loop.
Use a full add-on restart when you change build-time behavior such as repository checkout, SSH server setup, or the baked-in image itself:

```bash
ha addons restart local_openclaw
```

## Usage

### SSH Tunnel Access

The Gateway listens on loopback by default. Access it via SSH tunnel:

```bash
ssh -p 2222 -N -L 18789:127.0.0.1:18789 root@<ha-host>
```

Then point OpenClaw.app or the CLI at `ws://127.0.0.1:18789`.

### Browser Usage

Default browser mode is `node_host`.

If you want browser support from another machine:

- keep `browser_runtime_mode=node_host`
- pair a node host that exposes browser capability to the Gateway

If you want explicit remote CDP:

- set `browser_runtime_mode=remote_cdp`
- set `browser_remote_cdp_url`
- optionally set `browser_remote_cdp_profile`

If you want local browser support inside the add-on container:

1. Set `browser_runtime_mode=local`
2. Restart the add-on once so the new mode is applied cleanly
3. Let the add-on validate local browser launch against the baked-in Chromium runtime

If local mode misbehaves, recover by switching `browser_runtime_mode` back to `node_host` or `off` and restarting the add-on or waiting for the add-on-owned reload to apply.

### Google Workspace CLI usage

The add-on includes `gog` for Gmail, Calendar, Drive, Contacts, Sheets, Docs, and Tasks.

If `gog` is already authenticated but Control UI tool runs fail with a keyring or TTY prompt, set:

- `gog_account` to the Google account email you want to use by default
- `gog_keyring_password` to the password that unlocks `gog` token storage

The add-on exports both variables into the runtime environment and SSH shells so `gog` can reuse stored auth without an interactive prompt.

### Bind Mode

Configure bind mode via the OpenClaw CLI over SSH, not in the add-on options.
Use `pnpm exec openclaw configure` or `pnpm exec openclaw onboard` to set it in `openclaw.json`.

## Data Locations

| Path | Description |
| --- | --- |
| `/config/openclaw/.openclaw/openclaw.json` | Main OpenClaw configuration |
| `/config/openclaw/.openclaw/addon-runtime-status.json` | Add-on runtime truth and reload state |
| `/config/openclaw/.openclaw/agent/auth.json` | Authentication tokens |
| `/config/openclaw/workspace` | Agent workspace |
| `/config/openclaw/openclaw-src` | Source repository |
| `/config/openclaw/.ssh` | SSH keys |
| `/config/openclaw/.config` | App configs, including `gh` |
| `/config/openclaw/.cache/ms-playwright` | Playwright Chromium bundle (created after dependency install) |

## Included Tools

- **pnpm** — Installed globally (`npm install -g pnpm`); always on `PATH` via `/usr/local/bin` in the image and add-on runtime
- **claude** — Anthropic Claude Code CLI (`@anthropic-ai/claude-code`), for onboarding flows that use Claude CLI auth
- **codex** — OpenAI Codex CLI (`@openai/codex`), for OpenAI Codex–related onboarding or auth flows that expect `codex` on `PATH`
- **gemini** — Google Gemini CLI (`@google/gemini-cli`), for onboarding flows that use Gemini CLI OAuth
- **gog** — Google Workspace CLI ([gogcli.sh](https://gogcli.sh))
- **gh** — GitHub CLI ([cli.github.com](https://cli.github.com))
- **hass-cli** — Home Assistant CLI

## Troubleshooting

### SSH does not work

Ensure `ssh_authorized_keys` is set in the add-on options with your public key.

### Ingress onboarding does not load

Open the add-on from Home Assistant, not by browsing directly to port `8099`.
The ingress listener is intended for Home Assistant's internal proxy only.

### Onboarding finishes but the Control UI stays blank

The Control UI must be rendered through the Home Assistant add-on panel, not by connecting directly to the internal ingress port.
Confirm the add-on log shows the latest `run.sh version=` line after updating.

### The Control UI loads but does not connect

Refresh the add-on page once after updating so the current token bootstrap script and ingress WebSocket bootstrap can run.

### `openclaw gateway restart` says the gateway service is disabled

That is expected in this deployment model.

The live Gateway process is supervised by the add-on, not by upstream daemon or `systemd user service` management.
If you need a full restart:

```bash
ha addons restart local_openclaw
```

If you need to confirm runtime truth, inspect `/config/openclaw/.openclaw/addon-runtime-status.json`.

### I want the add-on panel to use the terminal UI instead

Set `ingress_ui_mode=tui` in the add-on options and restart the add-on.

### Local browser mode fails

Switch `browser_runtime_mode` back to `node_host` or `off`, then restart the add-on or let the add-on-owned reload apply.

Remember:

- local mode is headless-only
- Chromium is baked into the image
- `browser.noSandbox=true` is a container-specific compatibility setting here
- `node_host` remains the default browser mode

### “Port 18789 is already in use” / “gateway already running” after a config reload

The add-on signals the live gateway for hot reload when `openclaw.json` changes. If you still see this on an older add-on build, upgrade to the current image: the supervisor now treats Linux SIGUSR1 exits correctly and runs `gateway stop` before starting a new listener so the port is not left stuck.

### Gateway does not start

Check logs:

```bash
ha addons logs local_openclaw -n 200
```

### Build takes too long

The first boot runs a full build and may take several minutes. Subsequent starts are faster.

## Docker / fleet operations (how this add-on maps to common practices)

| Practice | In this project |
| --- | --- |
| **Multi-stage builds** | The image is not multi-stage: OpenClaw is **cloned and built at container start** into `/config/openclaw/openclaw-src`, so compilers (`g++`, `make`) stay in the runtime image by design. A smaller image would require **baking** a prebuilt OpenClaw artifact in CI and dropping build tools from the final stage (larger change). |
| **Layer caching** | Stable steps (apt, global npm CLIs) are ordered before `COPY` of add-on scripts so cache hits are more likely on script-only changes. |
| **Minimal base** | Uses **`node:*-bookworm-slim`**, not the full bookworm image. Distroless is a poor fit while `run.sh` needs a shell, `apt` (Playwright `install-deps`), `nginx`, and `sshd`. |
| **Pin base versions** | The Dockerfile pins the Node base image to a **SHA256 digest**; refresh it when bumping the Node major or for security rebuilds (`docker buildx imagetools inspect node:24-bookworm-slim`). |
| **Resource limits** | Set CPU/memory caps in **Home Assistant** for the add-on container where your Supervisor version supports it, so the gateway cannot starve the host. |
| **Ephemeral containers** | Stateful data is only under **`/config/openclaw`** (mapped volume). The container itself is replaceable; do not rely on writes outside `/config`. |
| **Secrets** | Use add-on options (`github_token`, `ha_token`, gateway token in `openclaw.json`) and **never** bake secrets into the image. |
| **Logging** | Primary diagnostics: **`ha addons logs`** (Supervisor captures container stdout/stderr from `/run.sh` and children). |
| **Non-root** | The process runs as **root**, which is typical for HA add-ons that own `/config` bind mounts and optional `sshd`. Tightening this would need Supervisor-compatible UID/GID mapping. |
| **Vulnerability scanning** | Run **Trivy**, **Snyk**, or registry scanning on built images before publishing to a registry. |
| **Health checks** | The Dockerfile defines **`HEALTHCHECK`** against `http://127.0.0.1:18789/healthz` with a long **start-period** for first-boot builds. Orchestrator behavior depends on your environment. |

## Supported vs limited on Home Assistant

| Area | On this add-on |
| --- | --- |
| Gateway + Control UI + ingress | Supported |
| Provider CLI onboarding (`claude`, `codex`, `gemini`, …) | Supported on **amd64** with explicit `PATH` / symlinks |
| Local browser (`browser_runtime_mode=local`) | System Chromium + validated profile |
| Playwright-downloaded Chromium | Installed to `/config/openclaw/.cache/ms-playwright` for upstream-aligned automation |
| Agent sandbox (`agents.defaults.sandbox` + host Docker) | **Not wired by default**; mounting host `docker.sock` would be a major trust decision on HA OS. Prefer `sandbox.mode: off` here or run OpenClaw on a full Docker/VM host for sandboxing. |

## Security Notes

- For `bind=lan/tailnet/auto`, enable gateway auth in `openclaw.json`
- SSH access is exposed only through the configured add-on port mapping
- Local browser mode uses `browser.noSandbox=true` only as a Home Assistant add-on container compatibility tradeoff

## Links

- [OpenClaw](https://github.com/openclaw/openclaw) — Main repository
- [Documentation](https://docs.openclaw.io) — Full documentation
- [Community](https://discord.com/invite/openclaw) — Discord server
- [gog CLI](https://gogcli.sh) — Google Workspace CLI
- [GitHub CLI](https://cli.github.com) — GitHub CLI
