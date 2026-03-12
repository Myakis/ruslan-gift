const { updateElectronApp } = require('update-electron-app');
updateElectronApp();
const { app, BrowserWindow, nativeImage, Notification } = require('electron');
const path = require('path');
const Store = require('electron-store').default;
const { createLoginWindow, createMainWindow } = require('./windows');
const { initializeIpcHandlers } = require('./ipcHandlers');
const { setupScheduler } = require('./scheduler');

if (require('electron-squirrel-startup')) {
  app.quit();
}

const store = new Store({ projectName: 'wplan-auto' });

initializeIpcHandlers(store, Notification);

app.whenReady().then(() => {
  if (process.platform === 'darwin') {
    const image = nativeImage.createFromPath(path.join(__dirname, '../assets/images/logo-wplan.icns'));
    app.dock.setIcon(image);
  }

  const credentials = store.get('credentials');
  if (credentials && credentials.username && credentials.password) {
    console.log('Найдены сохраненные учетные данные. Попытка авто-входа...');
    createMainWindow(store, setupScheduler, Notification);
  } else {
    createLoginWindow();
  }

  app.on('activate', () => {
    if (BrowserWindow.getAllWindows().length === 0) {
      if (store.get('credentials')) {
        createMainWindow(store, setupScheduler, Notification);
      } else {
        createLoginWindow();
      }
    }
  });
});

app.on('window-all-closed', () => {
  if (process.platform !== 'darwin') {
    app.quit();
  }
});