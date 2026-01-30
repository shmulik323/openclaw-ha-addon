import * as pty from '@lydell/node-pty';
import { WebSocketServer } from 'ws';
import { createServer } from 'http';
import { readFileSync, existsSync } from 'fs';
import { join } from 'path';

const PORT = parseInt(process.argv[2] || '18789', 10);
const STATE_DIR = process.env.OPENCLAW_STATE_DIR || '/config/openclaw/.openclaw';
const CONFIG_PATH = process.env.OPENCLAW_CONFIG_PATH || join(STATE_DIR, 'openclaw.json');
const REPO_DIR = '/config/openclaw/openclaw-src';

let html;
try {
  html = readFileSync(join(import.meta.dirname, 'onboarding.html'), 'utf8');
} catch (err) {
  console.error('[onboarding] Failed to read onboarding.html:', err.message);
  process.exit(1);
}

const server = createServer((req, res) => {
  if (req.url === '/health') {
    res.writeHead(200, { 'Content-Type': 'application/json' });
    res.end(JSON.stringify({ status: existsSync(CONFIG_PATH) ? 'ready' : 'setup' }));
    return;
  }
  if (req.url === '/shutdown') {
    res.writeHead(200, { 'Content-Type': 'application/json' });
    res.end(JSON.stringify({ status: 'ok' }));
    console.log('[onboarding] shutdown requested');
    setTimeout(() => process.exit(0), 500);
    return;
  }
  res.writeHead(200, { 'Content-Type': 'text/html' });
  res.end(html);
});

const wss = new WebSocketServer({ server });

wss.on('connection', (ws) => {
  console.log('[onboarding] client connected');

  let ptyProcess;
  try {
    ptyProcess = pty.spawn('bash', [], {
      name: 'xterm-color',
      cols: 80,
      rows: 24,
      cwd: REPO_DIR,
      env: process.env
    });
  } catch (err) {
    console.error('[onboarding] Failed to spawn PTY:', err.message);
    ws.send(`\x1b[31mError: Failed to spawn terminal: ${err.message}\x1b[0m\r\n`);
    ws.close();
    return;
  }

  ws.on('message', (data) => {
    const msg = data.toString();
    if (msg === 'START_ONBOARD') {
      ptyProcess.write('node scripts/run-node.mjs onboard --install-daemon\n');
    } else {
      ptyProcess.write(msg);
    }
  });

  ptyProcess.onData((data) => {
    ws.send(data);
  });

  ws.on('close', () => {
    console.log('[onboarding] client disconnected');
    ptyProcess.kill();
  });
});

server.listen(PORT, '0.0.0.0', () => {
  console.log(`[onboarding] setup server listening on port ${PORT}`);
});
