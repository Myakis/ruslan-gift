import type { BrowserView } from "electrobun/bun";
import { sendNotification } from "./notifications";
import { clearKeepAlive, scheduleKeepAlive } from "./session-activity";
import type { Settings } from "../shared/rpc";

let timers: Timer[] = [];

const waitForElementScript = `
  function waitForElement(selector, timeout = 15000) {
    return new Promise((resolve, reject) => {
      const element = document.querySelector(selector);
      if (element) return resolve(element);
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
  }
`;

function clearTimers() {
  timers.forEach((t) => clearTimeout(t));
  timers = [];
  clearKeepAlive();
}

export async function getButtonState(view: BrowserView): Promise<string | null> {
  try {
    return await view.rpc.request.evaluateJavascriptWithResponse({
      script: `${waitForElementScript}; (async()=>{ try { const el = await waitForElement('#startEndWorkButton', 7000); return el?.innerText ?? null; } catch { return null; } })();`,
    });
  } catch {
    return null;
  }
}

async function clickStartEndButton(view: BrowserView) {
  await view.executeJavascript(`
    ${waitForElementScript}
    (async() => {
      const btn = await waitForElement('#startEndWorkButton', 10000);
      btn.dispatchEvent(new MouseEvent('mousedown', { bubbles: true }));
      btn.dispatchEvent(new MouseEvent('mouseup', { bubbles: true }));
      btn.dispatchEvent(new MouseEvent('click', { bubbles: true }));
    })();
  `);
}

function scheduleAt(date: Date, action: () => Promise<void>) {
  const delay = Math.max(0, date.getTime() - Date.now());
  timers.push(setTimeout(() => void action(), delay));
}

export function setupScheduler(view: BrowserView, settings: Settings) {
  clearTimers();
  if (!(settings.autoStartEnabled ?? true)) return;

  scheduleKeepAlive(view);

  const now = new Date();
  const notificationsEnabled = settings.notificationsEnabled ?? true;
  const schedulePoint = (
    hour: number | undefined,
    minute: number | undefined,
    expectedLabel: string,
    notificationTitle: string,
    notificationBody: string,
  ) => {
    if (hour === undefined || minute === undefined) return;
    const planned = new Date(now);
    planned.setHours(hour, minute, 0, 0);
    if (planned <= now) planned.setDate(planned.getDate() + 1);

    scheduleAt(planned, async () => {
      const state = await getButtonState(view);
      if (state?.includes(expectedLabel)) {
        await clickStartEndButton(view);
        sendNotification(notificationTitle, notificationBody, notificationsEnabled);
      }
      setupScheduler(view, settings);
    });
  };

  schedulePoint(settings.startHour, settings.startMinute, "Начать", "Начало дня", "Рабочий день начался");
  schedulePoint(settings.endHour, settings.endMinute, "Заверш", "Конец дня", "Рабочий день завершен");
}
