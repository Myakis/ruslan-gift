import { Electroview } from "electrobun/view";
import type { Settings, WplanRPC } from "../../shared/rpc";

const rpc = Electroview.defineRPC<WplanRPC>({
  handlers: {
    requests: { ping: () => ({ ok: true }) },
    messages: {
      schedulerEvent: ({ type, message }) => console[type === "error" ? "error" : "log"]("scheduler:", message),
    },
  },
});

const view = new Electroview({ rpc });

(window as any).electronAPI = {
  getSettings: () => view.rpc.bun.request.getSettings({}),
  saveSettings: (settings: Settings) => view.rpc.bun.request.saveSettings(settings),
  getButtonState: () => view.rpc.bun.request.getButtonState({}),
  getNotificationPermissionStatus: () => view.rpc.bun.request.getNotificationPermissionStatus({}),
};

console.log("[settings-view] rpc bridge ready");
