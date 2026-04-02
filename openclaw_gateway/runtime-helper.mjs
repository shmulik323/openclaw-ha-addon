import { createHash, randomBytes } from 'node:crypto';
import { existsSync, readFileSync, writeFileSync } from 'node:fs';
import { createRequire } from 'node:module';

const requireFromCwd = createRequire(`${process.cwd()}/`);

let JSON5;
try {
  JSON5 = requireFromCwd('json5');
} catch {
  JSON5 = { parse: JSON.parse };
}

const DEFAULT_PORT = 18789;
const DEFAULT_LOG_FILE = '/tmp/openclaw/openclaw.log';
const DEFAULT_INGRESS_UI_MODE = 'auto';
const DEFAULT_BROWSER_RUNTIME_MODE = 'node_host';
const DEFAULT_REMOTE_CDP_PROFILE = 'ha_remote';
const LOCAL_BROWSER_EXECUTABLE = '/usr/bin/chromium';
const DEFAULT_TRUSTED_PROXIES = ['127.0.0.1', '172.30.32.0/24'];

function parseArgs(argv) {
  const [command, ...rest] = argv;
  const flags = {};

  for (let i = 0; i < rest.length; i += 1) {
    const token = rest[i];
    if (!token.startsWith('--')) {
      continue;
    }
    const key = token.slice(2);
    const next = rest[i + 1];
    if (next == null || next.startsWith('--')) {
      flags[key] = true;
      continue;
    }
    flags[key] = next;
    i += 1;
  }

  return { command, flags };
}

function safeParseJson(text, fallback) {
  try {
    return JSON.parse(text);
  } catch {
    return fallback;
  }
}

function readJson5File(filePath, fallback) {
  if (!filePath || !existsSync(filePath)) {
    return fallback;
  }
  try {
    return JSON5.parse(readFileSync(filePath, 'utf8'));
  } catch {
    return fallback;
  }
}

function writeJsonFile(filePath, value) {
  writeFileSync(filePath, `${JSON.stringify(value, null, 2)}\n`);
}

function ensureObject(value) {
  return value && typeof value === 'object' && !Array.isArray(value) ? value : {};
}

function ensureString(value, fallback = '') {
  if (typeof value !== 'string') {
    return fallback;
  }
  const trimmed = value.trim();
  return trimmed.length > 0 ? trimmed : fallback;
}

function ensureUniqueStrings(values) {
  const result = [];
  for (const value of values) {
    if (typeof value !== 'string') {
      continue;
    }
    const trimmed = value.trim();
    if (!trimmed || result.includes(trimmed)) {
      continue;
    }
    result.push(trimmed);
  }
  return result;
}

function normalizeIngressUiMode(value) {
  const raw = ensureString(value, DEFAULT_INGRESS_UI_MODE).toLowerCase();
  if (raw === 'controlui' || raw === 'control-ui' || raw === 'control_ui') {
    return 'control_ui';
  }
  if (raw === 'tui') {
    return 'tui';
  }
  return DEFAULT_INGRESS_UI_MODE;
}

function normalizeBrowserRuntimeMode(value) {
  const raw = ensureString(value, DEFAULT_BROWSER_RUNTIME_MODE).toLowerCase();
  if (raw === 'local') {
    return 'local';
  }
  if (raw === 'remote_cdp' || raw === 'remote-cdp' || raw === 'remotecdp') {
    return 'remote_cdp';
  }
  if (raw === 'off') {
    return 'off';
  }
  return 'node_host';
}

function normalizeBoolean(value, fallback = false) {
  return typeof value === 'boolean' ? value : fallback;
}

function normalizeInteger(value, fallback) {
  if (typeof value === 'number' && Number.isInteger(value) && value > 0) {
    return value;
  }
  if (typeof value === 'string' && value.trim()) {
    const parsed = Number.parseInt(value.trim(), 10);
    if (Number.isInteger(parsed) && parsed > 0) {
      return parsed;
    }
  }
  return fallback;
}

