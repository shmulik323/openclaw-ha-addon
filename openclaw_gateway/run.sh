#!/usr/bin/env bash
set -euo pipefail

log() {
  printf "[addon] %s\n" "$*"
}

log "run.sh version=2026-04-03-sigusr1-reload-port-teardown"

BASE_DIR=/config/openclaw
STATE_DIR="${BASE_DIR}/.openclaw"
REPO_DIR="${BASE_DIR}/openclaw-src"
WORKSPACE_DIR="${BASE_DIR}/workspace"
SSH_AUTH_DIR="${BASE_DIR}/.ssh"
BUN_INSTALL="${BUN_INSTALL:-/usr/local/bun}"
PNPM_HOME="${PNPM_HOME:-/pnpm}"
TERMINAL_UI_PORT=18080
RUNTIME_HELPER=/runtime-helper.mjs
STATUS_FILE="${STATE_DIR}/addon-runtime-status.json"
RELOAD_REASON_FILE="${STATE_DIR}/addon-reload-reason"
LOCAL_BROWSER_EXECUTABLE=/usr/bin/chromium
SUPERVISOR_PID="$$"

mkdir -p "${BASE_DIR}" "${STATE_DIR}" "${WORKSPACE_DIR}" "${SSH_AUTH_DIR}" "${PNPM_HOME}"

mkdir -p \
  "${BASE_DIR}/.config/gh" \
  "${BASE_DIR}/.local" \
  "${BASE_DIR}/.cache" \
  "${BASE_DIR}/.npm" \
  "${BASE_DIR}/bin"

for dir in .ssh .config .local .cache .npm; do
  target="${BASE_DIR}/${dir}"
  link="/root/${dir}"
  if [ -L "${link}" ]; then
    :
  elif [ -d "${link}" ]; then
    cp -rn "${link}/." "${target}/" 2>/dev/null || true
    rm -rf "${link}"
    ln -s "${target}" "${link}"
  else
    rm -f "${link}" 2>/dev/null || true
    ln -s "${target}" "${link}"
  fi
done
log "persistent home symlinks configured"

if [ -d /root/.openclaw ] && [ ! -f "${STATE_DIR}/openclaw.json" ]; then
  cp -a /root/.openclaw/. "${STATE_DIR}/"
fi

if [ -d /root/openclaw-src ] && [ ! -d "${REPO_DIR}" ]; then
  mv /root/openclaw-src "${REPO_DIR}"
fi

if [ -d /root/workspace ] && [ ! -d "${WORKSPACE_DIR}" ]; then
  mv /root/workspace "${WORKSPACE_DIR}"
fi

export HOME="${BASE_DIR}"
export BUN_INSTALL="${BUN_INSTALL}"
export PNPM_HOME="${PNPM_HOME}"
# npm -g installs pnpm/claude under /usr/local/bin; keep that on PATH for HA supervisor + SSH.
export PATH="${BASE_DIR}/bin:${BUN_INSTALL}/bin:${PNPM_HOME}:/usr/local/bin:/usr/local/sbin:${PATH}"
export OPENCLAW_STATE_DIR="${STATE_DIR}"
export OPENCLAW_CONFIG_PATH="${STATE_DIR}/openclaw.json"
export HA_URL="http://supervisor/core/api/"

HA_TOKEN_OPT="$(jq -r '.ha_token // empty' /data/options.json 2>/dev/null || true)"
if [ -n "${HA_TOKEN_OPT}" ] && [ "${HA_TOKEN_OPT}" != "null" ]; then
  export HA_TOKEN="${HA_TOKEN_OPT}"
  log "HA_TOKEN set from add-on options"
elif [ -n "${SUPERVISOR_TOKEN:-}" ]; then
  export HA_TOKEN="${SUPERVISOR_TOKEN}"
  log "HA_TOKEN set from SUPERVISOR_TOKEN"
else
  log "HA_TOKEN not available (set ha_token in add-on config if needed)"
fi

log "config path=${OPENCLAW_CONFIG_PATH}"

