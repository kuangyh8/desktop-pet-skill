---
name: desktop-pet
description: Build a macOS desktop pet (桌宠 / 桌面宠物) as a transparent, frameless, always-on-top Electron window showing only a character, with click interactions and drag. Use when the user asks for a desktop pet, a floating mascot, or a transparent always-on-top character window.
---

# Desktop Pet

Build macOS desktop pets as a transparent, frameless, always-on-top Electron window that shows only the character. This recipe comes from the user's previous pets and should be the default approach.

## Workflow

1. Confirm the target is macOS and the pet has a small set of states, such as `still` (idle) and `move` (clicked). Size the window to the character, not to a fixed browser frame.
2. Prepare transparent character images. If source images have solid or gradient backgrounds, cut them out with [references/background-removal.md](references/background-removal.md) instead of shipping gray rectangles.
3. Scaffold the Electron app with `main.js`, `preload.js`, `renderer/`, and `start.sh`. Follow [references/macos-electron-pet.md](references/macos-electron-pet.md) for the window, drag, menu, and position persistence code.
4. Wire renderer interactions: a click toggles states, and a drag moves the window. Distinguish them with a 3px movement threshold.
5. Verify with `--check` (window properties, image loading, state toggle, zero console errors) and `--snapshot` (capture the window and confirm the PNG is nonblank with transparent corners).

## Hard-won constraints

- Unset `ELECTRON_RUN_AS_NODE` before launching Electron. Some terminals inject it, and otherwise the window silently never appears.
- Electron 45 ships a lazy binary; have `start.sh` run `node node_modules/electron/install.js` when `dist/Electron.app` is missing.
- Do not use `-webkit-app-region: drag`. It swallows `contextmenu`, so right-click stops working. Drive dragging over IPC and open the menu from the renderer's `contextmenu` event.
- Float over fullscreen apps with `setAlwaysOnTop(true, 'screen-saver')` plus `setVisibleOnAllWorkspaces(true, { visibleOnFullScreen: true, skipTransformProcessType: true })`.
- Vision-based background removal must run outside an app sandbox (ANE and CoreVideo are blocked inside sandboxed commands), and Swift needs an Xcode SDK plus a writable `-module-cache-path`.

Read the two reference files for concrete recipes. `scripts/cutout.swift` is the reusable background-removal tool.
