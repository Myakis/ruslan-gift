const { ipcMain } = require('electron');
const { createMainWindow, getMainWindow, getLoginWindow, createLoginWindow, createSettingsWindow, getSettingsWindow } = require('./windows');
const { setupScheduler, getButtonState } = require('./scheduler');

function initializeIpcHandlers(store, Notification) {
  ipcMain.handle('login-data', async (event, credentials) => {
    console.log('Получены данные для входа:', credentials);
    const isAuthenticated = true; // Заглушка

    if (isAuthenticated) {
      store.set('credentials', credentials);
      const mainWindow = createMainWindow(store, setupScheduler, Notification); // Передаем Notification
      const loginWindow = getLoginWindow();
      if (loginWindow) {
        loginWindow.close();
      }
      return { success: true };
    } else {
      return { success: false, message: 'Неверный логин или пароль' };
    }
  });

  ipcMain.on('open-settings', () => {
    console.log('Пользователь нажал "Настройки"');
    createSettingsWindow();
  });

  ipcMain.handle('get-settings', async () => {
    return store.get('settings') || {};
  });

  ipcMain.on('save-settings', (event, settings) => {
    console.log('Сохранение настроек:', settings);
    store.set('settings', settings);
    
    // Перезапускаем планировщик с новыми настройками
    const mainWindow = getMainWindow();
    const view = mainWindow ? mainWindow.getBrowserView() : null;
    if (view) {
      console.log('Настройки сохранены. Перезапускаем планировщик...');
      setupScheduler(view.webContents, store, Notification); // Передаем Notification
    }

    const settingsWindow = getSettingsWindow();
    if (settingsWindow) {
      settingsWindow.close();
    }
  });

  ipcMain.handle('get-button-state', async () => {
    const mainWindow = getMainWindow();
    const view = mainWindow.getBrowserView();
    if (view) {
      return await getButtonState(view.webContents);
    }
    return null;
  });

  ipcMain.on('logout', () => {
    console.log('Пользователь нажал "Выход"');
    store.delete('credentials');
    
    const mainWindow = getMainWindow();
    if (mainWindow) {
      mainWindow.close();
    }
    
    createLoginWindow();
  });

  ipcMain.on('reload-wplan', () => {
    console.log('Пользователь нажал "Перезагрузить"');
    const mainWindow = getMainWindow();
    const view = mainWindow ? mainWindow.getBrowserView() : null;
    if (view && !view.webContents.isDestroyed()) {
      view.webContents.reload();
    } else {
      console.log('reload-wplan: BrowserView не доступен, перезагрузка отменена.');
    }
  });

  ipcMain.handle('type-in-debugger', async (event, text) => {
    const mainWindow = getMainWindow();
    const view = mainWindow.getBrowserView();
    if (view && !view.webContents.isDestroyed()) {
        // Дебаггер нужно аттачить к webContents от BrowserView
        try {
            view.webContents.debugger.attach('1.3');
        } catch (err) {
            console.log('Debugger attach failed on demand: ', err);
            return false;
        }

        for (const char of text) {
            await view.webContents.debugger.sendCommand('Input.dispatchKeyEvent', {
                type: 'char',
                text: char,
            });
        }
        
        try {
            view.webContents.debugger.detach();
        } catch (err) {
            console.log('Debugger detach failed on demand: ', err);
        }

        return true;
    }
    return false;
  });

  ipcMain.handle('get-notification-permission-status', () => {
    return Notification.isSupported();
  });
}

module.exports = { initializeIpcHandlers };