cat > /etc/profile.d/openclaw.sh <<EOF
export HOME="${BASE_DIR}"
export GH_CONFIG_DIR="${BASE_DIR}/.config/gh"
export BUN_INSTALL="${BUN_INSTALL}"
export PNPM_HOME="${PNPM_HOME}"
export PATH="${BASE_DIR}/bin:${BUN_INSTALL}/bin:${PNPM_HOME}:/usr/local/bin:/usr/local/sbin:\${PATH}"
if [ -n "\${SSH_CONNECTION:-}" ]; then
  export OPENCLAW_STATE_DIR="${STATE_DIR}"
  export OPENCLAW_CONFIG_PATH="${STATE_DIR}/openclaw.json"
  cd "${REPO_DIR}" 2>/dev/null || true
fi
EOF

pnpm config set global-bin-dir "${PNPM_HOME}" >/dev/null 2>&1 || true

auth_from_opts() {
  local val
  val="$(jq -r .ssh_authorized_keys /data/options.json 2>/dev/null || true)"
  if [ -n "${val}" ] && [ "${val}" != "null" ]; then
    printf "%s" "${val}"
  fi
}

REPO_URL="$(jq -r .repo_url /data/options.json)"
BRANCH="$(jq -r .branch /data/options.json 2>/dev/null || true)"
TOKEN_OPT="$(jq -r .github_token /data/options.json)"

if [ -z "${REPO_URL}" ] || [ "${REPO_URL}" = "null" ]; then
  log "repo_url is empty; set it in add-on options"
  exit 1
fi

if [ -n "${TOKEN_OPT}" ] && [ "${TOKEN_OPT}" != "null" ]; then
  REPO_URL="https://${TOKEN_OPT}@${REPO_URL#https://}"
fi

SSH_PORT="$(jq -r .ssh_port /data/options.json 2>/dev/null || true)"
SSH_KEYS="$(auth_from_opts || true)"
SSH_PORT_FILE="${STATE_DIR}/ssh_port"
SSH_KEYS_FILE="${STATE_DIR}/ssh_authorized_keys"

if [ -z "${SSH_PORT}" ] || [ "${SSH_PORT}" = "null" ]; then
  if [ -f "${SSH_PORT_FILE}" ]; then
    SSH_PORT="$(cat "${SSH_PORT_FILE}")"
  else
    SSH_PORT="2222"
  fi
fi

if [ -z "${SSH_KEYS}" ] || [ "${SSH_KEYS}" = "null" ]; then
  if [ -f "${SSH_KEYS_FILE}" ]; then
    SSH_KEYS="$(cat "${SSH_KEYS_FILE}")"
  fi
fi

if [ -n "${SSH_KEYS}" ] && [ "${SSH_KEYS}" != "null" ]; then
  printf "%s\n" "${SSH_PORT}" > "${SSH_PORT_FILE}"
  printf "%s\n" "${SSH_KEYS}" > "${SSH_KEYS_FILE}"
  chmod 700 "${SSH_AUTH_DIR}"
  printf "%s\n" "${SSH_KEYS}" > "${SSH_AUTH_DIR}/authorized_keys"
  chmod 600 "${SSH_AUTH_DIR}/authorized_keys"

  mkdir -p /var/run/sshd
  cat > /etc/ssh/sshd_config <<EOF_SSH
Port ${SSH_PORT}
Protocol 2
PermitRootLogin prohibit-password
PasswordAuthentication no
PubkeyAuthentication yes
AuthorizedKeysFile ${SSH_AUTH_DIR}/authorized_keys
ChallengeResponseAuthentication no
ClientAliveInterval 30
ClientAliveCountMax 3
EOF_SSH

  ssh-keygen -A
  /usr/sbin/sshd -e -f /etc/ssh/sshd_config
  log "sshd listening on ${SSH_PORT}"
else
  log "sshd disabled (no authorized keys)"
fi

if [ "${BRANCH}" = "null" ]; then
  BRANCH=""
fi

if [ -n "${BRANCH}" ]; then
  log "branch=${BRANCH}"
fi

if [ ! -d "${REPO_DIR}/.git" ]; then
  log "cloning repo ${REPO_URL} -> ${REPO_DIR}"
  rm -rf "${REPO_DIR}"
  if [ -n "${BRANCH}" ]; then
    git clone --branch "${BRANCH}" "${REPO_URL}" "${REPO_DIR}"
  else
    git clone "${REPO_URL}" "${REPO_DIR}"
  fi
