const { sendNotification } = require('./notifications');
const { scheduleKeepAlive, clearKeepAlive } = require('./sessionActivity');

let schedulerTimeouts = [];

function clearAllTimeouts() {
    schedulerTimeouts.forEach(timeout => clearTimeout(timeout));
    schedulerTimeouts = [];
    clearKeepAlive();
}

// Вспомогательная функция для ожидания элемента в DOM
const waitForElementScript = `
  function waitForElement(selector, timeout = 15000) {
    return new Promise((resolve, reject) => {
      const element = document.querySelector(selector);
      if (element) {
        return resolve(element);
      }

      const observer = new MutationObserver(() => {
        const foundElement = document.querySelector(selector);
        if (foundElement) {
          observer.disconnect();
          resolve(foundElement);
        }
      });

      observer.observe(document.body, { childList: true, subtree: true });

      setTimeout(() => {
        observer.disconnect();
        reject(new Error(\`Таймаут ожидания элемента \${selector}\`));
      }, timeout);
    });
  }
`;

async function getButtonState(webContents) {
  if (!webContents || webContents.isDestroyed()) {
    console.log('getButtonState: webContents не доступен или уничтожен.');
    return null;
  }
  try {
    const buttonText = await webContents.executeJavaScript(`
      ${waitForElementScript}
      (async function() {
        try {
          const button = await waitForElement('#startEndWorkButton', 10000); // Короткий таймаут для проверки состояния
          console.log('getButtonState (внутри рендерера): Кнопка найдена, текст:', button.innerText);
          return button.innerText;
        } catch (e) {
          console.error('getButtonState (внутри рендерера): Ошибка при поиске кнопки:', e.message);
          return null;
        }
      })();
    `);
    return buttonText;
  } catch (error) {
    console.error('getButtonState (основной процесс): Ошибка при получении состояния кнопки:', error.message);
    return null;
  }
}


async function clickStartEndButton(webContents, store, Notification) {
    if (!webContents || webContents.isDestroyed()) {
        console.log('clickStartEndButton: webContents не доступен или уничтожен. Клик отменен.');
        return;
    }
    console.log('clickStartEndButton (основной процесс): Попытка нажать кнопку startEndWorkButton...');
    try {
        const result = await webContents.executeJavaScript(`
            ${waitForElementScript}
            (async function() {
                try {
                    console.log('clickStartEndButton (внутри рендерера): Поиск кнопки для клика...');
                    const button = await waitForElement('#startEndWorkButton', 10000); // Увеличил таймаут
                    
                    console.log('clickStartEndButton (внутри рендерера): Кнопка найдена, текст:', button.innerText);
                    // Имитация пользовательского клика
                    button.dispatchEvent(new MouseEvent('mousedown', { bubbles: true }));
                    button.dispatchEvent(new MouseEvent('mouseup', { bubbles: true }));
                    button.dispatchEvent(new MouseEvent('click', { bubbles: true }));
                    console.log('clickStartEndButton (внутри рендерера): События клика отправлены.');
                    return 'Кнопка успешно нажата';
                } catch (e) {
                    console.error('clickStartEndButton (внутри рендерера): Ошибка при выполнении скрипта:', e.message, e.stack);
                    return \`Ошибка: \${e.message}\`; // Возвращаем сообщение об ошибке
                }
            })();
        `);
        console.log('clickStartEndButton (результат):', result);

        if (result === 'Кнопка успешно нажата') {
            console.log('clickStartEndButton: Кнопка нажата, ожидание 10 секунд для обновления страницы...');
            setTimeout(() => {
                console.log('clickStartEndButton: Перезапуск планировщика после клика...');
                setupScheduler(webContents, store, Notification);
            }, 5000);
        } else if (result.startsWith('Ошибка:')) {
            console.warn('clickStartEndButton: Клик не выполнен из-за ошибки в рендерере:', result);
        } else {
            console.warn('clickStartEndButton: Клик не выполнен по неизвестной причине.');
        }
    } catch (error) {
        console.error('clickStartEndButton (основной процесс): Ошибка при выполнении скрипта:', error);
    }
}

