# macOS Electron Pet Recipe

Use this when building the pet shell on macOS. The goal is a frameless, transparent,
always-on-top window that contains only the character and can be clicked, dragged,
and right-clicked.

## BrowserWindow

```js
const mainWindow = new BrowserWindow({
  width: WINDOW_WIDTH,
  height: WINDOW_HEIGHT,
  transparent: true,
  frame: false,
  hasShadow: false,
  alwaysOnTop: true,
  resizable: false,
  maximizable: false,
  minimizable: false,
  fullscreenable: false,
  skipTaskbar: true,
  show: false,
  acceptFirstMouse: true,
  backgroundColor: '#00000000',
  webPreferences: {
    preload: path.join(__dirname, 'preload.js'),
    contextIsolation: true,
    nodeIntegration: false,
    sandbox: true,
    backgroundThrottling: false,
    paintWhenInitiallyHidden: true,
  },
});

// screen-saver 级别才能盖住全屏 App；visibleOnFullScreen 才能出现在全屏 Space。
mainWindow.setAlwaysOnTop(true, 'screen-saver');
mainWindow.setVisibleOnAllWorkspaces(true, {
  visibleOnFullScreen: true,
  skipTransformProcessType: true,
});
```

Show the window with `showInactive()` on `ready-to-show` so it does not steal focus.

## Manual Drag Over IPC

`-webkit-app-region: drag` looks tempting but makes the system own the pointer events,
which swallows `contextmenu` and leaves right-click dead. Instead:

Renderer (`pet.js`):

```js
const stage = document.querySelector('.pet-stage');
let dragging = false, dragMoved = false, dragOrigin = { x: 0, y: 0 };

stage.addEventListener('mousedown', (event) => {
  if (event.button !== 0) return;
  dragging = true; dragMoved = false;
  dragOrigin = { x: event.screenX, y: event.screenY };
  window.petAPI.dragStart(event.screenX, event.screenY);
  event.preventDefault();
});

window.addEventListener('mousemove', (event) => {
  if (!dragging) return;
  if (Math.abs(event.screenX - dragOrigin.x) > 3 || Math.abs(event.screenY - dragOrigin.y) > 3) {
    dragMoved = true;
  }
  if (dragMoved) window.petAPI.dragMove(event.screenX, event.screenY);
});

window.addEventListener('mouseup', () => {
  if (!dragging) return;
  dragging = false;
  window.petAPI.dragEnd();
  if (!dragMoved) handleTap(); // 3px 内抬起算点击
});
```

Main (`main.js`):

```js
let dragState = null;
ipcMain.on('pet:drag-start', (_e, pos) => {
  const [wx, wy] = mainWindow.getPosition();
  dragState = { cursorX: pos.x, cursorY: pos.y, winX: wx, winY: wy };
});
ipcMain.on('pet:drag-move', (_e, pos) => {
  if (!dragState) return;
  mainWindow.setPosition(
    Math.round(dragState.winX + (pos.x - dragState.cursorX)),
    Math.round(dragState.winY + (pos.y - dragState.cursorY)),
    false,
  );
});
```

`preload.js` exposes only a whitelist through `contextBridge.exposeInMainWorld`:

```js
const { contextBridge, ipcRenderer } = require('electron');
contextBridge.exposeInMainWorld('petAPI', Object.freeze({
  dragStart: (x, y) => ipcRenderer.send('pet:drag-start', { x, y }),
  dragMove: (x, y) => ipcRenderer.send('pet:drag-move', { x, y }),
  dragEnd: () => ipcRenderer.send('pet:drag-end'),
  showMenu: () => ipcRenderer.send('pet:show-menu'),
}));
```

## Right-Click Menu

Drive it from the renderer's `contextmenu` event so it works on transparent windows:

```js
window.addEventListener('contextmenu', (event) => {
  event.preventDefault();
  window.petAPI.showMenu();
});
```

Main process builds the menu with `Menu.buildFromTemplate(template).popup({ window: mainWindow })`.
Offer at least "窗口置顶" (checkbox toggling always-on-top and visible-on-all-workspaces)
and "退出" (`app.quit()`).

## Position Persistence

Store `{ x, y, height }` in `app.getPath('userData')/state.json`. Anchor by the bottom edge
so a height change keeps the character standing on the same line:

```js
y: saved.y + (savedHeight - WINDOW_HEIGHT)
```

Clamp the restored bounds into a display work area, and if the saved window is mostly offscreen,
fall back to the primary display's bottom-right corner. Debounce saves to ~350ms and listen to
`display-added` / `display-removed` / `display-metrics-changed` to pull the window back onscreen.

## start.sh

```bash
#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")"
if [ ! -x "./node_modules/electron/dist/Electron.app/Contents/MacOS/Electron" ]; then
  node node_modules/electron/install.js
fi
unset ELECTRON_RUN_AS_NODE
exec node ./node_modules/electron/cli.js . "$@"
```

`npm start` should call this script. Electron 45's npm package is a lazy binary, so the
`dist` check and `install.js` fallback matter. If the download is needed offline, set
`ELECTRON_MIRROR` to a reachable mirror.

## Image Sizing

Resize transparent cutouts to twice the CSS display width so Retina shows them at native
resolution. Keep `object-fit: contain` with `object-position: center bottom` on the frame
so states with different aspect ratios stay foot-aligned:

```css
.pet-frame {
  width: auto; max-width: 100%;
  height: 100%; max-height: 100%;
  object-fit: contain; object-position: center bottom;
  pointer-events: none; -webkit-user-drag: none;
}
```

## Verification

Add `--check` and `--snapshot` modes:

- `--check` runs `executeJavaScript` to assert renderer readiness, loaded images,
  and that a synthetic click toggles the state, plus window properties
  (`alwaysOnTop`, `resizable === false`, `hasShadow === false`, correct bounds).
- `--snapshot` waits for readiness, calls `webContents.capturePage()`, writes a PNG, and
  exits. Confirm the PNG is nonblank and its corners have alpha 0.

Both modes create the window with `show: false`; the window never needs to be visible.

## Per-Pixel Mouse Passthrough

A transparent window still intercepts clicks across its whole rectangle. Let clicks fall
through the empty surround and only react on the character:

- Start with `mainWindow.setIgnoreMouseEvents(true, { forward: true })`. `forward` keeps
  `mousemove` events flowing while ignoring, so the renderer can re-enable interaction.
- In the renderer, build a one-channel alpha mask per frame by drawing the image to an
  offscreen canvas and reading `getImageData(...).data` (alpha is every fourth byte).
- On `mousemove`, map the cursor into the frame's `object-fit: contain` content rect
  (respecting `object-position: center bottom`), sample the alpha, and IPC back to main:

```js
ipcMain.on('pet:set-ignore-mouse', (_event, ignore) => {
  mainWindow.setIgnoreMouseEvents(Boolean(ignore), { forward: Boolean(ignore) });
});
```

- Only call `setIgnoreMouseEvents` when the state actually flips, and skip the hit test
  while a drag is in flight so dragging is never interrupted.
- Use a small alpha threshold (for example 8) so anti-aliased character edges still
  respond, while the empty surround passes through to the desktop.
