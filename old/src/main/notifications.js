function sendNotification(eventName, Notification, notificationsEnabled, title, body) {
  if (!notificationsEnabled) {
    console.log(`[Уведомление] (${eventName}) Уведомления отключены в настройках.`);
    return;
  }
  if (!Notification) {
    console.warn(`[Уведомление] (${eventName}) Объект Notification не доступен.`);
    return;
  }
  if (!Notification.isSupported || !Notification.isSupported()) {
    console.warn(`[Уведомление] (${eventName}) Нативные уведомления не поддерживаются в текущей среде.`);
    return;
  }

  console.log(`[Уведомление] (${eventName}) Попытка отправить уведомление.`);
  const notification = new Notification({
    title,
    body,
    silent: false,
  });
  notification.show();
  notification.on('show', () => console.log(`[Уведомление] (${eventName}) показано.`));
  notification.on('click', () => console.log(`[Уведомление] (${eventName}) кликнуто.`));
  notification.on('close', () => console.log(`[Уведомление] (${eventName}) закрыто.`));
  notification.on('failed', (event, error) => console.error(`[Уведомление] (${eventName}) Ошибка при отображении:`, error));
}

module.exports = { sendNotification };
