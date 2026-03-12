# План миграции `ruslan-gift` (Wplan Auto): Electron → ElectroBun

## 1) Цель и контекст

Текущий проект — desktop-приложение **Wplan Auto** на Electron (Electron Forge), которое:
- хранит учетные данные локально;
- открывает `https://wplan.office.lan/` в `BrowserView`;
- выполняет авто-логин через внедрение JS;
- по расписанию нажимает кнопку `#startEndWorkButton` (начало/завершение рабочего дня);
- показывает нативные уведомления;
- имеет окна login/main/settings и IPC-мост через preload.

Цель миграции: перевести приложение на ElectroBun с минимальными рисками регрессий, сохранив функциональное поведение и подготовив базу для более легкого/быстрого runtime и обновлений.

---

## 2) Что изучено по ElectroBun (концентрированно)

Источник: https://blackboard.sh/electrobun/docs/

### 2.1 Архитектура
- Приложение ElectroBun — это Bun-приложение, запускаемое через нативный launcher.
- Main-логика на TypeScript/Bun (импорт из `electrobun/bun`).
- UI живет в webview (системные движки по умолчанию: WKWebView/WebView2/WebKitGTK; опционально CEF).
- Основные сущности: `BrowserWindow`, `BrowserView`, `ApplicationMenu`, `Tray`, `Updater`, events.
- Межпроцессное взаимодействие не через `ipcMain/ipcRenderer`, а через typed RPC (`BrowserView.defineRPC` + `Electroview.defineRPC`).

### 2.2 Инициализация и запуск
- Инициализация: `bunx electrobun init`.
- Типовой workflow:
  - `bun install`
  - dev запуск: `electrobun dev` (или `bun run dev`)
  - watch: `electrobun dev --watch`
  - отдельный запуск готового dev-билда: `electrobun run`.
- Конфигурация в `electrobun.config.ts`.

### 2.3 Сборка, релиз, дистрибуция
- Сборка: `electrobun build --env=dev|canary|stable`.
- Non-dev билды генерируют `artifacts/` с плоскими именами файлов (`{channel}-{os}-{arch}-...`).
- Для обновлений нужен только static host (`release.baseUrl`, например S3/R2/GitHub Releases).
- Обновления — встроенный updater + BSDIFF-патчи; fallback на полный bundle.
- macOS: поддерживаются codesign/notarize (через env и настройки в `build.mac`).

### 2.4 Ограничения / нюансы совместимости
- Электрон-API не является drop-in полностью: нужна адаптация `ipc*`, preload-моста, части window/webview API, автопдейта.
- Linux: системный WebKitGTK ограничен для сложного layer/masking; для стабильности рекомендуют `bundleCEF: true`.
- GitHub Releases + canary: `/releases/latest/download` не резолвит prerelease (ограничение автообновлений canary).
- Генерируется один patch на билд (предыдущая версия → текущая); более старые клиенты могут скачать full bundle.
- Deep links URL schemes полноценно документированы для macOS; Windows/Linux — not yet.

---

## 3) Анализ текущего проекта (до миграции)

Код перемещен в `old/` (см. структуру ниже).

### 3.1 Текущая структура
- `old/src/main/index.js` — bootstrap app, выбор login/main window, загрузка scheduler/IPC.
- `old/src/main/windows.js` — создание `BrowserWindow`, `BrowserView`, settings/login окон.
- `old/src/main/ipcHandlers.js` — `ipcMain.handle/on` каналы (login/settings/logout/reload/debugger/notifications).
- `old/src/main/scheduler.js` — планирование start/end кликов, проверка состояния кнопки, executeJavaScript.
- `old/src/main/sessionActivity.js` — keep-alive раз в 3 часа.
- `old/src/main/notifications.js` — нативные уведомления.
- `old/src/preload/*.js` — API-мост в renderer через `contextBridge`.
- `old/src/assets/html/*`, `old/src/assets/css/*` — UI login/settings/menu/main container.
- `old/forge.config.js` + `old/package.json` — Electron Forge packaging/publishing.

### 3.2 Технологии/зависимости
- Electron 39 + Electron Forge makers/publishers.
- `electron-store` (настройки, credentials).
- `update-electron-app`.
- `electron-squirrel-startup`.

