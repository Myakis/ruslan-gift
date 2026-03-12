import { Electroview } from "electrobun/view";
import type { WplanRPC } from "../../shared/rpc";

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
  openSettings: () => view.rpc.bun.send.openSettings({}),
  logout: () => view.rpc.bun.send.logout({}),
  reloadWplan: () => view.rpc.bun.send.reloadWplan({}),
  typeInDebugger: (text: string) => view.rpc.bun.send.typeInDebugger({ text }),
};

console.log("[main-view] rpc bridge ready");
