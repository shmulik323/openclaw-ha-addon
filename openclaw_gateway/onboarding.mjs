import { spawn } from 'child_process';
import { WebSocketServer } from 'ws';
import { createServer } from 'http';
import { readFileSync, existsSync } from 'fs';
import { join, dirname } from 'path';
import { fileURLToPath } from 'url';

const __dirname = dirname(fileURLToPath(import.meta.url));

const PORT = parseInt(process.argv[2] || '18080', 10);
const TERMINAL_MODE = String(process.env.OPENCLAW_TERMINAL_MODE || 'onboarding')
  .trim()
  .toLowerCase();
const STATE_DIR = process.env.OPENCLAW_STATE_DIR || '/config/openclaw/.openclaw';
const CONFIG_PATH = process.env.OPENCLAW_CONFIG_PATH || join(STATE_DIR, 'openclaw.json');
const REPO_DIR = '/config/openclaw/openclaw-src';
const CONTROL_PREFIX = '\u0000';

const MODE_CONFIG = {
  onboarding: {
    logPrefix: 'onboarding',
    title: 'OpenClaw Onboarding',
    description:
      'Use the full-screen terminal below to complete first-run setup. Once onboarding starts, the wizard takes over the whole terminal surface.',
    tips: [
      'Click inside the terminal if keyboard focus is lost',
      'Use arrow keys, Tab, and Enter to move through prompts',
      'The terminal will use almost the full ingress page',
    ],
    startLabel: 'Start Onboarding',
    readyLine: 'Press the button to run openclaw onboard --install-daemon',
    runningStatus: 'Running onboarding...',
    connectLine: 'Connected to setup server.',
    startBanner: 'Starting openclaw onboard...',
    successLine: 'Onboarding complete! The page will reload shortly...',
    autoStart: false,
    command: 'node scripts/run-node.mjs onboard --install-daemon',
  },
  tui: {
    logPrefix: 'tui',
    title: 'OpenClaw TUI',
    description:
      'Use the terminal below to run the OpenClaw terminal UI through Home Assistant ingress. This keeps the interaction inside the add-on panel instead of relying on the embedded Control UI.',
    tips: [
      'Click inside the terminal if keyboard focus is lost',
      'Use arrow keys, Tab, and Enter inside the terminal UI',
      'Restart the terminal session from the button if it exits',
    ],
    startLabel: 'Start TUI',
    readyLine: 'The terminal UI starts automatically. Use the button if you need to restart it.',
    runningStatus: 'Running terminal UI...',
    connectLine: 'Connected to terminal server.',
    startBanner: 'Starting openclaw tui...',
    successLine: '',
    autoStart: true,
    command: 'node scripts/run-node.mjs tui',
  },
};

const terminalConfig = MODE_CONFIG[TERMINAL_MODE] || MODE_CONFIG.onboarding;

function normalizeTerminalSize(inputCols, inputRows) {
  const cols = Math.max(80, Math.min(240, Number.parseInt(inputCols || '160', 10) || 160));
  const rows = Math.max(24, Math.min(80, Number.parseInt(inputRows || '48', 10) || 48));
  return { cols, rows };
}

function buildTerminalCommand(cols, rows) {
  return `sh -lc 'export COLUMNS=${cols} LINES=${rows}; stty cols ${cols} rows ${rows}; exec ${terminalConfig.command}'`;
}

function log(...args) {
  console.log(`[${terminalConfig.logPrefix}]`, ...args);
}

function error(...args) {
  console.error(`[${terminalConfig.logPrefix}]`, ...args);
}

function sendControl(ws, payload) {
  ws.send(`${CONTROL_PREFIX}${JSON.stringify(payload)}`);
}

log('Starting terminal server...');
log('MODE:', TERMINAL_MODE);
log('PORT:', PORT);
log('CONFIG_PATH:', CONFIG_PATH);
log('REPO_DIR:', REPO_DIR);
log('__dirname:', __dirname);

