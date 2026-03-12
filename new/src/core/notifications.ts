import { Utils } from "electrobun/bun";

export function sendNotification(title: string, body: string, enabled = true) {
  if (!enabled) return;
  Utils.showNotification({ title, body, silent: false });
}

export function isNotificationsSupported() {
  return true;
}