function stableClone(value) {
  if (Array.isArray(value)) {
    return value.map((entry) => stableClone(entry));
  }
  if (value && typeof value === 'object') {
    return Object.keys(value)
      .sort()
      .reduce((acc, key) => {
        acc[key] = stableClone(value[key]);
        return acc;
      }, {});
  }
  return value;
}

function stableStringify(value) {
  return JSON.stringify(stableClone(value));
}

function sha256(value) {
  return createHash('sha256').update(value).digest('hex');
}

function readRuntimeOptions(optionsPath) {
  const options = readJson5File(optionsPath, {});

  return {
    port: normalizeInteger(options.port, DEFAULT_PORT),
    verbose: normalizeBoolean(options.verbose, false),
    logFormat: ensureString(options.log_format, 'pretty'),
    logColor: normalizeBoolean(options.log_color, false),
    logFields: ensureString(options.log_fields, ''),
    ingressUiMode: normalizeIngressUiMode(options.ingress_ui_mode),
    browserRuntimeMode: normalizeBrowserRuntimeMode(options.browser_runtime_mode),
    browserRemoteCdpUrl: ensureString(options.browser_remote_cdp_url, ''),
    browserRemoteCdpProfile: ensureString(options.browser_remote_cdp_profile, DEFAULT_REMOTE_CDP_PROFILE),
  };
}

function hasOwnProperty(object, key) {
  return Object.prototype.hasOwnProperty.call(object, key);
}

function clearPropertyIfValue(object, key, expectedValue, recordChange, label) {
  if (!hasOwnProperty(object, key)) {
    return;
  }
  if (object[key] !== expectedValue) {
    return;
  }
  delete object[key];
  recordChange(label);
}