else
  log "updating repo in ${REPO_DIR}"
  git -C "${REPO_DIR}" remote set-url origin "${REPO_URL}"
  git -C "${REPO_DIR}" fetch --prune
  git -C "${REPO_DIR}" reset --hard
  git -C "${REPO_DIR}" clean -fd
  if [ -n "${BRANCH}" ]; then
    git -C "${REPO_DIR}" checkout "${BRANCH}"
    git -C "${REPO_DIR}" reset --hard "origin/${BRANCH}"
  else
    DEFAULT_BRANCH="$(git -C "${REPO_DIR}" remote show origin | sed -n '/HEAD branch/s/.*: //p')"
    git -C "${REPO_DIR}" checkout "${DEFAULT_BRANCH}"
    git -C "${REPO_DIR}" reset --hard "origin/${DEFAULT_BRANCH}"
  fi
  git -C "${REPO_DIR}" clean -fd
fi

cd "${REPO_DIR}"

# Upstream .npmrc sets node-linker=hoisted (pnpm-only). npm warns when users run
# `npm exec` from this tree; drop the key and pass hoisted layout to pnpm explicitly.
if [ -f "${REPO_DIR}/.npmrc" ]; then
  sed -i 's/\r$//' "${REPO_DIR}/.npmrc" 2>/dev/null || true
  sed -i '/^[[:space:]]*node-linker[[:space:]]*=/d' "${REPO_DIR}/.npmrc" 2>/dev/null || true
fi

log "installing dependencies"
pnpm config set confirmModulesPurge false >/dev/null 2>&1 || true
pnpm install --config.node-linker=hoisted --no-frozen-lockfile --prefer-frozen-lockfile --prod=false

log "building gateway"
pnpm build
if [ ! -d "${REPO_DIR}/ui/node_modules" ]; then
  log "installing UI dependencies"
  pnpm ui:install
fi
log "building control UI"
pnpm ui:build

copy_terminal_ui_files() {
  cp /onboarding.mjs "${REPO_DIR}/onboarding.mjs"
  cp /onboarding.html "${REPO_DIR}/onboarding.html"
}

terminal_ui_pid=""
tail_pid=""
child_pid=""
watcher_pid=""
NGINX_STARTED="false"
INGRESS_UI_SELECTION="auto"
INGRESS_ROOT_MODE="onboarding"
CURRENT_RUNTIME_DIGEST=""
RUNTIME_STATE_JSON='{}'
LOG_FILE="/tmp/openclaw/openclaw.log"
PORT="18789"
VERBOSE="false"
LOG_FORMAT="pretty"
LOG_COLOR="false"
LOG_FIELDS=""
BROWSER_MODE="node_host"
LOCAL_BROWSER_DETECTED="false"
LOCAL_BROWSER_LAUNCH_VALIDATED="false"
BROWSER_RUNTIME_ACTIVE="false"
BROWSER_STATUS_REASON="runtime state not initialized yet"
LAST_RELOAD_RESULT="pending"
LAST_RELOAD_REASON="startup"
LAST_RELOAD_ERROR=""
RELOAD_PENDING="false"
RELOAD_FALLBACK_USED="false"

resolve_effective_ingress_mode() {
  local selection="$1"
  local config_exists="$2"

  if [ "${config_exists}" != "true" ]; then
    printf "onboarding"
    return
  fi

  if [ "${selection}" = "tui" ]; then
    printf "tui"
    return
  fi

  printf "control_ui"
}

start_terminal_ui_background() {
  local mode="$1"

  if [ -n "${terminal_ui_pid}" ] && kill -0 "${terminal_ui_pid}" 2>/dev/null; then
    return
  fi

  copy_terminal_ui_files
  OPENCLAW_TERMINAL_MODE="${mode}" node "${REPO_DIR}/onboarding.mjs" "${TERMINAL_UI_PORT}" &
  terminal_ui_pid=$!
  log "started ${mode} terminal UI on port ${TERMINAL_UI_PORT}"
}

stop_terminal_ui_background() {
  if [ -n "${terminal_ui_pid}" ]; then
    kill -TERM "${terminal_ui_pid}" 2>/dev/null || true
    terminal_ui_pid=""
  fi
}

