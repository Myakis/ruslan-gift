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
        console.log("[rpc] login request received");
        await store.setCredentials({ username, password });
        console.log("[rpc] credentials stored, opening main window");
        openMainWindow();
        if (loginWindow) {
          loginWindow.close();
          loginWindow = null;
          console.log("[rpc] login window closed");
        }
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

function autologinScript(username: string, password: string) {
  return `
  (async function() {
    function waitForElement(selector, timeout = 15000) {
      return new Promise((resolve, reject) => {
        const initial = document.querySelector(selector);
        if (initial) return resolve(initial);
        const observer = new MutationObserver(() => {
          const found = document.querySelector(selector);
          if (found) {
            observer.disconnect();
            resolve(found);
          }
        });
        observer.observe(document.body, { childList: true, subtree: true });
        setTimeout(() => { observer.disconnect(); reject(new Error('timeout')); }, timeout);
      });
    }

    try {
      const loginButton = await waitForElement('#loginButton');
      const usernameField = document.querySelector('input[name="login"]');
      const passwordField = document.querySelector('input[name="password"]');
      if (!usernameField || !passwordField) return;
      const setValue = Object.getOwnPropertyDescriptor(window.HTMLInputElement.prototype, 'value').set;
      setValue.call(usernameField, ${JSON.stringify(username)});
      usernameField.dispatchEvent(new Event('input', { bubbles: true }));
      setValue.call(passwordField, ${JSON.stringify(password)});
      passwordField.dispatchEvent(new Event('input', { bubbles: true }));
      loginButton.click();
    } catch (e) {
      console.error('auto login failed', e);
    }
  })();`;
}

function openLoginWindow() {
  if (loginWindow) return loginWindow;
  console.log("[window] opening login window");
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
  console.log("[window] opening main window");
  mainWindow = new BrowserWindow({
    title: "Wplan Auto",
    url: "views://main/index.html",
    rpc,
    frame: { width: 1200, height: 800, x: 120, y: 80 },
  });

  // Отдельный BrowserView для рабочего сайта (как в исходном Electron-проекте)
  wplanView = new BrowserView({
    url: 'https://wplan.office.lan/',
    frame: { x: 0, y: 50, width: 1200, height: 750 },
  });

  const credentials = store.getCredentials();
  if (credentials) {
    wplanView.on('dom-ready', () => {
      console.log('[webview] dom-ready, running autologin script');
      void wplanView?.executeJavascript(autologinScript(credentials.username, credentials.password));
    });
  }

  setupScheduler(wplanView, store.getSettings());

  mainWindow.on("close", () => {
    mainWindow = null;
    wplanView = null;
  });
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
    console.log("[bootstrap] credentials found, going to main window");
    openMainWindow();
  } else {
    console.log("[bootstrap] credentials not found, going to login window");
    openLoginWindow();
  }

  console.log("Wplan ElectroBun started in", Utils.paths.userData);
}

void bootstrap();
