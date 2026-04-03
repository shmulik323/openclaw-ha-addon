# Pin digest for reproducible builds (update via: docker buildx imagetools inspect node:24-bookworm-slim).
# Manifest list digest; amd64-only add-on still benefits from immutable base resolution.
FROM node:24-bookworm-slim@sha256:06e5c9f86bfa0aaa7163cf37a5eaa8805f16b9acb48e3f85645b09d459fc2a9f

LABEL org.opencontainers.image.base.name="docker.io/library/node:24-bookworm-slim" \
  org.opencontainers.image.base.digest="sha256:06e5c9f86bfa0aaa7163cf37a5eaa8805f16b9acb48e3f85645b09d459fc2a9f"

# Use bash with pipefail so curl|tar failures stop the build.
SHELL ["/bin/bash", "-o", "pipefail", "-c"]

# Pull latest Debian security updates, then clean apt caches.
RUN apt-get update \
  && apt-get upgrade -y \
  && apt-get install -y --no-install-recommends \
  bash \
  ca-certificates \
  chromium \
  curl \
  g++ \
  git \
  hostname \
  jq \
  lsof \
  make \
  nano \
  nginx \
  openssh-server \
  openssl \
  procps \
  python3 \
  python3-pip \
  ripgrep \
  unzip \
  xvfb \
  && apt-get clean \
  && rm -rf /var/lib/apt/lists/*

# Install GitHub CLI
RUN curl -fsSL https://cli.github.com/packages/githubcli-archive-keyring.gpg | dd of=/usr/share/keyrings/githubcli-archive-keyring.gpg \
  && chmod go+r /usr/share/keyrings/githubcli-archive-keyring.gpg \
  && echo "deb [arch=$(dpkg --print-architecture) signed-by=/usr/share/keyrings/githubcli-archive-keyring.gpg] https://cli.github.com/packages stable main" | tee /etc/apt/sources.list.d/github-cli.list > /dev/null \
  && apt-get update \
  && apt-get install -y gh \
  && rm -rf /var/lib/apt/lists/*

ENV BUN_INSTALL=/usr/local/bun
ENV PNPM_HOME=/pnpm
# pnpm and other npm -g tools live under /usr/local/bin; keep that early so every shell finds them.
ENV PATH="/usr/local/bin:/usr/local/sbin:/usr/local/bun/bin:/pnpm:/usr/sbin:/usr/bin:/sbin:/bin"

RUN curl -fsSL https://bun.sh/install | bash

RUN npm install -g pnpm @anthropic-ai/claude-code @google/gemini-cli @openai/codex \
  && mkdir -p /pnpm \
  && pnpm config set global-bin-dir /pnpm \
  && command -v pnpm \
  && pnpm --version \
  && command -v gemini \
  && command -v claude \
  && command -v codex \
  && ln -sf /usr/local/bin/gemini /usr/bin/gemini \
  && ln -sf /usr/local/bin/claude /usr/bin/claude \
  && ln -sf /usr/local/bin/codex /usr/bin/codex \
  && ln -sf /usr/local/bin/pnpm /usr/bin/pnpm \
  && command -v gemini && command -v claude && command -v codex && command -v pnpm

RUN pip3 install --no-cache-dir --break-system-packages homeassistant-cli

# Install gog CLI (Google Workspace: Gmail, Calendar, Drive, Contacts, Sheets, Docs)
ARG GOG_VERSION=0.6.1
ARG TARGETARCH
RUN ARCH=$(echo ${TARGETARCH:-$(uname -m)} | sed 's/aarch64/arm64/;s/x86_64/amd64/') \
  && curl -fsSL "https://github.com/steipete/gogcli/releases/download/v${GOG_VERSION}/gogcli_${GOG_VERSION}_linux_${ARCH}.tar.gz" \
  | tar xz -C /usr/local/bin gog \
  && chmod +x /usr/local/bin/gog

WORKDIR /opt/openclaw

COPY onboarding.mjs /onboarding.mjs
COPY onboarding.html /onboarding.html
COPY runtime-helper.mjs /runtime-helper.mjs
COPY nginx.conf /nginx.conf.tpl
COPY run.sh /run.sh
COPY openclaw-path.sh /etc/profile.d/openclaw-path.sh
RUN chmod +x /run.sh

# Gateway listens on 18789 after clone/build; first start can take many minutes (pnpm + Playwright).
# Supervisor may ignore HEALTHCHECK, but it helps local/docker runs and documents expected readiness.
HEALTHCHECK --interval=2m --timeout=15s --start-period=25m --retries=3 \
  CMD curl -fsS http://127.0.0.1:18789/healthz >/dev/null || exit 1

CMD [ "/run.sh" ]
