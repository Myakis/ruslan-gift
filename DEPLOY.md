# Деплой Wplan Widget

## Как устроено

`.github/workflows/wplan-widget-release.yml` — ручной workflow (`workflow_dispatch`).
Запускается из вкладки **Actions** на GitHub, на любой ветке (в том числе
на `widget`, пока `main` не обновлён). По кнопке:

1. Собирает `WplanCore` + `WplanWidgetApp` через `xcodegen` + `xcodebuild archive`.
2. Подписывает тем же сертификатом «Apple Development», что и локально —
   импортирует его во временный keychain и кладёт уже готовые (сгенерированные
   локальным Xcode) провижининг-профили в нужную папку. Подпись остаётся
   **Automatic** (как в `project.yml`) — Manual тут не вариант: профили от
   бесплатного аккаунта всегда `IsXcodeManaged: true`, и Xcode отказывается
   использовать такие в Manual-режиме, даже если имя совпадает. Проверено
   локально: Automatic находит совпадающие сертификат+профиль без обращения
   в сеть, если они уже присутствуют — то есть в CI работает точно так же.
3. Экспортирует `.app`, пакует в `.dmg` (`scripts/build_dmg.sh`).
4. Публикует GitHub Release с этим DMG, тегом (тем, что ты введёшь при
   запуске) и текстом из секции `[Unreleased]` в `CHANGELOG.md`.

**Важно:** это не даёт нотаризацию. Скачавший DMG человек всё равно
увидит блокировку Gatekeeper (см. ниже, «Что получит скачавший»).

## Разовая настройка секретов (нужно сделать один раз, руками)

Нужны 4 секрета в **Settings → Secrets and variables → Actions** этого
репозитория. У тебя уже есть готовый сертификат и оба провижининг-профиля —
их просто нужно экспортировать и закодировать в base64.

### 1. Сертификат (.p12)

```bash
security export -k login.keychain-db \
  -t identities \
  -f pkcs12 \
  -P "придумай-пароль-для-экспорта" \
  -o ~/Desktop/wplan-cert.p12
```
Появится диалог Keychain Access с запросом разрешить экспорт приватного
ключа — подтверди. Если команда предложит выбрать identity, укажи
`Apple Development: myakishevandrey@gmail.com (6JJ5943Q95)`.

```bash
base64 -i ~/Desktop/wplan-cert.p12 | pbcopy
```
Вставь это в секрет **`MACOS_CERT_P12_BASE64`**.

Секрет **`MACOS_CERT_PASSWORD`** — тот самый пароль, что придумал выше.

Удали `~/Desktop/wplan-cert.p12` после того, как секрет сохранён — он тебе
больше не нужен на диске.

### 2. Провижининг-профили

Уже сгенерированы локальным Xcode, лежат в
`~/Library/Developer/Xcode/UserData/Provisioning Profiles/`:

```bash
base64 -i ~/Library/Developer/Xcode/UserData/Provisioning\ Profiles/e892d45f-082c-425a-a813-b29a02ed94ef.provisionprofile | pbcopy
```
→ секрет **`MACOS_PROFILE_APP_BASE64`** (профиль для `com.wplanwidget.app`).

```bash
base64 -i ~/Library/Developer/Xcode/UserData/Provisioning\ Profiles/722b5882-bb79-4cf7-b67e-22fc5560f5e5.provisionprofile | pbcopy
```
→ секрет **`MACOS_PROFILE_WIDGET_BASE64`** (профиль для
`com.wplanwidget.app.widget`).

Если когда-нибудь пересоздашь эти профили в Xcode (новый Team, новый
bundle ID и т.п.) — имена файлов изменятся, найди актуальные через:
```bash
for f in ~/Library/Developer/Xcode/UserData/Provisioning\ Profiles/*; do
  echo "$f:"; security cms -D -i "$f" | plutil -extract Name raw -o - -
done
```

### 3. Добавление секретов на GitHub

Через веб-интерфейс: **Settings → Secrets and variables → Actions → New
repository secret** — вставить то, что скопировано в буфер, под нужным
именем. Либо, если установлен `gh` (`brew install gh && gh auth login`):

```bash
gh secret set MACOS_CERT_P12_BASE64 < <(base64 -i ~/Desktop/wplan-cert.p12)
gh secret set MACOS_CERT_PASSWORD -b "придумай-пароль-для-экспорта"
gh secret set MACOS_PROFILE_APP_BASE64 < <(base64 -i ~/Library/Developer/Xcode/UserData/Provisioning\ Profiles/e892d45f-082c-425a-a813-b29a02ed94ef.provisionprofile)
gh secret set MACOS_PROFILE_WIDGET_BASE64 < <(base64 -i ~/Library/Developer/Xcode/UserData/Provisioning\ Profiles/722b5882-bb79-4cf7-b67e-22fc5560f5e5.provisionprofile)
```

`GITHUB_TOKEN` для создания релиза ничего настраивать не нужно — GitHub
подставляет его сам, workflow уже просит `permissions: contents: write`.

## Как выпустить релиз

1. Обнови `CHANGELOG.md` — допиши в `[Unreleased]`, что изменилось.
2. **Actions → Wplan Widget Release → Run workflow** — выбери ветку, впиши тег (например
   `v1.3.0-widget`).
3. Дождись зелёной галочки — в **Releases** появится тег с приложенным
   `Wplan-<тег>.dmg` и текстом из `[Unreleased]`.
4. Переименуй `[Unreleased]` в CHANGELOG.md в `[<тег>] — <дата>` и заведи
   новый пустой `[Unreleased]` сверху, закоммить.

## Что получит скачавший DMG

Открыть образ и перетащить `.app` в Applications — можно. Но при первом
запуске macOS заблокирует его (Gatekeeper): сертификат «Apple Development»
не нотаризован. Обход:

```bash
xattr -cr /Applications/WplanWidgetApp.app
```
— затем правый клик по иконке → «Открыть». Это стоит явно написать в
описании релиза, пока нет платного Apple Developer Program.

## Если сборка падает на этапе Archive/Export

Скорее всего дело в версии Xcode на раннере `macos-latest` — она может
не совпадать с той, что стоит у тебя локально (SDK новее/старше). Проверить
можно через отдельный шаг `xcodebuild -version` в начале workflow, а зафиксировать
конкретную версию — либо явным `runs-on: macos-15` (конкретный образ вместо
`latest`), либо шагом `sudo xcode-select -s /Applications/Xcode_16.x.app`,
если на раннере доступно несколько версий Xcode одновременно (обычно да,
см. `ls /Applications | grep Xcode`).

## Когда появится платный аккаунт

Замени сертификат «Apple Development» на «Developer ID Application» (те же
секреты, переэкспортированные под новый сертификат), и добавь в workflow
после экспорта два шага:
```bash
xcrun notarytool submit "$RUNNER_TEMP/Wplan-${{ inputs.version }}.dmg" \
  --apple-id ... --team-id 8W787APH48 --password ... --wait
xcrun stapler staple "$RUNNER_TEMP/Wplan-${{ inputs.version }}.dmg"
```
(`--password` — app-specific-password, отдельный секрет). После этого DMG
открывается у любого без единого предупреждения.