### 3.3 Риски миграции именно для этого приложения
1. **IPC архитектура**: переход с `ipcMain/ipcRenderer` на RPC-схемы.
2. **Авто-логин и DOM-автоматизация**: перенос `executeJavaScript` в API ElectroBun BrowserView без потери таймингов.
3. **Persisted storage**: `electron-store` может быть заменен (JSON/SQLite/адаптер) — риск несовместимости формата.
4. **Автообновления**: уход с `update-electron-app` к ElectroBun Updater и новой release-пайплайн-схеме.
5. **Кроссплатформенность webview engine**: поведение DOM/рендера может отличаться между WKWebView/WebView2/WebKitGTK.
6. **Публикация**: полный пересмотр CI/CD, артефактов и naming.

---

## 4) Целевая архитектура (после миграции)

## 4.1 Целевая структура репозитория
- `old/` — неизменяемый snapshot текущего Electron-проекта (для отката/сравнения).
- `new/` — ElectroBun проект:
  - `new/src/bun/index.ts` — main процесс (создание окон, scheduler orchestration, updater).
  - `new/src/shared/rpc.ts` — общие RPC типы.
  - `new/src/views/login/*`, `new/src/views/main/*`, `new/src/views/settings/*` — UI.
  - `new/src/core/`:
    - `store.ts` (персистентный слой),
    - `scheduler.ts`,
    - `session-activity.ts`,
    - `notifications.ts`,
    - `auth.ts`.
  - `new/electrobun.config.ts`.
  - `new/package.json`.

### 4.2 Компонентная модель
- Main/Bun создает `BrowserWindow` и управляет `BrowserView`.
- Renderer получает API через Electroview RPC.
- Логика scheduler/автоклика остается в main + webview JS execution.
- Настройки/учетка сохраняются в единый storage-адаптер (не завязанный на Electron API).
- Обновления через `Updater` + `release.baseUrl`.

---

## 5) Карта соответствия модулей/файлов (Electron → ElectroBun)