render_ingress_proxy() {
  local upstream_port="${PORT}"
  local token_b64=""
  local config_exists

  config_exists="$(printf '%s' "${RUNTIME_STATE_JSON}" | jq -r '.configExists // false' 2>/dev/null || printf 'false')"
  if [ "${INGRESS_ROOT_MODE}" = "onboarding" ] || [ "${INGRESS_ROOT_MODE}" = "tui" ]; then
    upstream_port="${TERMINAL_UI_PORT}"
  fi

  if [ "${INGRESS_ROOT_MODE}" = "control_ui" ] && [ "${config_exists}" = "true" ]; then
    token_b64="$(printf '%s' "${RUNTIME_STATE_JSON}" | jq -r '.gatewayAuthTokenBase64 // ""' 2>/dev/null || true)"
  fi

  PORT="${upstream_port}" GATEWAY_TOKEN_B64="${token_b64}" node -e "
    const fs = require('fs');
    let template = fs.readFileSync('/nginx.conf.tpl', 'utf8');
    template = template.replaceAll('__UPSTREAM_PORT__', process.env.PORT);
    template = template.replace('__GATEWAY_TOKEN_B64__', process.env.GATEWAY_TOKEN_B64 || '');
    fs.writeFileSync('/etc/nginx/sites-enabled/openclaw.conf', template);
  "
}

start_ingress_proxy() {
  log "starting nginx reverse proxy for Ingress on 8099 -> ${INGRESS_ROOT_MODE}"
  render_ingress_proxy
  rm -f /etc/nginx/sites-enabled/default 2>/dev/null || true
  nginx
  NGINX_STARTED="true"
}

read_homeassistant_control_ui_origins_json() {
  if [ -z "${HA_TOKEN:-}" ]; then
    printf '[]'
    return
  fi

  curl -fsS \
    -H "Authorization: Bearer ${HA_TOKEN}" \
    -H "Content-Type: application/json" \
    "${HA_URL}config" 2>/dev/null \
    | jq -c '
        [
          .internal_url?,
          .external_url?
        ]
        | map(select(type == "string" and length > 0))
        | map(select(test("^https?://")))
        | map(capture("^(?<origin>https?://[^/]+)").origin)
        | unique
      ' 2>/dev/null \
    || printf '[]'
}

run_reconcile() {
  local origins_json="$1"

  node "${RUNTIME_HELPER}" reconcile \
    --config "${OPENCLAW_CONFIG_PATH}" \
    --options /data/options.json \
    --ha-origins "${origins_json}"
}

log_reconcile_result() {
  local result_json="$1"
  local config_changed
  config_changed="$(printf '%s' "${result_json}" | jq -r '.configChanged // false' 2>/dev/null || printf 'false')"
  if [ "${config_changed}" = "true" ]; then
    while IFS= read -r change; do
      [ -n "${change}" ] || continue
      log "config reconcile: ${change}"
    done < <(printf '%s' "${result_json}" | jq -r '.changes[]?' 2>/dev/null || true)
  fi
}

apply_runtime_reconciliation() {
  local origins_json
  local next_state

  origins_json="$(read_homeassistant_control_ui_origins_json || true)"
  if [ -z "${origins_json}" ]; then
    origins_json='[]'
  fi

  next_state="$(run_reconcile "${origins_json}")"
  log_reconcile_result "${next_state}"

  RUNTIME_STATE_JSON="${next_state}"
  CURRENT_RUNTIME_DIGEST="$(printf '%s' "${RUNTIME_STATE_JSON}" | jq -r '.runtimeDigest // ""' 2>/dev/null || true)"
  LOG_FILE="$(printf '%s' "${RUNTIME_STATE_JSON}" | jq -r '.logFile // "/tmp/openclaw/openclaw.log"' 2>/dev/null || printf '/tmp/openclaw/openclaw.log')"
  PORT="$(printf '%s' "${RUNTIME_STATE_JSON}" | jq -r '.runtimeOptions.port // 18789' 2>/dev/null || printf '18789')"
  VERBOSE="$(printf '%s' "${RUNTIME_STATE_JSON}" | jq -r '.runtimeOptions.verbose // false' 2>/dev/null || printf 'false')"
  LOG_FORMAT="$(printf '%s' "${RUNTIME_STATE_JSON}" | jq -r '.runtimeOptions.logFormat // "pretty"' 2>/dev/null || printf 'pretty')"
  LOG_COLOR="$(printf '%s' "${RUNTIME_STATE_JSON}" | jq -r '.runtimeOptions.logColor // false' 2>/dev/null || printf 'false')"
  LOG_FIELDS="$(printf '%s' "${RUNTIME_STATE_JSON}" | jq -r '.runtimeOptions.logFields // ""' 2>/dev/null || true)"
  INGRESS_UI_SELECTION="$(printf '%s' "${RUNTIME_STATE_JSON}" | jq -r '.runtimeOptions.ingressUiMode // "auto"' 2>/dev/null || printf 'auto')"
  BROWSER_MODE="$(printf '%s' "${RUNTIME_STATE_JSON}" | jq -r '.browserMode // "node_host"' 2>/dev/null || printf 'node_host')"
  LOCAL_BROWSER_DETECTED="$(printf '%s' "${RUNTIME_STATE_JSON}" | jq -r '.localBrowserDetected // false' 2>/dev/null || printf 'false')"
  LOCAL_BROWSER_EXECUTABLE_PATH="$(printf '%s' "${RUNTIME_STATE_JSON}" | jq -r '.localBrowserExecutable // ""' 2>/dev/null || true)"
  BROWSER_STATUS_REASON="$(printf '%s' "${RUNTIME_STATE_JSON}" | jq -r '.browserStatusReason // ""' 2>/dev/null || true)"
  if [ -z "${LOCAL_BROWSER_EXECUTABLE_PATH}" ]; then
    LOCAL_BROWSER_EXECUTABLE_PATH="${LOCAL_BROWSER_EXECUTABLE}"
  fi
}