async function setupScheduler(webContents, store, Notification) {
  clearAllTimeouts(); // Всегда очищаем старые таймеры перед новой настройкой
  
  const settings = store.get('settings') || {};
  const autoStartEnabled = settings.autoStartEnabled ?? true;
  const notificationsEnabled = settings.notificationsEnabled ?? true;

  if (!autoStartEnabled) {
    console.log('Автоматизация отключена в настройках.');
    return;
  }

  console.log('Настройка точного планировщика...');
  
  const startHour = settings.startHour;
  const startMinute = settings.startMinute;
  const endHour = settings.endHour;
  const endMinute = settings.endMinute;

  const now = new Date();

  // --- Планирование НАЧАЛА рабочего дня ---
  if (startHour !== undefined && startMinute !== undefined) {
    let startTime = new Date(now);
    startTime.setHours(startHour, startMinute, 0, 0);

    const nowTime = now.getHours() * 60 + now.getMinutes();
    const startTimeInMinutes = startHour * 60 + startMinute;

    // Если только наступила минута старта — даём несколько секунд для запуска "сегодня"
    if (nowTime === startTimeInMinutes && now.getSeconds() < 5) {
      const startDelay = 5000 - now.getMilliseconds();
      console.log(`Клик "Начать" запланирован в ${startTime.toLocaleTimeString()} (через ${Math.round(startDelay / 1000)} сек, с учетом секунд)`);
      const startTimeout = setTimeout(async () => {
        console.log(`[Событие] Время начала (${startTime.toLocaleTimeString()}). Проверяем кнопку...`);
        const buttonState = await getButtonState(webContents);
        if (buttonState && buttonState.includes('Начать')) {
            clickStartEndButton(webContents, store, Notification);
            sendNotification('Начало дня', Notification, notificationsEnabled, 'Wplan Auto', 'Рабочий день начался!');
        } else {
            console.log('[Событие] Кнопка "Начать" не найдена или день уже начат. Клик отменен.');
        }
      }, startDelay);
      schedulerTimeouts.push(startTimeout);
    } else {
      // Если время старта уже прошло — переносим на следующий день
      if (now >= startTime) {
        startTime.setDate(startTime.getDate() + 1);
        console.log(`Время начала уже прошло. Переносим клик "Начать" на ${startTime.toLocaleString()}.`);
      } else {
        console.log(`Клик "Начать" запланирован в ${startTime.toLocaleTimeString()} (сегодня).`);
      }

      const startDelay = startTime.getTime() - now.getTime();
      const startTimeout = setTimeout(async () => {
        console.log(`[Событие] Время начала (${startTime.toLocaleString()}). Проверяем кнопку...`);
        const buttonState = await getButtonState(webContents);
        if (buttonState && buttonState.includes('Начать')) {
            clickStartEndButton(webContents, store, Notification);
            sendNotification('Начало дня', Notification, notificationsEnabled, 'Wplan Auto', 'Рабочий день начался!');
        } else {
            console.log('[Событие] Кнопка "Начать" не найдена или день уже начат. Клик отменен.');
        }
      }, startDelay);
      schedulerTimeouts.push(startTimeout);
      console.log(`Клик "Начать" запланирован в ${startTime.toLocaleString()} (через ${Math.round(startDelay / 1000)} сек).`);
    }
  } else {
    console.log('Время начала не настроено.');
  }

  // Keep-alive для активной сессии
  scheduleKeepAlive(webContents);

  // --- Планирование ОКОНЧАНИЯ рабочего дня ---
  if (endHour !== undefined && endMinute !== undefined) {
    let endTime = new Date(now);
    endTime.setHours(endHour, endMinute, 0, 0);

    const nowTime = now.getHours() * 60 + now.getMinutes();
    const endTimeInMinutes = endHour * 60 + endMinute;

    if (nowTime === endTimeInMinutes && now.getSeconds() < 5) { // Добавляем допущение на несколько секунд после наступления минуты
      const endDelay = 5000 - now.getMilliseconds(); // Запускаем через несколько секунд, чтобы избежать повторного срабатывания
      console.log(`Клик "Завершить" запланирован в ${endTime.toLocaleTimeString()} (через ${Math.round(endDelay / 1000)} сек, с учетом секунд)`);
      const endTimeout = setTimeout(async () => {
        console.log(`[Событие] Время окончания (${endTime.toLocaleTimeString()}). Проверяем кнопку...`);
        const buttonState = await getButtonState(webContents);
        if (buttonState && buttonState.includes('Завершить')) {
            clickStartEndButton(webContents, store, Notification);
            sendNotification('Конец дня', Notification, notificationsEnabled, 'Wplan Auto', 'Рабочий день завершен!');
        } else {
            console.log('[Событие] Кнопка "Завершить" не найдена или день еще не начат. Клик отменен.');
        }
      }, endDelay);
      schedulerTimeouts.push(endTimeout);
    } else {
      if (now >= endTime) {
        endTime.setDate(endTime.getDate() + 1);
        console.log(`Время окончания уже прошло. Переносим клик "Завершить" на ${endTime.toLocaleString()}.`);
      } else {
        console.log(`Клик "Завершить" запланирован в ${endTime.toLocaleTimeString()} (сегодня).`);
      }

      const endDelay = endTime.getTime() - now.getTime();
      const endTimeout = setTimeout(async () => {
        console.log(`[Событие] Время окончания (${endTime.toLocaleString()}). Проверяем кнопку...`);
        const buttonState = await getButtonState(webContents);
        if (buttonState && buttonState.includes('Завершить')) {
            clickStartEndButton(webContents, store, Notification);
            sendNotification('Конец дня', Notification, notificationsEnabled, 'Wplan Auto', 'Рабочий день завершен!');
        } else {
            console.log('[Событие] Кнопка "Завершить" не найдена или день еще не начат. Клик отменен.');
        }
      }, endDelay);
      schedulerTimeouts.push(endTimeout);
      console.log(`Клик "Завершить" запланирован в ${endTime.toLocaleString()} (через ${Math.round(endDelay / 1000)} сек).`);
    }
  } else {
    console.log('Время окончания не настроено.');
  }
}

function clearScheduler() {
    clearAllTimeouts();
}

module.exports = { setupScheduler, clearScheduler, getButtonState };
