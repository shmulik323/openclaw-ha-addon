import { spawn } from 'child_process';
import { WebSocketServer } from 'ws';
import { createServer } from 'http';
import { readFileSync, existsSync } from 'fs';
import { join, dirname } from 'path';
import { fileURLToPath } from 'url';

const __dirname = dirname(fileURLToPath(import.meta.url));

const PORT = parseInt(process.argv[2] || '18789', 10);
const STATE_DIR = process.env.OPENCLAW_STATE_DIR || '/config/openclaw/.openclaw';
const CONFIG_PATH = process.env.OPENCLAW_CONFIG_PATH || join(STATE_DIR, 'openclaw.json');
const REPO_DIR = '/config/openclaw/openclaw-src';

console.log('[onboarding] Starting setup server...');
console.log('[onboarding] PORT:', PORT);
console.log('[onboarding] CONFIG_PATH:', CONFIG_PATH);
console.log('[onboarding] REPO_DIR:', REPO_DIR);
console.log('[onboarding] __dirname:', __dirname);

let html;
try {
  html = readFileSync(join(__dirname, 'onboarding.html'), 'utf8');
  console.log('[onboarding] Loaded onboarding.html successfully');
} catch (err) {
  console.error('[onboarding] Failed to read onboarding.html:', err.message);
  process.exit(1);
}

const server = createServer((req, res) => {
  console.log('[onboarding] HTTP request:', req.method, req.url);
  
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
  console.log('[onboarding] WebSocket client connected');
  
  let childProcess = null;

  ws.on('message', (data) => {
    const msg = data.toString();
    console.log('[onboarding] Received message:', msg);
    
    if (msg === 'START_ONBOARD') {
      if (childProcess) {
        ws.send('\x1b[33mOnboarding already in progress...\x1b[0m\r\n');
        return;
      }
      
      ws.send('\x1b[36mStarting openclaw onboard...\x1b[0m\r\n');
      
      childProcess = spawn('node', ['scripts/run-node.mjs', 'onboard', '--install-daemon'], {
        cwd: REPO_DIR,
        env: { ...process.env, FORCE_COLOR: '1' },
        shell: true
      });

      childProcess.stdout.on('data', (data) => {
        ws.send(data.toString());
      });

      childProcess.stderr.on('data', (data) => {
        ws.send(data.toString());
      });

      childProcess.on('close', (code) => {
        ws.send(`\r\n\x1b[${code === 0 ? '32' : '31'}mProcess exited with code ${code}\x1b[0m\r\n`);
        if (code === 0) {
          ws.send('\x1b[32mOnboarding complete! The page will reload shortly...\x1b[0m\r\n');
        }
        childProcess = null;
      });

      childProcess.on('error', (err) => {
        ws.send(`\x1b[31mError: ${err.message}\x1b[0m\r\n`);
        childProcess = null;
      });
    }
  });

  ws.on('close', () => {
    console.log('[onboarding] WebSocket client disconnected');
    if (childProcess) {
      childProcess.kill();
    }
  });
});

server.listen(PORT, '0.0.0.0', () => {
  console.log(`[onboarding] Setup server listening on http://0.0.0.0:${PORT}`);
});

server.on('error', (err) => {
  console.error('[onboarding] Server error:', err.message);
  process.exit(1);
});