refresh_ingress_surfaces() {
  local config_exists
  local desired_mode

  config_exists="$(printf '%s' "${RUNTIME_STATE_JSON}" | jq -r '.configExists // false' 2>/dev/null || printf 'false')"
  desired_mode="$(resolve_effective_ingress_mode "${INGRESS_UI_SELECTION}" "${config_exists}")"

  if [ "${desired_mode}" = "tui" ]; then
    start_terminal_ui_background "tui"
  else
    stop_terminal_ui_background
  fi

  if [ "${desired_mode}" != "${INGRESS_ROOT_MODE}" ]; then
    INGRESS_ROOT_MODE="${desired_mode}"
    log "effective ingress ui mode=${INGRESS_ROOT_MODE} (selection=${INGRESS_UI_SELECTION})"
  else
    INGRESS_ROOT_MODE="${desired_mode}"
  fi

  render_ingress_proxy
  if [ "${NGINX_STARTED}" = "true" ]; then
    nginx -s reload >/dev/null 2>&1 || true
  fi
}

write_runtime_status() {
  local child_json='null'
  if [ -n "${child_pid}" ]; then
    child_json="${child_pid}"
  fi

  printf '%s' "${RUNTIME_STATE_JSON}" \
    | jq \
      --arg updatedAt "$(date -Iseconds)" \
      --argjson supervisorPid "${SUPERVISOR_PID}" \
      --argjson childPid "${child_json}" \
      --argjson reloadPending "${RELOAD_PENDING}" \
      --argjson localBrowserLaunchValidated "${LOCAL_BROWSER_LAUNCH_VALIDATED}" \
      --argjson browserRuntimeActive "${BROWSER_RUNTIME_ACTIVE}" \
      --arg browserStatusReason "${BROWSER_STATUS_REASON}" \
      --arg lastReloadResult "${LAST_RELOAD_RESULT}" \
      --arg lastReloadReason "${LAST_RELOAD_REASON}" \
      --arg lastReloadError "${LAST_RELOAD_ERROR}" \
      '
      . + {
        updatedAt: $updatedAt,
        supervisorPid: $supervisorPid,
        childPid: $childPid,
        reloadPending: $reloadPending,
        localBrowserLaunchValidated: $localBrowserLaunchValidated,
        browserRuntimeActive: $browserRuntimeActive,
        browserStatusReason: $browserStatusReason,
        lastReloadResult: $lastReloadResult,
        lastReloadReason: $lastReloadReason,
        lastReloadError: $lastReloadError
      }
      ' > "${STATUS_FILE}.tmp"

  mv "${STATUS_FILE}.tmp" "${STATUS_FILE}"
}

