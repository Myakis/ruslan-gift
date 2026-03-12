import type { ElectrobunConfig } from "electrobun";

export default {
  app: {
    name: "wplan-auto",
    identifier: "com.myakis.wplan-auto",
    version: "1.1.0",
  },
  build: {
    bun: {
      entrypoint: "src/bun/index.ts",
    },
    views: {
      login: { entrypoint: "src/views/login/index.ts" },
      main: { entrypoint: "src/views/main/index.ts" },
      settings: { entrypoint: "src/views/settings/index.ts" },
    },
    copy: {
      "src/views/login/index.html": "views/login/index.html",
      "src/views/main/index.html": "views/main/index.html",
      "src/views/settings/index.html": "views/settings/index.html",
      "src/views/logo-wplan.icns": "views/assets/logo-wplan.icns",
    },
    mac: { bundleCEF: false },
    win: { bundleCEF: false },
  },
  release: {
    baseUrl: "https://example.com/wplan-auto-artifacts"
  }
} satisfies ElectrobunConfig;
