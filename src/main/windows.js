const { BrowserWindow, BrowserView } = require('electron');
const path = require('path');

let mainWindow;
let loginWindow;
let settingsWindow;

const MENU_BAR_HEIGHT = 40; // Высота меню-бара

function createLoginWindow() {
  loginWindow = new BrowserWindow({
    width: 400,
    height: 600,
    icon: path.join(__dirname, '../assets/images/logo-wplan.icns'),
    webPreferences: {
      preload: path.join(__dirname, '../preload/loginPreload.js'),
      contextIsolation: true,
      nodeIntegration: false,
    },
  });

  loginWindow.loadFile(path.join(__dirname, '../assets/html/login.html'));

  loginWindow.on('closed', () => {
    loginWindow = null;
  });
  
  return loginWindow;
}

function createMainWindow(store, setupScheduler, Notification) {
  const credentials = store.get('credentials');
  mainWindow = new BrowserWindow({
    width: 1200,
    height: 800,
    icon: path.join(__dirname, '../assets/images/logo-wplan.icns'),
    webPreferences: {
      preload: path.join(__dirname, '../preload/mainPreload.js'),
      contextIsolation: true,
      nodeIntegration: false,
    },
  });

  // Загружаем наш HTML-контейнер
  mainWindow.loadFile(path.join(__dirname, '../assets/html/main.html'));

  // Создаем BrowserView для Wplan
  const view = new BrowserView();
  mainWindow.setBrowserView(view);

  // Позиционируем BrowserView
  const [width, height] = mainWindow.getSize();
  view.setBounds({ x: 0, y: MENU_BAR_HEIGHT, width: width, height: height - MENU_BAR_HEIGHT });
  view.setAutoResize({ width: true, height: true });

  // Загружаем Wplan в BrowserView
  view.webContents.loadURL('https://wplan.office.lan/');

  // Логика авто-логина теперь применяется к webContentsของ BrowserView
  let isAutoLoginSent = false;
  view.webContents.on('did-finish-load', () => {
    if (credentials && !isAutoLoginSent) {
      console.log('Первая загрузка Wplan. Внедряю скрипт авто-логина...');
      isAutoLoginSent = true;
      view.webContents.executeJavaScript(`
        (async function() {
          function waitForElement(selector) {
            return new Promise(resolve => {
              if (document.querySelector(selector)) {
                return resolve(document.querySelector(selector));
              }
              const observer = new MutationObserver(() => {
                if (document.querySelector(selector)) {
                  resolve(document.querySelector(selector));
                  observer.disconnect();
                }
              });
              observer.observe(document.body, { childList: true, subtree: true });
            });
          }
          console.log('Скрипт внедрен. Ожидание кнопки #loginButton...');
          const loginButton = await waitForElement('#loginButton');
          console.log('Кнопка входа найдена. Заполняю форму...');
          const usernameField = document.querySelector('input[name="login"]');
          const passwordField = document.querySelector('input[name="password"]');
          if (usernameField && passwordField) {
            const nativeInputValueSetter = Object.getOwnPropertyDescriptor(window.HTMLInputElement.prototype, 'value').set;
            const inputEvent = new Event('input', { bubbles: true });
            nativeInputValueSetter.call(usernameField, '${credentials.username}');
            usernameField.dispatchEvent(inputEvent);
            await new Promise(r => setTimeout(r, 100));
            nativeInputValueSetter.call(passwordField, '${credentials.password}');
            passwordField.dispatchEvent(inputEvent);
            await new Promise(r => setTimeout(r, 100));
            loginButton.click();
          } else {
            console.error('Не удалось найти поля для логина или пароля.');
          }
        })();
      `);
    }
    // Передаем webContents от BrowserView в планировщик
    setupScheduler(view.webContents, store, Notification);
  });

  mainWindow.on('closed', () => {
    // BrowserView уничтожается вместе с окном
    mainWindow = null;
  });
  
  return mainWindow;
}


function getMainWindow() { return mainWindow; }
function getLoginWindow() { return loginWindow; }


function createSettingsWindow() {
  settingsWindow = new BrowserWindow({
    width: 500,
    height: 500,
    title: 'Настройки',
    webPreferences: {
      preload: path.join(__dirname, '../preload/settingsPreload.js'),
    },
  });

  settingsWindow.loadFile(path.join(__dirname, '../assets/html/settings.html'));
  
  settingsWindow.on('closed', () => {
    settingsWindow = null;
  });

  return settingsWindow;
}

function getSettingsWindow() { return settingsWindow; }

module.exports = {
  createLoginWindow,
  createMainWindow,
  createSettingsWindow,
  getMainWindow,
  getLoginWindow,
  getSettingsWindow,
};