compute_gateway_args() {
  local gateway_mode
  ALLOW_UNCONFIGURED=()
  gateway_mode="$(printf '%s' "${RUNTIME_STATE_JSON}" | jq -r '.gatewayMode // ""' 2>/dev/null || true)"

  if [ -z "${gateway_mode}" ]; then
    log "gateway.mode missing; allowing unconfigured gateway start"
    ALLOW_UNCONFIGURED=(--allow-unconfigured)
  fi

  ARGS=(gateway "${ALLOW_UNCONFIGURED[@]}" --port "${PORT}")
  if [ "${VERBOSE}" = "true" ]; then
    ARGS+=(--verbose)
  fi
}

format_log_stream() {
  local format="$1"
  local use_color="$2"
  local fields="$3"

  if [ "${format}" != "pretty" ]; then
    cat
    return
  fi

  if ! command -v jq >/dev/null 2>&1; then
    cat
    return
  fi

  local jq_color="false"
  if [ "${use_color}" = "true" ]; then
    jq_color="true"
  fi

  jq -Rr --argjson use_color "${jq_color}" --arg fields "${fields}" '
    def trim: gsub("^\\s+|\\s+$"; "");
    def parse_name($raw):
      if ($raw|type) == "string" then (try ($raw|fromjson) catch null) else null end;
    def render($v):
      if ($v|type) == "string" then $v
      elif ($v|type) == "number" or ($v|type) == "boolean" then ($v|tostring)
      else ($v|tojson)
      end;
    def numeric_entries($obj):
      ($obj | to_entries | map(select(.key|test("^\\d+$"))) | sort_by(.key|tonumber));
    def string_parts($obj; $name):
      (numeric_entries($obj) | map(.value) | map(select(type=="string")) | map(select(. != $name)));
    def object_meta($obj):
      (numeric_entries($obj) | map(.value) | map(select(type=="object")) | reduce .[] as $o ({}; . * $o));
    def colorize($text; $level):
      if $use_color then
        (if $level == "ERROR" or $level == "FATAL" then "\u001b[31m"+$text+"\u001b[0m"
         elif $level == "WARN" then "\u001b[33m"+$text+"\u001b[0m"
         elif $level == "DEBUG" or $level == "TRACE" then "\u001b[90m"+$text+"\u001b[0m"
         else "\u001b[36m"+$text+"\u001b[0m"
         end)
      else $text end;
    def collect_fields($meta; $fields):
      [ $fields[] | select($meta[.] != null) | "\(. )=\(render($meta[.]))" ];
    def format_line($time; $level; $tag; $message; $fields):
      ([ $time, (colorize($level; $level)), $tag ] | map(select(. != null and . != "")) | join(" "))
      + (if $message != "" then " - " + $message else "" end)
      + (if ($fields|length) > 0 then " | " + ($fields|join(" ")) else "" end);
    . as $line
    | (fromjson? // null) as $obj
    | if $obj == null then $line
      else
        ($obj._meta // {}) as $meta
        | ($meta.name // null) as $name
        | (parse_name($name) // {}) as $name_meta
        | (object_meta($obj) + $name_meta) as $merged
        | ($fields | split(",") | map(trim) | map(select(length>0))) as $field_list
        | (string_parts($obj; $name) | join(" ")) as $message
        | if ($message|length) == 0 then $line
          else
            ($obj.time // $meta.date // "") as $time
            | ($meta.logLevelName // "INFO" | tostring | ascii_upcase) as $level
            | ($name_meta.subsystem // $name_meta.module // "") as $tag
            | format_line($time; $level; $tag; $message; collect_fields($merged; $field_list))
          end
      end
  '
}

start_log_tail() {
  local file="$1"
  (
    while [ ! -f "${file}" ]; do
      sleep 1
    done
    tail -n +1 -F "${file}" | format_log_stream "${LOG_FORMAT}" "${LOG_COLOR}" "${LOG_FIELDS}"
  ) &
  tail_pid=$!
}

wait_for_gateway_ready() {
  local attempt
  for attempt in $(seq 1 90); do
    if curl -fsS "http://127.0.0.1:${PORT}/healthz" >/dev/null 2>&1; then
      return 0
    fi
    sleep 1
  done
  return 1
}

# Ask OpenClaw to release the gateway port before we spawn again (covers reload races where
# the supervised node exited but a worker still held 18789).
request_gateway_listener_teardown() {
  (
    cd "${REPO_DIR}" || exit 0
    timeout 40s node scripts/run-node.mjs gateway stop 2>/dev/null
  ) || true
  sleep 1
}

validate_local_browser_runtime() {
  LOCAL_BROWSER_LAUNCH_VALIDATED="false"
  BROWSER_RUNTIME_ACTIVE="false"

  if [ "${BROWSER_MODE}" != "local" ]; then
    return
  fi

  if [ "${LOCAL_BROWSER_DETECTED}" != "true" ]; then
    BROWSER_STATUS_REASON="local browser mode selected but ${LOCAL_BROWSER_EXECUTABLE_PATH} is unavailable"
    return
  fi

  if ! wait_for_gateway_ready; then
    BROWSER_STATUS_REASON="gateway did not become ready before local browser validation"
    return
  fi

  local validation_log
  validation_log="${STATE_DIR}/browser-validation.log"
  if timeout 90s node scripts/run-node.mjs browser start --browser-profile openclaw >"${validation_log}" 2>&1; then
    LOCAL_BROWSER_LAUNCH_VALIDATED="true"
    BROWSER_RUNTIME_ACTIVE="true"
    BROWSER_STATUS_REASON="local browser launch validated via openclaw browser start"
    log "local browser launch validated using ${LOCAL_BROWSER_EXECUTABLE_PATH}"
  else
    local error_line
    error_line="$(tail -n 20 "${validation_log}" 2>/dev/null | tr '\n' ' ' | sed 's/[[:space:]]\+/ /g; s/^ //; s/ $//')"
    if [ -z "${error_line}" ]; then
      error_line="openclaw browser start failed"
    fi
    BROWSER_STATUS_REASON="local browser launch validation failed: ${error_line}"
    LAST_RELOAD_ERROR="${BROWSER_STATUS_REASON}"
    log "${BROWSER_STATUS_REASON}"
  fi
}

prepare_reload_request() {
  local reason="manual"

  if [ -f "${RELOAD_REASON_FILE}" ]; then
    reason="$(tr -d '\r\n' < "${RELOAD_REASON_FILE}")"
    rm -f "${RELOAD_REASON_FILE}" 2>/dev/null || true
  fi
  if [ -z "${reason}" ]; then
    reason="manual"
  fi

  LAST_RELOAD_REASON="${reason}"
  LAST_RELOAD_RESULT="pending"
  LAST_RELOAD_ERROR=""
  RELOAD_PENDING="true"
  RELOAD_FALLBACK_USED="false"

  apply_runtime_reconciliation || true
  refresh_ingress_surfaces
  write_runtime_status

  if [ -n "${child_pid}" ]; then
    # Signal the full tree: if we only signal the node parent when a child exists, the child
    # can handle USR1 while the parent never gets a clean shutdown signal.
    pkill -USR1 -P "${child_pid}" 2>/dev/null || true
    kill -USR1 "${child_pid}" 2>/dev/null || true
    log "forwarded SIGUSR1 to gateway process tree (reason=${LAST_RELOAD_REASON})"
  else
    log "reload requested with no active gateway child (reason=${LAST_RELOAD_REASON})"
  fi
}

shutdown_child() {
  if [ -n "${watcher_pid}" ]; then
    kill -TERM "${watcher_pid}" 2>/dev/null || true
  fi
  stop_terminal_ui_background
  if [ -n "${tail_pid}" ]; then
    kill -TERM "${tail_pid}" 2>/dev/null || true
  fi
  if [ -n "${child_pid}" ]; then
    kill -TERM "${child_pid}" 2>/dev/null || true
  fi
}

watch_runtime_changes() {
  local last_digest="$1"

  while true; do
    sleep 3
    local origins_json
    local next_state
    local next_digest

    origins_json="$(read_homeassistant_control_ui_origins_json || true)"
    if [ -z "${origins_json}" ]; then
      origins_json='[]'
    fi

    next_state="$(run_reconcile "${origins_json}")" || continue
    next_digest="$(printf '%s' "${next_state}" | jq -r '.runtimeDigest // ""' 2>/dev/null || true)"
    if [ -z "${next_digest}" ]; then
      continue
    fi

    if [ "${next_digest}" != "${last_digest}" ]; then
      printf "config_changed\n" > "${RELOAD_REASON_FILE}"
      kill -USR1 "${SUPERVISOR_PID}" 2>/dev/null || true
      last_digest="${next_digest}"
    fi
  done
}

apply_runtime_reconciliation
refresh_ingress_surfaces
start_ingress_proxy

if [ ! -f "${OPENCLAW_CONFIG_PATH}" ]; then
  log "openclaw.json missing; starting onboarding terminal UI on port ${TERMINAL_UI_PORT}"
  copy_terminal_ui_files
  OPENCLAW_TERMINAL_MODE="onboarding" node "${REPO_DIR}/onboarding.mjs" "${TERMINAL_UI_PORT}"
fi

log "this add-on is the gateway supervisor; upstream openclaw gateway restart does not control the live runtime here"

apply_runtime_reconciliation
refresh_ingress_surfaces
write_runtime_status

trap prepare_reload_request USR1
trap shutdown_child TERM INT

watch_runtime_changes "${CURRENT_RUNTIME_DIGEST}" &
watcher_pid=$!

export OPENCLAW_NO_RESPAWN=1

gateway_supervisor_cycle=0
while true; do
  gateway_supervisor_cycle=$((gateway_supervisor_cycle + 1))
  apply_runtime_reconciliation
  refresh_ingress_surfaces
  compute_gateway_args

  LOCAL_BROWSER_LAUNCH_VALIDATED="$(printf '%s' "${RUNTIME_STATE_JSON}" | jq -r '.localBrowserLaunchValidated // false' 2>/dev/null || printf 'false')"
  BROWSER_RUNTIME_ACTIVE="$(printf '%s' "${RUNTIME_STATE_JSON}" | jq -r '.browserRuntimeActive // false' 2>/dev/null || printf 'false')"

  child_pid=""
  write_runtime_status

  if [ "${gateway_supervisor_cycle}" -gt 1 ]; then
    request_gateway_listener_teardown
  fi

  node scripts/run-node.mjs "${ARGS[@]}" &
  child_pid=$!
  start_log_tail "${LOG_FILE}"
  write_runtime_status

  if wait_for_gateway_ready; then
    if [ "${LAST_RELOAD_RESULT}" = "pending" ]; then
      LAST_RELOAD_RESULT="success"
    fi
  else
    log "gateway health check did not report ready within the expected window"
  fi

  validate_local_browser_runtime
  RELOAD_PENDING="false"
  RELOAD_FALLBACK_USED="false"
  write_runtime_status

  set +e
  wait "${child_pid}"
  status=$?
  set -e

  if [ -n "${tail_pid}" ]; then
    kill -TERM "${tail_pid}" 2>/dev/null || true
    tail_pid=""
  fi

  if [ "${status}" -eq 0 ]; then
    LAST_RELOAD_RESULT="success"
    LAST_RELOAD_ERROR=""
    BROWSER_RUNTIME_ACTIVE="false"
    child_pid=""
    write_runtime_status
    log "gateway exited cleanly"
    break
  fi

  # Linux: SIGUSR1 is signal 10 → wait status 128+10=138. (129 is SIGHUP, not SIGUSR1.)
  if [ "${status}" -eq 138 ] || [ "${status}" -eq 129 ]; then
    child_pid=""
    BROWSER_RUNTIME_ACTIVE="false"
    LAST_RELOAD_RESULT="success"
    LAST_RELOAD_ERROR=""
    write_runtime_status
    log "gateway exited after reload signal (status=${status}); restarting"
    continue
  fi

  if [ "${RELOAD_PENDING}" = "true" ] && [ "${RELOAD_FALLBACK_USED}" = "false" ]; then
    LAST_RELOAD_RESULT="failure"
    LAST_RELOAD_ERROR="gateway exited uncleanly during reload with status=${status}; performing fallback restart"
    RELOAD_FALLBACK_USED="true"
    child_pid=""
    BROWSER_RUNTIME_ACTIVE="false"
    write_runtime_status
    log "${LAST_RELOAD_ERROR}"
    continue
  fi

  LAST_RELOAD_RESULT="failure"
  LAST_RELOAD_REASON="crash"
  LAST_RELOAD_ERROR="gateway exited uncleanly with status=${status}"
  child_pid=""
  BROWSER_RUNTIME_ACTIVE="false"
  write_runtime_status
  log "${LAST_RELOAD_ERROR}; restarting"
done

exit "${status}"
