# Changelog

## 0.5.5

- **Fix**: Treat Linux SIGUSR1 shutdown as exit status **138** (128+10), not 129 (SIGHUP), so config hot-reload no longer looks like a crash and avoids the “fallback restart” path.
- **Fix**: On reload, send SIGUSR1 to both the supervised `node` child and its children so the gateway tree gets a consistent signal.
- **Fix**: Before restarting the gateway after a prior cycle, run `openclaw gateway stop` (`node scripts/run-node.mjs gateway stop`) so a stale listener cannot keep port `18789` and block the next start.
- **Tweak**: Extend the initial gateway `/healthz` wait window to 90s to reduce false “not ready” logs on slow starts.

## 0.5.3/4

- **Fix**: Ship Google Gemini CLI (`gemini`, `@google/gemini-cli`) globally so OpenClaw onboarding can use “Gemini CLI OAuth” inside the container.
- **Fix**: Strip `node-linker` from the cloned repo `.npmrc` more defensively (optional whitespace, CRLF) so `npm exec` under `openclaw-src` stops warning after add-on sync.

## 0.5.2

- **Fix**: Remove pnpm-only `node-linker` from the cloned OpenClaw `.npmrc` after sync and pass `--config.node-linker=hoisted` to `pnpm install` so dependency layout stays stable while `npm exec` from `openclaw-src` no longer warns.
- **Fix**: Ship the Anthropic Claude Code CLI (`claude`) in the image so OpenClaw onboarding can use the “Anthropic Claude CLI” auth path; run `claude auth login` in the add-on terminal or SSH session when that method is selected.
- **Fix**: Put `/usr/local/bin` and `/usr/local/sbin` on `PATH` for the supervisor and SSH profile so globally installed `pnpm` (and `claude`) always resolve; Dockerfile `PATH` puts those dirs first and the image build fails if `pnpm` is missing.

## 0.5.1

- **Fix**: Persist `gateway.nodes.browser.mode=auto` correctly in `node_host` mode.
  - Prevent repeated reconcile writes for the same browser node-host setting on every startup.
  - Keep `node_host` mode stable without noisy `config reconcile: gateway.nodes.browser.mode=auto` log lines after the first persisted write.

## 0.5.0

- **Feature**: Make the add-on the canonical Gateway supervisor and config reload path.
  - The add-on now watches semantic `openclaw.json` and supported add-on option changes instead of relying on upstream daemon or service restart semantics.
  - Runtime truth is written to `/config/openclaw/.openclaw/addon-runtime-status.json`, including supervisor PID, child PID, digests, browser mode, reload state, and the last reload result or error.
  - The add-on now logs explicitly that `openclaw gateway restart` is not the runtime control plane inside Home Assistant.
- **Feature**: Add supported browser runtime modes.
  - New add-on option: `browser_runtime_mode=node_host|local|remote_cdp|off`.
  - `node_host` is the default supported mode.
  - `local` is supported but opt-in in this first release.
  - `remote_cdp` is supported for explicit remote browser endpoints.
  - `off` disables browser runtime management.
- **Feature**: Add baked-in local Chromium support for opt-in local browser mode.
  - The add-on image now installs Chromium and wires `browser.executablePath=/usr/bin/chromium` when `browser_runtime_mode=local`.
  - Local mode forces `browser.headless=true` and `browser.noSandbox=true` as a Home Assistant add-on container compatibility setting.
  - Local browser launch is validated through `openclaw browser start` after the Gateway becomes ready.
- **Docs**: Document browser modes, add-on-owned reload behavior, local browser tradeoffs, and rollback guidance.

## 0.4.24

- **Fix**: Improve ingress Control UI WebSocket compatibility.
  - Preserve Home Assistant forwarded host/proto headers through the ingress proxy instead of trusting the rewritten internal request host.
  - Synthesize a matching `Origin` header for the gateway WebSocket handshake on the ingress path.
  - Seed `gateway.controlUi.allowedOrigins` from Home Assistant `internal_url` and `external_url` when available.
  - Inject the exact ingress `gatewayUrl` into the dashboard bootstrap flow instead of relying on OpenClaw's default browser URL inference.

## 0.4.23

