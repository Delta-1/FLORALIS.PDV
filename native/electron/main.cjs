const { app, BrowserWindow, shell } = require('electron');
const { createServer } = require('node:http');
const { readFile, stat } = require('node:fs/promises');
const { extname, join, normalize, sep } = require('node:path');

const APP_PORT = 41731;
const APP_ORIGIN = `http://127.0.0.1:${APP_PORT}`;
const WEB_ROOT = join(__dirname, '..', '..', 'dist-native');
const MIME = Object.freeze({
  '.css': 'text/css; charset=utf-8',
  '.html': 'text/html; charset=utf-8',
  '.ico': 'image/x-icon',
  '.js': 'text/javascript; charset=utf-8',
  '.json': 'application/json; charset=utf-8',
  '.png': 'image/png',
  '.svg': 'image/svg+xml; charset=utf-8',
  '.webmanifest': 'application/manifest+json; charset=utf-8',
  '.webp': 'image/webp'
});

let mainWindow;
let localServer;

function safeFilePath(requestUrl) {
  const pathname = decodeURIComponent(new URL(requestUrl, APP_ORIGIN).pathname);
  const relative = pathname === '/' ? 'index.html' : pathname.replace(/^\/+/, '');
  const resolved = normalize(join(WEB_ROOT, relative));
  if (resolved !== WEB_ROOT && !resolved.startsWith(`${WEB_ROOT}${sep}`)) return null;
  return resolved;
}

async function serve(request, response) {
  const filePath = safeFilePath(request.url || '/');
  if (!filePath) {
    response.writeHead(403).end('Forbidden');
    return;
  }
  try {
    if (!(await stat(filePath)).isFile()) throw new Error('Not a file');
    const body = await readFile(filePath);
    response.writeHead(200, {
      'Cache-Control': 'no-cache',
      'Content-Type': MIME[extname(filePath).toLowerCase()] || 'application/octet-stream',
      'X-Content-Type-Options': 'nosniff'
    });
    response.end(body);
  } catch {
    response.writeHead(404, { 'Content-Type': 'text/plain; charset=utf-8' });
    response.end('Arquivo não encontrado');
  }
}

function startServer() {
  return new Promise((resolve, reject) => {
    localServer = createServer((request, response) => void serve(request, response));
    localServer.once('error', reject);
    localServer.listen(APP_PORT, '127.0.0.1', resolve);
  });
}

function isInternal(url) {
  try { return new URL(url).origin === APP_ORIGIN; } catch { return false; }
}

function openExternal(url) {
  try {
    const parsed = new URL(url);
    if (parsed.protocol === 'https:' || parsed.protocol === 'mailto:') void shell.openExternal(parsed.href);
  } catch {}
}

function createWindow() {
  mainWindow = new BrowserWindow({
    width: 1440,
    height: 900,
    minWidth: 980,
    minHeight: 680,
    show: false,
    autoHideMenuBar: true,
    backgroundColor: '#0b0c0f',
    icon: join(__dirname, '..', '..', 'dist-native', 'assets', 'icon-512.png'),
    webPreferences: {
      preload: join(__dirname, 'preload.cjs'),
      contextIsolation: true,
      nodeIntegration: false,
      sandbox: true,
      webSecurity: true
    }
  });

  mainWindow.webContents.setWindowOpenHandler(({ url }) => {
    if (isInternal(url)) return { action: 'allow' };
    openExternal(url);
    return { action: 'deny' };
  });
  mainWindow.webContents.on('will-navigate', (event, url) => {
    if (isInternal(url)) return;
    event.preventDefault();
    openExternal(url);
  });
  mainWindow.once('ready-to-show', () => mainWindow.show());
  void mainWindow.loadURL(`${APP_ORIGIN}/index.html?native=desktop`);
}

const hasLock = app.requestSingleInstanceLock();
if (!hasLock) app.quit();
else {
  app.on('second-instance', () => {
    if (!mainWindow) return;
    if (mainWindow.isMinimized()) mainWindow.restore();
    mainWindow.focus();
  });
  app.whenReady().then(async () => {
    await startServer();
    createWindow();
  }).catch(error => {
    console.error(error);
    app.quit();
  });
  app.on('window-all-closed', () => app.quit());
  app.on('before-quit', () => localServer?.close());
}
