import { Utils } from "electrobun/bun";
import { mkdir, readFile, writeFile } from "node:fs/promises";
import { join } from "node:path";
import type { Credentials, Settings } from "../shared/rpc";

type State = {
  credentials?: Credentials;
  settings?: Settings;
};

const defaults: Settings = {
  autoStartEnabled: true,
  notificationsEnabled: true,
  autoEndEnabled: true,
  startHour: 9,
  startMinute: 0,
  endHour: 17,
  endMinute: 0,
};

export class AppStore {
  #filePath = join(Utils.paths.userData, "state.json");
  #state: State = {};

  async init() {
    await mkdir(Utils.paths.userData, { recursive: true });
    try {
      const raw = await readFile(this.#filePath, "utf-8");
      this.#state = JSON.parse(raw) as State;
    } catch {
      this.#state = {};
      await this.flush();
    }
  }

  getCredentials() {
    return this.#state.credentials;
  }

  async setCredentials(credentials: Credentials) {
    this.#state.credentials = credentials;
    await this.flush();
  }

  async clearCredentials() {
    delete this.#state.credentials;
    await this.flush();
  }

  getSettings(): Settings {
    return { ...defaults, ...(this.#state.settings ?? {}) };
  }

  async setSettings(settings: Settings) {
    this.#state.settings = { ...this.getSettings(), ...settings };
    await this.flush();
  }

  private async flush() {
    await writeFile(this.#filePath, JSON.stringify(this.#state, null, 2), "utf-8");
  }
}
