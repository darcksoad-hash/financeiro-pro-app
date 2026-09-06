const { app, BrowserWindow, dialog, shell } = require('electron');
const { spawn } = require('child_process');
const crypto = require('crypto');
const fs = require('fs');
const http = require('http');
const path = require('path');

const port = 3032;
const localAppDir = path.join(process.env.LOCALAPPDATA || app.getPath('userData'), 'FinanceiroPro');
const envPath = path.join(localAppDir, '.env.local');
const dataPath = path.join(localAppDir, 'data.local.json');
let serverProcess = null;
let mainWindow = null;

function projectRoot() {
  return app.isPackaged ? path.join(process.resourcesPath, 'app') : path.join(__dirname, '..');
}

function parseEnvFile(filePath) {
  if (!fs.existsSync(filePath)) return {};
  const env = {};
  for (const line of fs.readFileSync(filePath, 'utf8').split(/\r?\n/)) {
    const trimmed = line.trim();
    if (!trimmed || trimmed.startsWith('#') || !trimmed.includes('=')) continue;
    const [name, ...rest] = trimmed.split('=');
    env[name.trim()] = rest.join('=').trim().replace(/^["']|["']$/g, '');
  }
  return env;
}

function ensureLocalFiles() {
  fs.mkdirSync(localAppDir, { recursive: true });

  if (!fs.existsSync(envPath)) {
    const secret = crypto.randomBytes(32).toString('base64');
    fs.writeFileSync(
      envPath,
      [
        'NODE_ENV=production',
        'ADMIN_USER=admin.financeiro',
        'ADMIN_PASSWORD=FinanceiroLocal@2026',
        `JWT_SECRET=${secret}`
      ].join('\n'),
      'utf8'
    );
  }

  if (!fs.existsSync(dataPath)) {
    fs.writeFileSync(
      dataPath,
      JSON.stringify({ clients: [], loans: [], users: [], history: [] }, null, 2),
      'utf8'
    );
  }
}

function waitForServer(timeoutMs = 30000) {
  const started = Date.now();
  return new Promise((resolve, reject) => {
    const check = () => {
      const req = http.get(`http://127.0.0.1:${port}/`, (res) => {
        res.resume();
        resolve();
      });
      req.on('error', () => {
        if (Date.now() - started > timeoutMs) {
          reject(new Error('O servidor local nao respondeu a tempo.'));
        } else {
          setTimeout(check, 500);
        }
      });
      req.setTimeout(3000, () => {
        req.destroy();
      });
    };
    check();
  });
}

async function startServer() {
  try {
    await waitForServer(1500);
    return;
  } catch {
    // The desktop app owns the local server when one is not already running.
  }

  ensureLocalFiles();

  const root = projectRoot();
  const savedEnv = parseEnvFile(envPath);
  const env = {
    ...process.env,
    ...savedEnv,
    PORT: String(port),
    NODE_ENV: 'production',
    DATABASE_URL: '',
    LOCAL_DATA_FILE: dataPath,
    ELECTRON_RUN_AS_NODE: '1'
  };

  serverProcess = spawn(process.execPath, [path.join(root, 'server.js')], {
    cwd: root,
    env,
    windowsHide: true,
    stdio: 'ignore'
  });

  serverProcess.on('exit', () => {
    serverProcess = null;
  });

  await waitForServer();
}

async function createWindow() {
  await startServer();

  mainWindow = new BrowserWindow({
    width: 1280,
    height: 820,
    minWidth: 980,
    minHeight: 680,
    title: 'Financeiro Pro',
    icon: path.join(projectRoot(), 'assets', 'financeiro-pro-icon.png'),
    backgroundColor: '#f8fafc',
    autoHideMenuBar: true,
    webPreferences: {
      contextIsolation: true,
      nodeIntegration: false
    }
  });

  mainWindow.webContents.setWindowOpenHandler(({ url }) => {
    shell.openExternal(url);
    return { action: 'deny' };
  });

  mainWindow.webContents.on('will-navigate', (event, url) => {
    if (!url.startsWith(`http://127.0.0.1:${port}/`)) {
      event.preventDefault();
      shell.openExternal(url);
    }
  });

  await mainWindow.loadURL(`http://127.0.0.1:${port}/`);
}

app.whenReady().then(createWindow).catch((error) => {
  dialog.showErrorBox('Financeiro Pro', error.message);
  app.quit();
});

app.on('window-all-closed', () => {
  app.quit();
});

app.on('before-quit', () => {
  if (serverProcess) {
    serverProcess.kill();
    serverProcess = null;
  }
});
