# Ensure npm global CLIs resolve even when the container/supervisor supplies a minimal PATH.
# OpenClaw Gemini OAuth calls findInPath("gemini") against process.env.PATH only.
export PATH="/config/openclaw/bin:/usr/local/bin:/usr/local/sbin:/usr/local/bun/bin:/pnpm:/usr/sbin:/usr/bin:/sbin:/bin"
export PLAYWRIGHT_BROWSERS_PATH="/config/openclaw/.cache/ms-playwright"
