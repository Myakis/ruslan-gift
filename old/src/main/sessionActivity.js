let keepAliveInterval = null;

async function simulateActivity(webContents) {
  if (!webContents || webContents.isDestroyed()) {
    console.log('simulateActivity: webContents не доступен или уничтожен.');
    return;
  }
  try {
    await webContents.executeJavaScript(`
      (function() {
        const evt = new MouseEvent('mousemove', { bubbles: true, clientX: 1, clientY: 1 });
        window.dispatchEvent(evt);
        if (document.body) {
          document.body.dispatchEvent(new MouseEvent('mousemove', { bubbles: true, clientX: 2, clientY: 2 }));
        }
        return true;
      })();
    `);
    console.log('simulateActivity: Отправлено небольшое событие активности для поддержания сессии.');
  } catch (error) {
    console.error('simulateActivity: Ошибка при симуляции активности:', error.message);
  }
}

function scheduleKeepAlive(webContents) {
  if (!webContents || webContents.isDestroyed()) {
    console.log('scheduleKeepAlive: webContents не доступен или уничтожен. Keep-alive не запланирован.');
    return;
  }
  // Запускаем немедленно и затем каждые 3 часа
  simulateActivity(webContents);
  keepAliveInterval = setInterval(() => simulateActivity(webContents), 3 * 60 * 60 * 1000);
  console.log('scheduleKeepAlive: Keep-alive настроен каждые 3 часа.');
}

function clearKeepAlive() {
  if (keepAliveInterval) {
    clearInterval(keepAliveInterval);
    keepAliveInterval = null;
  }
}

module.exports = {
  scheduleKeepAlive,
  clearKeepAlive,
};
