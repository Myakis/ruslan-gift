import Electrobun, { Electroview } from "electrobun/view";
import type { WplanRPC } from "../../shared/rpc";

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
  openSettings: () => electrobun.rpc!.send.openSettings({}),
  logout: () => electrobun.rpc!.send.logout({}),
  reloadWplan: () => electrobun.rpc!.send.reloadWplan({}),
  typeInDebugger: (text: string) => electrobun.rpc!.send.typeInDebugger({ text }),
  getCredentials: () => electrobun.rpc!.request.getCredentials({}),
};

