import { ApplicationMenu, BrowserView, BrowserWindow, Utils } from "electrobun/bun";
import type { WplanRPC } from "../shared/rpc";
import { AppStore } from "../core/store";
import { getButtonState } from "../core/scheduler";
import { isNotificationsSupported } from "../core/notifications";

const store = new AppStore();
let loginWindow: BrowserWindow | null = null;
let mainWindow: BrowserWindow | null = null;
let settingsWindow: BrowserWindow | null = null;

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
      reloadWplan: () => {
        try {
          if ((mainWindow as any)?.webview && typeof (mainWindow as any).webview.reload === 'function') {
            (mainWindow as any).webview.reload();
          } else {
            console.warn('[rpc] reloadWplan skipped: mainWindow.webview.reload is unavailable');
          }
        } catch (e) {
          console.error('[rpc] reloadWplan error:', e);
        }
      },
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

  // В ElectroBun основной UI рендерится в views://main/index.html.
  // Контент Wplan загружается внутри <webview> тега в main HTML.
  // Не подменяем корневой webview окна через mainWindow.webview.loadURL(...),
  // иначе views-страница затирается и автологин ломается.

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
    console.log("[bootstrap] credentials found, going to main window");
    openMainWindow();
  } else {
    console.log("[bootstrap] credentials not found, going to login window");
    openLoginWindow();
  }

  console.log("Wplan ElectroBun started in", Utils.paths.userData);
}

void bootstrap();
