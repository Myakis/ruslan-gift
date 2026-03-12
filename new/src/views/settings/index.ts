import Electrobun, { Electroview } from "electrobun/view";
import type { Settings, WplanRPC } from "../../shared/rpc";

const rpc = Electroview.defineRPC<WplanRPC>({
  handlers: {
    requests: { ping: () => ({ ok: true }) },
    messages: {
      schedulerEvent: ({ type, message }) => console[type === "error" ? "error" : "log"]("scheduler:", message),
    },
  },
});

const electrobun = new Electrobun.Electroview({ rpc });

(window as any).electronAPI = {
  getSettings: () => electrobun.rpc!.request.getSettings({}),
  saveSettings: (settings: Settings) => electrobun.rpc!.request.saveSettings(settings),
  getButtonState: () => electrobun.rpc!.request.getButtonState({}),
  getNotificationPermissionStatus: () => electrobun.rpc!.request.getNotificationPermissionStatus({}),
};