- **Feature**: Add configurable ingress UI modes.
  - New add-on option: `ingress_ui_mode=auto|control_ui|tui`.
  - `auto` keeps the first-run onboarding terminal, then switches to the embedded Control UI once `openclaw.json` exists.
  - `tui` keeps the add-on panel on `openclaw tui` after onboarding for users who prefer the terminal workflow.

## 0.4.22

- **Fix**: Disable Control UI device-identity enforcement for Home Assistant ingress sessions.
  - Set `gateway.controlUi.dangerouslyDisableDeviceAuth=true` during add-on startup.
  - Keep token auth enabled while bypassing OpenClaw's non-local browser pairing/device checks.
  - Preserve the ingress host/origin compatibility work from `0.4.21`.

## 0.4.21

- **Fix**: Make the ingress Control UI connect automatically after onboarding.
  - Preserve the full Home Assistant host header, including port, through the ingress proxy.
  - Enable Control UI Host-header origin fallback for the Home Assistant ingress origin.
  - Inject the generated gateway token into the browser URL fragment on first ingress load so the dashboard can connect without manual token copy/paste.

## 0.4.20

- **Fix**: Allow the OpenClaw Control UI to render inside Home Assistant ingress after onboarding.
  - Strip the upstream `X-Frame-Options: DENY` response on the ingress proxy only.
  - Replace the upstream `frame-ancestors 'none'` CSP with an iframe-safe ingress policy.
  - Keep the upstream gateway process unchanged outside the Home Assistant ingress path.

## 0.4.19

- **Fix**: Ensure `pnpm` global installs work during onboarding and runtime.
  - Put `/pnpm` on the image `PATH`.
  - Export `PNPM_HOME` and `/pnpm` from the add-on runtime before onboarding starts.
  - Reapply `pnpm`'s global bin directory in the runtime environment.

## 0.4.18

- **Fix**: Make the ingress onboarding layout responsive and keep controls visible.
  - Move the Start button and status into the terminal panel.
  - Allow the page to scroll on smaller screens instead of clipping controls.
  - Keep the terminal large without pushing the control bar out of view.

## 0.4.17

- **Fix**: Expand and fit the ingress onboarding terminal to the available page size.
  - Resize the xterm canvas to match the ingress viewport.
  - Start onboarding with the fitted terminal rows and columns.
  - Redesign the page so the terminal uses nearly the full width and about 90% of the height.

## 0.4.16

- **Fix**: Restore interactive input in ingress onboarding.
  - Forward WebSocket keystrokes to the onboarding process after startup.
  - Run onboarding inside a pseudo-terminal so interactive prompts behave correctly.
  - Return keyboard focus to the terminal after pressing Start.

## 0.4.15

- **Fix**: Use ingress-safe client URLs in the onboarding page.
  - Open the WebSocket on the current ingress path instead of the Home Assistant root.
  - Call onboarding health and shutdown endpoints through the ingress path.
  - Keep the Start button disabled until the onboarding socket is actually connected.

## 0.4.14

- **Fix**: Make first-run onboarding available through Home Assistant ingress.
  - Start the ingress proxy before the onboarding server so the add-on panel works on first boot.
  - Render nginx against the configured gateway port instead of hard-coding `18789`.
- **Fix**: Restrict the ingress listener to Home Assistant's internal proxy path.
  - Stop publishing the ingress port as a host port.
  - Deny direct non-ingress access at nginx level.
- **Fix**: Ensure `gateway.auth.token` exists before the gateway starts.
- **Docs**: Update quick-start and docs to point users at ingress onboarding first.

## 0.4.13

- **Feature**: Add Home Assistant API integration.
  - Enable `hassio_api`, `homeassistant_api`, and `auth_api` for Supervisor access.
  - Export `HA_URL` (`http://supervisor/core/api`) and `HA_TOKEN` env vars.
  - Uses `SUPERVISOR_TOKEN` automatically, or the user-provided `ha_token` option.
  - OpenClaw can now interact with Home Assistant entities and services.

## 0.4.12

- **Fix**: Auto-configure `gateway.trustedProxies` for nginx reverse proxy.
  - The gateway was rejecting connections because it did not trust nginx's proxy headers.
  - Now trusts `127.0.0.1` and `172.30.32.0/24` (HA Supervisor network).

## 0.4.11

- **Fix**: Auto-enable `gateway.controlUi.allowInsecureAuth=true` for HA ingress.
  - Ingress uses HTTP internally, which triggers OpenClaw's secure context check.
  - This setting allows token-only auth over HTTP.