let html;
try {
  html = readFileSync(join(__dirname, 'onboarding.html'), 'utf8');
  html = html.replace(
    '__OPENCLAW_TERMINAL_CONFIG__',
    JSON.stringify({
      mode: TERMINAL_MODE,
      title: terminalConfig.title,
      description: terminalConfig.description,
      tips: terminalConfig.tips,
      startLabel: terminalConfig.startLabel,
      readyLine: terminalConfig.readyLine,
      runningStatus: terminalConfig.runningStatus,
      connectLine: terminalConfig.connectLine,
      startBanner: terminalConfig.startBanner,
      successLine: terminalConfig.successLine,
      autoStart: terminalConfig.autoStart,
    }),
  );
  log('Loaded onboarding.html successfully');
} catch (err) {
  error('Failed to read onboarding.html:', err.message);
  process.exit(1);
}

const server = createServer((req, res) => {
  log('HTTP request:', req.method, req.url);

  if (TERMINAL_MODE === 'onboarding' && req.url === '/health') {
    res.writeHead(200, { 'Content-Type': 'application/json' });
    res.end(JSON.stringify({ status: existsSync(CONFIG_PATH) ? 'ready' : 'setup' }));
    return;
  }
  if (TERMINAL_MODE === 'onboarding' && req.url === '/shutdown') {
    res.writeHead(200, { 'Content-Type': 'application/json' });
    res.end(JSON.stringify({ status: 'ok' }));
    log('shutdown requested');
    setTimeout(() => process.exit(0), 500);
    return;
  }

  res.writeHead(200, { 'Content-Type': 'text/html' });
  res.end(html);
});

const wss = new WebSocketServer({ server });

wss.on('connection', (ws) => {
  log('WebSocket client connected');

  let childProcess = null;
  let terminalSize = normalizeTerminalSize();

  ws.on('message', (data) => {
    const msg = data.toString();
    let control = null;
    try {
      control = JSON.parse(msg);
    } catch {
      control = null;
    }

    if (control?.type === 'resize') {
      terminalSize = normalizeTerminalSize(control.cols, control.rows);
      return;
    }

    if (control?.type === 'start' || msg === 'START_ONBOARD') {
      if (childProcess) {
        ws.send('\x1b[33mTerminal session already in progress...\x1b[0m\r\n');
        return;
      }

      terminalSize = normalizeTerminalSize(control?.cols, control?.rows);
      log('Starting terminal command with size:', terminalSize);

      ws.send(`\x1b[36m${terminalConfig.startBanner}\x1b[0m\r\n`);
      sendControl(ws, { type: 'process_state', running: true });

      childProcess = spawn(
        'script',
        ['-qefc', buildTerminalCommand(terminalSize.cols, terminalSize.rows), '/dev/null'],
        {
          cwd: REPO_DIR,
          env: {
            ...process.env,
            FORCE_COLOR: '1',
            TERM: process.env.TERM || 'xterm-256color',
            COLORTERM: process.env.COLORTERM || 'truecolor',
          },
        },
      );

      childProcess.stdout.on('data', (chunk) => {
        ws.send(chunk.toString());
      });

      childProcess.stderr.on('data', (chunk) => {
        ws.send(chunk.toString());
      });

      childProcess.on('close', (code) => {
        ws.send(`\r\n\x1b[${code === 0 ? '32' : '31'}mProcess exited with code ${code}\x1b[0m\r\n`);
        if (TERMINAL_MODE === 'onboarding' && code === 0 && terminalConfig.successLine) {
          ws.send(`\x1b[32m${terminalConfig.successLine}\x1b[0m\r\n`);
        }
        sendControl(ws, { type: 'process_state', running: false, code });
        childProcess = null;
      });

      childProcess.on('error', (err) => {
        ws.send(`\x1b[31mError: ${err.message}\x1b[0m\r\n`);
        sendControl(ws, { type: 'process_state', running: false, error: err.message });
        childProcess = null;
      });
      return;
    }

    if (childProcess?.stdin?.writable) {
      childProcess.stdin.write(data);
    }
  });

  ws.on('close', () => {
    log('WebSocket client disconnected');
    if (childProcess) {
      childProcess.kill();
    }
  });
});

server.listen(PORT, '0.0.0.0', () => {
  log(`Terminal server listening on http://0.0.0.0:${PORT}`);
});

server.on('error', (err) => {
  error('Server error:', err.message);
  process.exit(1);
});
