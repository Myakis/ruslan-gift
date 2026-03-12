# ElectroBun migration progress (implementation)

## Branch
`feat/electrobun-migration-implementation` (from `chore/electrobun-migration-plan`)

## What is implemented

### 1) New ElectroBun app scaffold in `new/`
- Added runnable ElectroBun project structure:
  - `electrobun.config.ts`
  - `package.json`
  - `tsconfig.json`
  - `src/bun/*`, `src/core/*`, `src/shared/*`, `src/views/*`
- Kept legacy Electron app intact in `old/`.

### 2) Functional parity baseline
Implemented minimum viable parity for core flows:

- **Login flow**
  - Login window in ElectroBun (`views://login/index.html`)
  - Credentials persisted to local JSON store (`Utils.paths.userData/state.json`)
  - Transition to main window after login

- **Main view**
  - Main UI window (`views://main/index.html`)
  - Embedded webview loads `https://wplan.office.lan/`
  - Auto-login injection script on `dom-ready`

- **Settings/menu**
  - Settings window and save logic
  - Main menu actions: settings/reload/logout
  - App menu with Settings/Quit entries

- **IPC/bridge equivalents**
  - Replaced Electron preload+ipc with ElectroBun typed RPC:
    - shared schema: `src/shared/rpc.ts`
    - Bun handlers in `src/bun/index.ts`
    - Browser-side adapters in `src/views/*/index.ts`
  - For gradual migration compatibility, renderer still uses `window.electronAPI` (now mapped to Electroview RPC)

- **Scheduler/notifications**
  - Scheduler moved to `src/core/scheduler.ts`
  - Start/end day auto-click logic preserved
  - Keep-alive (session activity) every 3h preserved
  - Native notifications via `Utils.showNotification`

### 3) Release/build setup (macOS + Windows required)

#### Local build commands
From repo root:

```bash
cd new
bun install

# Dev
bun run dev

# macOS release build (arm64 + x64)
bun run build:mac

# Windows release build (x64)
bun run build:win

# Unified release build (macOS + Windows)
bun run build:release
```

#### CI workflow
- Added: `.github/workflows/release-electrobun.yml`
  - macOS job: builds and uploads artifacts
  - Windows job: builds and uploads artifacts
  - tag-based GitHub release upload (`electrobun-v*`)

#### Expected artifacts
- Output directory: `new/artifacts/`
- Naming/contents depend on ElectroBun build channel + target tuple

## Current coverage status

### Working now (implemented)
- ElectroBun project bootstrap and config
- Login window + credential persistence
- Main window + wplan webview load
- Settings flow and persistence
- Basic menu actions (settings/reload/logout)
- Scheduler + notifications core path
- macOS and Windows build commands + CI workflow

### Partially covered
- Deep runtime verification of all DOM timing edge-cases on real `wplan.office.lan`
- `typeInDebugger` flow is implemented via JS typing fallback (not Electron debugger protocol exact equivalent)
- Auto-update base URL is placeholder and needs production artifact host

### Not covered yet
- Production auto-update host integration and smoke verification
- Code-signing/notarization secrets and signed release hardening
- Exhaustive E2E tests across macOS and Windows

## Notes and safety decisions
- `old/` was not modified as runtime source of truth for current Electron app.
- Migration is incremental and reversible.
- Storage format in new app is isolated (`state.json`), no destructive migration from old store yet.

## Quick local validation checklist after `git pull`
1. `cd new && bun install`
2. `bun run dev`
3. In app:
   - login with test creds,
   - verify main window opens and loads wplan URL,
   - open settings, change times/toggles, save,
   - click reload/logout from main view,
   - check scheduler logs and notifications behavior.
4. Build:
   - `bun run build:mac`
   - `bun run build:win`
5. Verify artifacts in `new/artifacts/`.
