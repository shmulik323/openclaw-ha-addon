# Changelog

## 0.4.4

- **Fix**: Onboarding UI now starts correctly.
  - Read `port` from options before launching the onboarding server.
  - Copy onboarding files into `REPO_DIR` so native modules (`node-pty`) can be loaded.

## 0.4.3

- **Fix**: Apply Antigravity User-Agent patches AFTER `pnpm install` but BEFORE `pnpm build`.
  - Previous versions applied patches at the wrong time in the startup sequence.
  - Now patches are applied unconditionally every startup, ensuring the fix is always active.

## 0.4.1

- **Temporary Fix**: Patch Antigravity User-Agent header to fix "This version of Antigravity is no longer supported" error when using the `google-antigravity` provider.
  - Applies the fix from OpenClaw PR #4603 during Docker build.
  - Updates User-Agent to `antigravity/1.15.8 linux/arm64`.
  - **Note**: This is a temporary workaround until the main OpenClaw project merges the fix upstream.

## 0.4.0

- Major: Add Home Assistant Sidebar integration (`panel: true`).
- Feature: New interactive Onboarding UI with embedded terminal (`xterm.js`).
- Feature: Auto-reload logic to transition from setup to the OpenClaw Dashboard.
- Fix: Gateway now uses `ingress` for secure internal proxy access.

## 0.3.21

- Fix: CLI invocation now uses `node scripts/run-node.mjs` instead of `pnpm exec openclaw` to match how the openclaw monorepo runs its CLI.

## 0.3.0

- BREAKING: Migrated from Clawdbot to OpenClaw (https://github.com/openclaw/openclaw)
- Renamed addon slug from `clawdbot_gateway` to `openclaw_gateway`
- Updated all paths from `/config/clawdbot` to `/config/openclaw`
- Updated CLI commands from `clawdbot` to `openclaw`
- Updated config files from `clawdbot.json` to `openclaw.json`
- Fixed CLI invocation to use `pnpm exec openclaw` instead of `pnpm clawdbot`

## 0.2.15

- Fix: install dev dependencies so gateway builds include tsc. (#9)

## 0.2.14

- Add pretty log formatting options for the add-on Log tab.

## 0.2.13

- Add icon.png and logo.png (cyber-lobster mascot).
- Add DOCS.md with detailed documentation.
- Simplify README.md as add-on store intro.
- Follow Home Assistant add-on presentation best practices.

## 0.2.12

- Docker: install Bun runtime.

## 0.2.11

- Docker: install GitHub CLI.
- Storage: persist root home directories under /config/clawdbot.
- Docker: refresh base image/toolchain and update gogcli. Thanks @niemyjski! (PR #2)

## 0.2.10

- Fix: remove unsupported pnpm install flag in add-on image.

## 0.2.9

- Install: auto-confirm module purge only when needed.

## 0.2.8

- Install: always reinstall dependencies without confirmation.

## 0.2.7

- Docker: install clawdhub and Home Assistant CLI.

## 0.2.6

- Auto-restart gateway on unclean exits (e.g., shutdown timeout).

## 0.2.5

- BREAKING: Renamed `repo_ref` to `branch`. Set to track a specific branch; omit to use repo's default.
- Config: `github_token` now uses password field (masked in UI).

## 0.2.4

- Docs: repo-based install steps and add-on info links.
- Docker: set WORKDIR to /opt/clawdbot.
- Logs: stream gateway log file into add-on stdout.
- Docker: add ripgrep for faster log searches.

## 0.2.3

- Docs: repo-based install steps and add-on info links.
- Docker: set WORKDIR to /opt/clawdbot.
- Logs: stream gateway log file into add-on stdout.

## 0.2.2

- Add HA add-on repository layout and improved SIGUSR1 handling.
- Support pinning upstream refs and clean checkouts.

## 0.2.1

- Ensure gateway.mode=local on first boot.

## 0.2.0

- Initial Home Assistant add-on.
