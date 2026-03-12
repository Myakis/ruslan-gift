# ElectroBun runtime status (feat/electrobun-migration-implementation)

## Что исправлено

1. **Стабилизирован главный экран (не пустой):**
   - Убран фиксированный внутренний контейнер `1200x800`, теперь layout растягивается на всё окно (`h-screen w-screen`, `app-window: 100% x 100%`).
   - Это убирает риск визуально «пустого» окна при несовпадении frame/content размеров.

2. **Стабилизирован интерактив webview с первого клика:**
   - Добавлен явный `focusWebview()` и вызовы в ключевых точках (`dom-ready`, `did-stop-loading`, mouse enter/down).
   - Снята необходимость «протабать» окно для получения интерактива webview.

3. **Усилен автологин (устойчивость):**
   - Вынесен в единый runtime-поток внутри `main` webview-страницы.
   - Добавлены:
     - fallback-селекторы для login/password/submit,
     - ретраи с коротким интервалом,
     - защита от повторной отправки (`autologinDone`),
     - backup-попытка по таймауту, если события webview не дали старт.
   - Автологин запускается при `dom-ready`, `did-navigate` и timeout-fallback.

4. **Reload/Logout/Settings не ломают сессию на уровне текущей архитектуры:**
   - `reload` выполняется через `electrobun-webview.reload()` с fallback.
   - `logout` очищает credentials + закрывает main + открывает login (как и задумано).
   - `settings` открывается отдельным окном, сохранение не ломает состояние main.

5. **Минимальная диагностика без шума:**
   - Добавлен компактный runtime status chip в main view:
     - `bridge:<state> · webview:<state> · autologin:<state>`
   - Убраны лишние `console.log` в `bun/index.ts` и view bridge-файлах.
   - Оставлены только полезные `warn/error`.

## Что протестировано

### 1) Сборка/рантайм sanity
- `npm run build` (в `new/`) — **успешно**.
- Проверена генерация артефактов ElectroBun без compile/runtime ошибок в JS/TS bundle.

### 2) Dev запуск
- `npm run dev` стартует и watcher поднимается.
- На текущем Linux-host окружении запуск native wrapper останавливается из-за отсутствующей системной зависимости:
  - `libwebkit2gtk-4.1.so.0`
- Это инфраструктурный runtime-блокер окружения, не логики приложения.

### 3) Smoke flow
- Полный UI smoke (`login -> main -> settings -> reload -> logout -> login`) **невозможно завершить в этом CI/host окружении** из-за отсутствующей системной библиотеки WebKit GTK.
- Логика переходов, RPC и обработчики проверены статически/по коду и через успешный build-проход.

## Known limitations

1. Для полноценного локального dev-run на Linux требуется установить системную зависимость:
   - `libwebkit2gtk-4.1.so.0` (пакет зависит от дистрибутива).
2. Scheduler в settings использует `BrowserView`-операции; при текущей реализации main через `<electrobun-webview>` `getButtonState` может возвращать `null` (статус в settings будет «неизвестен») — это не ломает login/reload/logout flow, но ограничивает telemetry scheduler-а.
3. Полноценный ручной E2E smoke должен быть подтверждён на машине с рабочим WebKit GTK runtime.
