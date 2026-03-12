import type { RPCSchema } from "electrobun/bun";

export type Credentials = {
  username: string;
  password: string;
};

export type Settings = {
  autoStartEnabled?: boolean;
  notificationsEnabled?: boolean;
  autoEndEnabled?: boolean;
  startHour?: number;
  startMinute?: number;
  endHour?: number;
  endMinute?: number;
};

export type WplanRPC = {
  bun: RPCSchema<{
    requests: {
      login: { params: Credentials; response: { success: boolean; message?: string } };
      getSettings: { params: {}; response: Settings };
      saveSettings: { params: Settings; response: { success: boolean } };
      getButtonState: { params: {}; response: string | null };
      getNotificationPermissionStatus: { params: {}; response: boolean };
      getSessionState: {
        params: {};
        response: { hasCredentials: boolean; isLoggedIn: boolean; url: string };
      };
    };
    messages: {
      openSettings: {};
      logout: {};
      reloadWplan: {};
      typeInDebugger: { text: string };
      closeSettings: {};
    };
  }>;
  webview: RPCSchema<{
    requests: {
      ping: { params: {}; response: { ok: true } };
    };
    messages: {
      schedulerEvent: { type: "info" | "error"; message: string };
    };
  }>;
};
