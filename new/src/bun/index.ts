import { ApplicationMenu, BrowserView, BrowserWindow, Utils } from "electrobun/bun";
import type { WplanRPC } from "../shared/rpc";
import { AppStore } from "../core/store";
import { getButtonState, setupScheduler } from "../core/scheduler";
import { isNotificationsSupported } from "../core/notifications";

const store = new AppStore();
let loginWindow: BrowserWindow | null = null;
let mainWindow: BrowserWindow | null = null;
let settingsWindow: BrowserWindow | null = null;
let wplanView: BrowserView | null = null;

const rpc = BrowserView.defineRPC<WplanRPC>({
  handlers: {
    requests: {
      login: async ({ username, password }) => {
        await store.setCredentials({ username, password });
        openMainWindow();
        setTimeout(() => {
          if (loginWindow) {
            loginWindow.close();
            loginWindow = null;
          }
        }, 120);
        return { success: true };
      },
      getSettings: () => store.getSettings(),
      saveSettings: async (settings) => {
        await store.setSettings(settings);
        if (wplanView) setupScheduler(wplanView, store.getSettings());
        settingsWindow?.close();
        settingsWindow = null;
        return { success: true };
      },
      getButtonState: async () => {
        if (!wplanView) return null;
        return getButtonState(wplanView);
      },
      getNotificationPermissionStatus: () => isNotificationsSupported(),
      getSessionState: () => ({
        hasCredentials: Boolean(store.getCredentials()),
        isLoggedIn: Boolean(mainWindow),
        url: "https://wplan.office.lan/",
      }),
      getCredentials: () => store.getCredentials(),
    },
    messages: {
      openSettings: () => openSettingsWindow(),
      logout: async () => {
        await store.clearCredentials();
        mainWindow?.close();
        mainWindow = null;
        openLoginWindow();
      },
      reloadWplan: () => {
        try {
          if (wplanView && typeof (wplanView as any).reload === 'function') {
            (wplanView as any).reload();
          } else if (wplanView && typeof (wplanView as any).loadURL === 'function') {
            (wplanView as any).loadURL('https://wplan.office.lan/');
          } else {
            console.warn('[rpc] reloadWplan skipped: wplanView is unavailable');
          }
        } catch (e) {
          console.error('[rpc] reloadWplan error:', e);
        }
      },
      typeInDebugger: ({ text }) => {
        void wplanView?.executeJavascript(`
          (function(){
            const el = document.activeElement;
            if (el && ('value' in el)) {
              const nativeInputValueSetter = Object.getOwnPropertyDescriptor(window.HTMLInputElement.prototype, 'value').set;
              nativeInputValueSetter.call(el, (el.value || '') + ${JSON.stringify(text)});
              el.dispatchEvent(new Event('input', { bubbles: true }));
            }
          })();
        `);
      },
      closeSettings: () => {
        settingsWindow?.close();
        settingsWindow = null;
      }
    },
  },
});

function openLoginWindow() {
  if (loginWindow) return loginWindow;
  loginWindow = new BrowserWindow({
    title: "Wplan Auto - Login",
    url: "views://login/index.html",
    rpc,
    frame: { width: 400, height: 600, x: 240, y: 160 },
  });
  loginWindow.on("close", () => (loginWindow = null));
  return loginWindow;
}

function openSettingsWindow() {
  if (settingsWindow) return settingsWindow.focus();
  settingsWindow = new BrowserWindow({
    title: "Wplan Auto - Settings",
    url: "views://settings/index.html",
    rpc,
    frame: { width: 500, height: 600, x: 280, y: 180 },
  });
  settingsWindow.on("close", () => (settingsWindow = null));
}

function openMainWindow() {
  if (mainWindow) return mainWindow.focus();
  mainWindow = new BrowserWindow({
    title: "Wplan Auto",
    url: "views://main/index.html",
    rpc,
    frame: { width: 1200, height: 800, x: 120, y: 80 },
  });

  // На текущем этапе рендерим Wplan через <electrobun-webview> внутри main HTML.
  wplanView = null;

  // Fallback: прокидываем креды напрямую в root views-контекст,
  // даже если renderer bridge не инициализировался.
  const creds = store.getCredentials();
  if (creds?.username && creds?.password) {
    const js = `window.__WPLAN_CREDS__ = ${JSON.stringify(creds)};`;
    try {
      (mainWindow as any).webview?.on?.('dom-ready', () => {
        void (mainWindow as any).webview?.executeJavascript?.(js);
      });
      setTimeout(() => {
        void (mainWindow as any).webview?.executeJavascript?.(js);
      }, 500);
    } catch {}
  }

  mainWindow.on("close", () => {
    mainWindow = null;
    wplanView = null;
  });

  setTimeout(() => {
    mainWindow?.focus();
  }, 50);
}

async function bootstrap() {
  await store.init();

  ApplicationMenu.setApplicationMenu([
    { submenu: [{ label: "Quit", role: "quit" }] },
    {
      label: "Wplan Auto",
      submenu: [
        { label: "Settings", action: "open-settings" },
        { type: "separator" },
        { label: "Quit", role: "quit" },
      ],
    },
  ]);

  const credentials = store.getCredentials();
  if (credentials?.username && credentials?.password) {
    openMainWindow();
  } else {
    openLoginWindow();
  }

  console.log("[runtime] started", Utils.paths.userData);
}

void bootstrap();
