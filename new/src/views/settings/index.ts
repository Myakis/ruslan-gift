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
  getSettings: () => view.rpc.request.getSettings({}),
  saveSettings: (settings: Settings) => view.rpc.request.saveSettings(settings),
  getButtonState: () => view.rpc.request.getButtonState({}),
  getNotificationPermissionStatus: () => view.rpc.request.getNotificationPermissionStatus({}),
};