## 0.4.10

- **Fix**: Disable `host_network` for proper ingress support.
  - Ingress requires standard Docker networking to reach the add-on via internal IP.
  - SSH port `2222` is now exposed via port mapping instead.
  - Added `proxy_buffering off` to nginx for better WebSocket support.

## 0.4.9

- **Fix**: Add nginx reverse proxy to enable HA ingress with `host_network: true`.
  - nginx binds to `0.0.0.0:8099` and forwards to the gateway on `127.0.0.1:18789`.
  - `ingress_port` changed to `8099` to match nginx.
  - Removed invalid `--host` flag and `HOST` environment variable.

## 0.4.8

- **Fix**: Use `HOST=0.0.0.0` environment variable instead of `--host`.

## 0.4.7

- **Fix**: Gateway now binds to `0.0.0.0` instead of `127.0.0.1` so HA ingress can reach it.

## 0.4.6

- **Fix**: Replace `node-pty` with built-in `child_process` to avoid native module loading issues.
- **Fix**: Use compatible `import.meta.url` path resolution.
- **Added**: Extensive onboarding server logging for debugging.

## 0.4.5

- **Reverted**: Removed Antigravity User-Agent fix.
- **Fix**: Onboarding UI now starts correctly.
  - Read `port` from options before launching the onboarding server.
  - Copy onboarding files into `REPO_DIR` so native modules can be loaded.

## 0.4.0

- Major: Add Home Assistant sidebar integration (`panel: true`).
- Feature: New interactive onboarding UI with embedded terminal (`xterm.js`).
- Feature: Auto-reload logic to transition from setup to the OpenClaw Dashboard.
- Fix: Gateway now uses ingress for secure internal proxy access.

## 0.3.21

- Fix: CLI invocation now uses `node scripts/run-node.mjs` instead of `pnpm exec openclaw`.

## 0.3.0

- BREAKING: Migrated from Clawdbot to OpenClaw (`https://github.com/openclaw/openclaw`)
- Renamed addon slug from `clawdbot_gateway` to `openclaw_gateway`
- Updated all paths from `/config/clawdbot` to `/config/openclaw`
- Updated CLI commands from `clawdbot` to `openclaw`
- Updated config files from `clawdbot.json` to `openclaw.json`
- Fixed CLI invocation to use `pnpm exec openclaw` instead of `pnpm clawdbot`

## 0.2.15

- Fix: install dev dependencies so gateway builds include `tsc`. (#9)

## 0.2.14

- Add pretty log formatting options for the add-on Log tab.

## 0.2.13

- Add `icon.png` and `logo.png`.
- Add `DOCS.md` with detailed documentation.
- Simplify README.md as add-on store intro.
- Follow Home Assistant add-on presentation best practices.

## 0.2.12

- Docker: install Bun runtime.

## 0.2.11

- Docker: install GitHub CLI.
- Storage: persist root home directories under `/config/clawdbot`.
- Docker: refresh base image and toolchain, and update gogcli. Thanks @niemyjski. (PR #2)

## 0.2.10

- Fix: remove unsupported pnpm install flag in the add-on image.

## 0.2.9

- Install: auto-confirm module purge only when needed.

## 0.2.8

- Install: always reinstall dependencies without confirmation.

## 0.2.7

- Docker: install clawdhub and Home Assistant CLI.

## 0.2.6

- Auto-restart gateway on unclean exits.

## 0.2.5

- BREAKING: Renamed `repo_ref` to `branch`. Set it to track a specific branch; omit it to use the repo default.
- Config: `github_token` now uses a password field.

## 0.2.4

- Docs: repo-based install steps and add-on info links.
- Docker: set `WORKDIR` to `/opt/clawdbot`.
- Logs: stream the gateway log file into add-on stdout.
- Docker: add ripgrep for faster log searches.

## 0.2.3

- Docs: repo-based install steps and add-on info links.
- Docker: set `WORKDIR` to `/opt/clawdbot`.
- Logs: stream the gateway log file into add-on stdout.

## 0.2.2

- Add HA add-on repository layout and improved `SIGUSR1` handling.
- Support pinning upstream refs and clean checkouts.

## 0.2.1

- Ensure `gateway.mode=local` on first boot.

## 0.2.0

- Initial Home Assistant add-on.
