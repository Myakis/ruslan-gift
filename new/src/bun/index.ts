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
    return { submitted: false, state: 'no-credentials' };
  }

  console.log("[autologin] injection attempted");

  // Важно: fire-and-forget, чтобы не упираться в RPC timeout при ожидании формы
  view.executeJavascript(`
    (function() {
      if (window.__wplanAutoLoginTimer) return;

      const userValue = ${JSON.stringify(credentials.username)};
      const passValue = ${JSON.stringify(credentials.password)};
      const pick = (arr) => arr.map((s) => document.querySelector(s)).find(Boolean) || null;
      const selectors = {
        user: ['input[name="login"]', 'input[name="username"]', '#login', '#username'],
        pass: ['input[name="password"]', '#password', 'input[type="password"]'],
        submit: ['#loginButton', 'button[type="submit"]', 'button[name="login"]', '.login-button']
      };

      const setNative = (el, value) => {
        const d = Object.getOwnPropertyDescriptor(HTMLInputElement.prototype, 'value');
        if (d && d.set) d.set.call(el, value); else el.value = value;
        el.dispatchEvent(new Event('input', { bubbles: true }));
        el.dispatchEvent(new Event('change', { bubbles: true }));
      };

      let tries = 0;
      window.__wplanAutoLoginTimer = setInterval(() => {
        tries += 1;
        const user = pick(selectors.user);
        const pass = pick(selectors.pass);
        const submit = pick(selectors.submit);

        if (user && pass && submit) {
          setNative(user, userValue);
          setNative(pass, passValue);
          submit.click();
          window.__wplanAutoLoginDone = true;
          clearInterval(window.__wplanAutoLoginTimer);
          window.__wplanAutoLoginTimer = null;
          console.log('[autologin] submitted');
          return;
        }

        if (tries >= 30) {
          clearInterval(window.__wplanAutoLoginTimer);
          window.__wplanAutoLoginTimer = null;
          console.log('[autologin] form-not-found');
        }
      }, 400);
    })();
  `);

  return { submitted: false, state: 'injected' };
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

  let autoLoginCompleted = false;
  let autoLoginAttempts = 0;

  const scheduleAutoLogin = () => {
    if (!wplanView || autoLoginCompleted || autoLoginAttempts >= 8) return;
    autoLoginAttempts += 1;
    const attemptNo = autoLoginAttempts;
    console.log(`[autologin] attempt #${attemptNo}`);
    setTimeout(async () => {
      if (!wplanView || autoLoginCompleted) return;
      try {
        await tryAutoLogin(wplanView);
        // one-shot inject script now contains its own retry loop inside the page
        autoLoginCompleted = true;
      } catch (e) {
        console.warn('[autologin] attempt failed:', e);
      }
    }, 300);
  };

  wplanView.on("dom-ready", () => {
    if (!wplanView) return;
    scheduleAutoLogin();
    setupScheduler(wplanView, store.getSettings());
  });

  wplanView.on("did-navigate", () => {
    scheduleAutoLogin();
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
