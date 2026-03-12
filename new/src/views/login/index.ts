import Electrobun, { Electroview } from "electrobun/view";
import type { WplanRPC } from "../../shared/rpc";

const rpc = Electroview.defineRPC<WplanRPC>({
  handlers: {
    requests: {
      ping: () => ({ ok: true }),
    },
    messages: {
      schedulerEvent: ({ type, message }) => console[type === "error" ? "error" : "log"]("scheduler:", message),
    },
  },
});

const electrobun = new Electrobun.Electroview({ rpc });

(window as any).electronAPI = {
  login: (credentials: { username: string; password: string }) => electrobun.rpc!.request.login(credentials),
};

