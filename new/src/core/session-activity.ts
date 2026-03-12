import type { BrowserView } from "electrobun/bun";

let keepAliveTimer: Timer | null = null;

export function clearKeepAlive() {
  if (keepAliveTimer) {
    clearInterval(keepAliveTimer);
    keepAliveTimer = null;
  }
}

export function scheduleKeepAlive(view: BrowserView) {
  clearKeepAlive();
  const heartbeat = () => {
    view.executeJavascript(`
      (function() {
        window.dispatchEvent(new MouseEvent('mousemove', { bubbles: true, clientX: 1, clientY: 1 }));
        document.body?.dispatchEvent(new MouseEvent('mousemove', { bubbles: true, clientX: 2, clientY: 2 }));
      })();
    `);
  };
  heartbeat();
  keepAliveTimer = setInterval(heartbeat, 3 * 60 * 60 * 1000);
}
