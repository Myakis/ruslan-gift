import { ApplicationMenu, BrowserView, BrowserWindow, Utils } from "electrobun/bun";
import type { WplanRPC } from "../shared/rpc";
import { AppStore } from "../core/store";
import { getButtonState, setupScheduler } from "../core/scheduler";
import { isNotificationsSupported } from "../core/notifications";

const store = new AppStore();
let loginWindow: BrowserWindow | null = null;
let mainWindow: BrowserWindow | null = null;
let settingsWindow: BrowserWindow | null = null;

const rpc = BrowserView.defineRPC<WplanRPC>({
  handlers: {
    requests: {
      login: async ({ username, password }) => {
        await store.setCredentials({ username, password });
        openMainWindow();
        loginWindow?.close();
        loginWindow = null;
        return { success: true };
      },
      getSettings: () => store.getSettings(),
      saveSettings: async (settings) => {
        await store.setSettings(settings);
        if (mainWindow) setupScheduler(mainWindow.webview, store.getSettings());
        settingsWindow?.close();
        settingsWindow = null;
        return { success: true };
      },
      getButtonState: async () => {
        if (!mainWindow) return null;
        return getButtonState(mainWindow.webview);
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
      reloadWplan: () => mainWindow?.webview.reload(),
      typeInDebugger: ({ text }) => {
        void mainWindow?.webview.executeJavascript(`
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
    const waitForElement = (selector, timeout = 15000) => new Promise((resolve, reject) => {
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
  loginWindow = new BrowserWindow({
    title: "Wplan Auto - Login",
    url: "views://login",
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
    url: "views://settings",
    rpc,
    frame: { width: 500, height: 600, x: 280, y: 180 },
  });
  settingsWindow.on("close", () => (settingsWindow = null));
}

function openMainWindow() {
  if (mainWindow) return mainWindow.focus();
  mainWindow = new BrowserWindow({
    title: "Wplan Auto",
    url: "views://main",
    rpc,
    frame: { width: 1200, height: 800, x: 120, y: 80 },
  });

  mainWindow.webview.loadURL("https://wplan.office.lan/");

  const credentials = store.getCredentials();
  if (credentials) {
    mainWindow.webview.on("dom-ready", () => {
      void mainWindow?.webview.executeJavascript(autologinScript(credentials.username, credentials.password));
    });
  }

  setupScheduler(mainWindow.webview, store.getSettings());
  mainWindow.on("close", () => (mainWindow = null));
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

  console.log("Wplan ElectroBun started in", Utils.paths.userData);
}

void bootstrap();