| Electron (old) | Назначение | ElectroBun (new, target) | Комментарий |
|---|---|---|---|
| `old/src/main/index.js` | app lifecycle/entry | `new/src/bun/index.ts` | `app.whenReady` → events/init ElectroBun |
| `old/src/main/windows.js` | окна и BrowserView | `new/src/bun/windows.ts` | `BrowserWindow`/`webview` API совместимы концептуально |
| `old/src/main/ipcHandlers.js` | IPC каналы | `new/src/shared/rpc.ts` + handler wiring в bun/view | migrate на typed RPC |
| `old/src/main/scheduler.js` | таймеры и автоклик | `new/src/core/scheduler.ts` | сохранить алгоритм и тайминги |
| `old/src/main/sessionActivity.js` | keep-alive | `new/src/core/session-activity.ts` | аналогичный interval + executeJavascript |
| `old/src/main/notifications.js` | нативные уведомления | `new/src/core/notifications.ts` | использовать API уведомлений ElectroBun |
| `old/src/preload/*.js` | bridge в renderer | `new/src/views/*/index.ts` + Electroview RPC | preload-концепт заменяется RPC/browser API |
| `old/src/assets/html/*` | UI шаблоны | `new/src/views/*/*.html` (copy в views://) | можно перенести почти без изменений |
| `old/src/assets/css/*` | стили | `new/src/views/*/*.css` | без существенных изменений |
| `old/forge.config.js` | packaging/release | `new/electrobun.config.ts` | новая модель билдов/артефактов |
| `update-electron-app` | автоапдейт | `Updater` (electrobun/bun) | нужна интеграция с baseUrl/artifacts |
| `electron-store` | storage | `new/src/core/store.ts` | обертка над JSON/SQLite/Bun APIs |

---

## 6) Пошаговый план миграции (практический)

### Фаза 0 — Подготовка (выполнено в этой задаче)
1. Создана ветка миграции.
2. Созданы папки `old/`, `new/`.
3. Текущий проект перемещен в `old/` через `git mv`.
4. Подготовлен подробный migration-док.

### Фаза 1 — Каркас ElectroBun
1. В `new/` создать проект (`bunx electrobun init` или вручную минимальный шаблон).
2. Создать `electrobun.config.ts`:
   - app metadata (name/id/version),
   - `build.bun.entrypoint`,
   - `build.views` + `copy` для html/css,
   - `release.baseUrl` (заглушка/реальный URL).
3. Настроить scripts: `dev`, `dev:watch`, `build:canary`, `build:stable`.

### Фаза 2 — Окна и навигация
1. Перенести логику login/main/settings окон.
2. Восстановить загрузку `https://wplan.office.lan/` в webview.
3. Проверить bounds/menu bar layout.

### Фаза 3 — IPC → RPC
1. Описать `RPCSchema` для каналов:
   - login-data, get/save-settings, get-button-state, logout, reload, debugger typing, notification status.
2. Реализовать bun handlers + browser handlers.
3. Убрать preload-зависимости.

### Фаза 4 — Scheduler и дом-автоматизация
1. Перенести `waitForElement`, `getButtonState`, `clickStartEndButton`.
2. Проверить тайминг планировщика при старте и на границах минут.
3. Перенести keep-alive.

### Фаза 5 — Storage/Settings/Auth
1. Реализовать storage adapter.
2. Мигрировать формат настроек/credentials (с fallback на старый формат при наличии).
3. Тестировать login/logout/settings cycle.

### Фаза 6 — Notifications + Updater
1. Подключить нативные уведомления через API ElectroBun.
2. Подключить `Updater.checkForUpdate/downloadUpdate/applyUpdate`.
3. Настроить `artifacts` upload flow и `baseUrl`.

### Фаза 7 — Build/Release/CI
1. Подготовить CI matrix под mac/win/linux.
2. Настроить codesign/notarization (mac) через secrets.
3. Выпустить canary, затем stable.

---

## 7) Риски и меры снижения

1. **Регрессия таймингов автоклика**
   - Мера: интеграционные тесты сценариев start/end, логирование в canary.
2. **Изменение поведения webview engine**
   - Мера: smoke-тесты на каждой ОС; при Linux рассмотреть `bundleCEF: true`.
3. **Проблемы с автообновлением**
   - Мера: staged rollout, проверка update.json/patch chain, fallback на full bundle.
4. **Несовместимость хранения настроек**
   - Мера: versioned storage schema + мигратор + backup файла настроек.
5. **Нарушение UX входа/выхода**
   - Мера: e2e чек-лист (login→main→settings→logout→relogin).

---

## 8) Критерии готовности (Definition of Done)

- [ ] Функциональный паритет по ключевым user flows.
- [ ] Scheduler корректно запускает start/end и не делает ложные клики.
- [ ] Уведомления работают и управляются настройкой.
- [ ] Настройки/учетка сохраняются и читаются после перезапуска.
- [ ] Сборка `canary` и `stable` успешна на целевых ОС.
- [ ] Артефакты опубликованы, updater корректно видит и применяет обновление.
- [ ] Подготовлена документация эксплуатации и rollback.

---

## 9) Rollback-план

1. Сохраняем `old/` как эталон Electron-версии.
2. До production cutover поддерживаем отдельный релизный канал старого приложения.
3. В случае критической регрессии:
   - остановить rollout ElectroBun;
   - вернуть пользователей на последний stable Electron билд;
   - сохранить логи и diff проблемного релиза;
   - выпуск hotfix/patch в canary перед повторным rollout.
4. На уровне репозитория откат тривиален: вся исходная версия физически присутствует в `old/` с сохраненной git-историей перемещений.

---

## 10) Чек-лист запуска и валидации

### Dev (будущий ElectroBun проект в `new/`)
```bash
cd new
bun install
bun run dev
# или
electrobun dev --watch
```

### Build
```bash
cd new
bun run build:canary
bun run build:stable
```

### Smoke functional checks
1. Login окно открывается, учетные данные сохраняются.
2. После повторного запуска выполняется авто-вход.
3. Main view загружает `wplan.office.lan`.
4. Кнопка start/end корректно определяется и кликается scheduler’ом.
5. Settings сохраняются и применяются сразу.
6. Logout чистит credentials и возвращает login.
7. Нотификации показываются только при `notificationsEnabled=true`.
8. Проверка апдейта (`Updater.checkForUpdate`) отрабатывает без ошибок.

---

## 11) Команды для проверки текущего подготовительного коммита

```bash
# из корня репозитория
cd /root/.openclaw/workspace/ruslan-gift

git checkout chore/electrobun-migration-plan
git status

tree -L 2
# ожидаемо: old/, new/, docs/migration-electron-to-electrobun.md
```

---

## 12) Примечания по точности и открытым вопросам

1. `web_search` (Brave API) в среде недоступен (нет API key), поэтому анализ выполнен через прямой fetch страниц документации ElectroBun.
2. Для фактического этапа код-миграции нужно подтвердить:
   - целевые платформы релиза (минимум mac/win/linux?);
   - предпочтение renderer на Linux (`native` vs `cef`);
   - целевой хост артефактов и стратегия каналов (`canary/stable`).