function reconcileConfig(configPath, optionsPath, haOriginsJson) {
  const runtimeOptions = readRuntimeOptions(optionsPath);
  const configExists = existsSync(configPath);
  const data = configExists ? readJson5File(configPath, {}) : {};
  const changes = [];
  let configChanged = false;

  const recordChange = (label) => {
    if (!changes.includes(label)) {
      changes.push(label);
    }
    configChanged = true;
  };

  if (configExists) {
    const gateway = ensureObject(data.gateway);
    const logging = ensureObject(data.logging);
    const controlUi = ensureObject(gateway.controlUi);
    const gatewayAuth = ensureObject(gateway.auth);
    const gatewayNodes = ensureObject(gateway.nodes);
    const browserNode = ensureObject(gatewayNodes.browser);
    const browser = ensureObject(data.browser);
    const browserProfiles = ensureObject(browser.profiles);

    if (!ensureString(gateway.mode, '')) {
      gateway.mode = 'local';
      recordChange('gateway.mode=local');
    }

    if (!ensureString(logging.file, '')) {
      logging.file = DEFAULT_LOG_FILE;
      recordChange(`logging.file=${DEFAULT_LOG_FILE}`);
    }

    if (!ensureString(gatewayAuth.mode, '')) {
      gatewayAuth.mode = 'token';
      recordChange('gateway.auth.mode=token');
    }

    if (!ensureString(gatewayAuth.token, '')) {
      gatewayAuth.token = randomBytes(24).toString('hex');
      recordChange('gateway.auth.token generated');
    }

    if (controlUi.allowInsecureAuth !== true) {
      controlUi.allowInsecureAuth = true;
      recordChange('gateway.controlUi.allowInsecureAuth=true');
    }

    if (controlUi.dangerouslyDisableDeviceAuth !== true) {
      controlUi.dangerouslyDisableDeviceAuth = true;
      recordChange('gateway.controlUi.dangerouslyDisableDeviceAuth=true');
    }

    if (controlUi.dangerouslyAllowHostHeaderOriginFallback !== true) {
      controlUi.dangerouslyAllowHostHeaderOriginFallback = true;
      recordChange('gateway.controlUi.dangerouslyAllowHostHeaderOriginFallback=true');
    }

    const currentTrustedProxies = Array.isArray(gateway.trustedProxies) ? gateway.trustedProxies : [];
    const mergedTrustedProxies = ensureUniqueStrings([...currentTrustedProxies, ...DEFAULT_TRUSTED_PROXIES]);
    if (stableStringify(currentTrustedProxies) !== stableStringify(mergedTrustedProxies)) {
      gateway.trustedProxies = mergedTrustedProxies;
      recordChange('gateway.trustedProxies merged');
    }

    const requestedOrigins = Array.isArray(haOriginsJson) ? haOriginsJson : [];
    const currentAllowedOrigins = Array.isArray(controlUi.allowedOrigins) ? controlUi.allowedOrigins : [];
    const mergedAllowedOrigins = ensureUniqueStrings([...currentAllowedOrigins, ...requestedOrigins]);
    if (stableStringify(currentAllowedOrigins) !== stableStringify(mergedAllowedOrigins)) {
      controlUi.allowedOrigins = mergedAllowedOrigins;
      recordChange('gateway.controlUi.allowedOrigins merged');
    }

    if (runtimeOptions.browserRuntimeMode === 'off') {
      if (browser.enabled !== false) {
        browser.enabled = false;
        recordChange('browser.enabled=false');
      }
      clearPropertyIfValue(browser, 'executablePath', LOCAL_BROWSER_EXECUTABLE, recordChange, 'browser.executablePath cleared');
      clearPropertyIfValue(browser, 'headless', true, recordChange, 'browser.headless cleared');
      clearPropertyIfValue(browser, 'noSandbox', true, recordChange, 'browser.noSandbox cleared');
    } else {
      if (browser.enabled !== true) {
        browser.enabled = true;
        recordChange('browser.enabled=true');
      }
    }

    if (runtimeOptions.browserRuntimeMode === 'node_host') {
      if (!ensureString(browserNode.mode, '')) {
        browserNode.mode = 'auto';
        recordChange('gateway.nodes.browser.mode=auto');
      }
      clearPropertyIfValue(browser, 'executablePath', LOCAL_BROWSER_EXECUTABLE, recordChange, 'browser.executablePath cleared');
      clearPropertyIfValue(browser, 'headless', true, recordChange, 'browser.headless cleared');
      clearPropertyIfValue(browser, 'noSandbox', true, recordChange, 'browser.noSandbox cleared');
    }

    if (runtimeOptions.browserRuntimeMode === 'local') {
      if (browser.defaultProfile !== 'openclaw') {
        browser.defaultProfile = 'openclaw';
        recordChange('browser.defaultProfile=openclaw');
      }
      if (browser.executablePath !== LOCAL_BROWSER_EXECUTABLE) {
        browser.executablePath = LOCAL_BROWSER_EXECUTABLE;
        recordChange(`browser.executablePath=${LOCAL_BROWSER_EXECUTABLE}`);
      }
      if (browser.headless !== true) {
        browser.headless = true;
        recordChange('browser.headless=true');
      }
      if (browser.noSandbox !== true) {
        browser.noSandbox = true;
        recordChange('browser.noSandbox=true');
      }
    }

    if (runtimeOptions.browserRuntimeMode === 'remote_cdp') {
      const profileName = runtimeOptions.browserRemoteCdpProfile || DEFAULT_REMOTE_CDP_PROFILE;
      const currentProfile = ensureObject(browserProfiles[profileName]);
      clearPropertyIfValue(browser, 'executablePath', LOCAL_BROWSER_EXECUTABLE, recordChange, 'browser.executablePath cleared');
      clearPropertyIfValue(browser, 'headless', true, recordChange, 'browser.headless cleared');
      clearPropertyIfValue(browser, 'noSandbox', true, recordChange, 'browser.noSandbox cleared');
      if (browser.defaultProfile !== profileName) {
        browser.defaultProfile = profileName;
        recordChange(`browser.defaultProfile=${profileName}`);
      }
      if (runtimeOptions.browserRemoteCdpUrl) {
        if (currentProfile.cdpUrl !== runtimeOptions.browserRemoteCdpUrl) {
          currentProfile.cdpUrl = runtimeOptions.browserRemoteCdpUrl;
          browserProfiles[profileName] = currentProfile;
          recordChange(`browser.profiles.${profileName}.cdpUrl updated`);
        }
      }
    }

    gateway.auth = gatewayAuth;
    gateway.controlUi = controlUi;
    gateway.nodes = gatewayNodes;
    data.gateway = gateway;
    data.logging = logging;
    browser.profiles = browserProfiles;
    data.browser = browser;

    if (configChanged) {
      writeJsonFile(configPath, data);
    }
  }

  const localBrowserDetected = existsSync(LOCAL_BROWSER_EXECUTABLE);
  const browserMode = runtimeOptions.browserRuntimeMode;
  const browserConfigured = browserMode !== 'off' && configExists;
  const localBrowserSupported = true;

  let browserStatusReason = 'browser runtime disabled by add-on option';
  if (!configExists) {
    browserStatusReason = 'OpenClaw config does not exist yet; browser runtime is not configured';
  } else if (browserMode === 'node_host') {
    browserStatusReason = 'configured for node host mode; local browser is not expected';
  } else if (browserMode === 'remote_cdp') {
    browserStatusReason = runtimeOptions.browserRemoteCdpUrl
      ? 'configured for remote CDP endpoint; waiting for runtime connection'
      : 'remote_cdp mode selected but browser_remote_cdp_url is empty';
  } else if (browserMode === 'local') {
    browserStatusReason = localBrowserDetected
      ? 'local browser configured; launch validation pending'
      : `local browser mode selected but ${LOCAL_BROWSER_EXECUTABLE} is unavailable`;
  }

  const optionsDigest = sha256(
    stableStringify({
      port: runtimeOptions.port,
      verbose: runtimeOptions.verbose,
      logFormat: runtimeOptions.logFormat,
      logColor: runtimeOptions.logColor,
      logFields: runtimeOptions.logFields,
      ingressUiMode: runtimeOptions.ingressUiMode,
      browserRuntimeMode: runtimeOptions.browserRuntimeMode,
      browserRemoteCdpUrl: runtimeOptions.browserRemoteCdpUrl,
      browserRemoteCdpProfile: runtimeOptions.browserRemoteCdpProfile,
    }),
  );
  const configDigest = sha256(configExists ? stableStringify(data) : 'missing');
  const runtimeDigest = sha256(stableStringify({ optionsDigest, configDigest }));
  const gateway = configExists ? ensureObject(data.gateway) : {};
  const logging = configExists ? ensureObject(data.logging) : {};
  const gatewayAuth = ensureObject(gateway.auth);

  return {
    configExists,
    configChanged,
    changes,
    optionsDigest,
    configDigest,
    runtimeDigest,
    logFile: ensureString(logging.file, DEFAULT_LOG_FILE),
    gatewayMode: ensureString(gateway.mode, ''),
    gatewayAuthTokenBase64: Buffer.from(ensureString(gatewayAuth.token, ''), 'utf8').toString('base64'),
    browserConfigured,
    browserMode,
    localBrowserSupported,
    localBrowserDetected,
    localBrowserLaunchValidated: false,
    localBrowserExecutable: LOCAL_BROWSER_EXECUTABLE,
    browserRuntimeActive: false,
    browserStatusReason,
    runtimeOptions,
  };
}

function main() {
  const { command, flags } = parseArgs(process.argv.slice(2));

  if (command === 'reconcile') {
    const configPath = ensureString(flags.config, '');
    const optionsPath = ensureString(flags.options, '');
    const haOrigins = safeParseJson(ensureString(flags['ha-origins'], '[]'), []);
    const result = reconcileConfig(configPath, optionsPath, haOrigins);
    process.stdout.write(JSON.stringify(result));
    return;
  }

  throw new Error(`Unknown command: ${command || '<missing>'}`);
}

main();
