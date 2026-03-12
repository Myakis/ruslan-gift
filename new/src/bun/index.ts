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

const MENU_BAR_HEIGHT = 50;

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
        wplanView = null;
        openLoginWindow();
      },
      reloadWplan: () => {
        if (!wplanView) return;
        wplanView.loadURL("https://wplan.office.lan/");
      },
      typeInDebugger: ({ text }) => {
        void wplanView?.executeJavascript(`
          (function() {
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

function resizeWplanView() {
  if (!mainWindow || !wplanView) return;
  const frame = mainWindow.getFrame();
  wplanView.frame = {
    x: 0,
    y: MENU_BAR_HEIGHT,
    width: frame.width,
    height: Math.max(0, frame.height - MENU_BAR_HEIGHT),
  };
}

async function tryAutoLogin(view: BrowserView) {
  const credentials = store.getCredentials();
  console.log("[autologin] credentials loaded:", Boolean(credentials?.username && credentials?.password));

  if (!credentials?.username || !credentials?.password) {
    console.log("[autologin] result state: no-credentials");
    return;
  }

  console.log("[autologin] injection attempted");
  const result = await view.rpc.request.evaluateJavascriptWithResponse({
    script: `
      (async function() {
        function waitForElement(selector) {
          return new Promise((resolve) => {
            const found = document.querySelector(selector);
            if (found) return resolve(found);
            const observer = new MutationObserver(() => {
              const el = document.querySelector(selector);
              if (el) {
                observer.disconnect();
                resolve(el);
              }
            });
            observer.observe(document.body, { childList: true, subtree: true });
          });
        }

        try {
          const loginButton = await waitForElement('#loginButton');
          const usernameField = document.querySelector('input[name="login"]');
          const passwordField = document.querySelector('input[name="password"]');

          if (!usernameField || !passwordField || !loginButton) {
            return { formFound: false, submitted: false, state: 'form-not-found' };
          }

          const nativeInputValueSetter = Object.getOwnPropertyDescriptor(window.HTMLInputElement.prototype, 'value').set;
          const inputEvent = new Event('input', { bubbles: true });

          nativeInputValueSetter.call(usernameField, ${JSON.stringify(credentials.username)});
          usernameField.dispatchEvent(inputEvent);
          await new Promise((r) => setTimeout(r, 100));

          nativeInputValueSetter.call(passwordField, ${JSON.stringify(credentials.password)});
          passwordField.dispatchEvent(inputEvent);
          await new Promise((r) => setTimeout(r, 100));

          loginButton.click();
          return { formFound: true, submitted: true, state: 'submitted' };
        } catch (e) {
          return { formFound: false, submitted: false, state: 'error', error: String(e?.message || e) };
        }
      })();
    `,
  });

  console.log("[autologin] form", result?.formFound ? "found" : "not found");
  if (result?.submitted) {
    console.log("[autologin] submit fired");
  }
  console.log("[autologin] result state:", result?.state ?? "unknown");
}

function openMainWindow() {
  if (mainWindow) return mainWindow.focus();

  mainWindow = new BrowserWindow({
    title: "Wplan Auto",
    url: "views://main/index.html",
    rpc,
    frame: { width: 1200, height: 800, x: 120, y: 80 },
  });

  const frame = mainWindow.getFrame();
  wplanView = new BrowserView({
    windowId: mainWindow.id,
    url: "https://wplan.office.lan/",
    renderer: "cef",
    frame: {
      x: 0,
      y: MENU_BAR_HEIGHT,
      width: frame.width,
      height: Math.max(0, frame.height - MENU_BAR_HEIGHT),
    },
  });

  let isAutoLoginSent = false;

  wplanView.on("dom-ready", () => {
    if (!wplanView) return;

    if (!isAutoLoginSent) {
      isAutoLoginSent = true;
      void tryAutoLogin(wplanView);
    }

    setupScheduler(wplanView, store.getSettings());
  });

  mainWindow.on("resize", resizeWplanView);

  mainWindow.on("close", () => {
    wplanView?.remove();
    wplanView = null;
    mainWindow = null;
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
