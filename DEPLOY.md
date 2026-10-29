# Деплой Wplan Widget

## Как устроено

`.github/workflows/wplan-widget-release.yml` — ручной workflow (`workflow_dispatch`).
Запускается из вкладки **Actions** на GitHub, на любой ветке (в том числе
на `widget`, пока `main` не обновлён). По кнопке:

1. Собирает `WplanCore` + `WplanWidgetApp` через `xcodegen` + `xcodebuild archive`.
2. Подписывает тем же сертификатом «Apple Development», что и локально, —
   импортирует его во временный keychain. Подпись **Manual, без
   провижининг-профиля** (см. `project.yml`): App Group имеет вид
   `<TeamID>.com.wplanwidget.app`, а такие группы macOS разрешает по самой
   подписи, профиль им не нужен. Поэтому у сборки нет 7-дневного срока
   бесплатного профиля — живёт, пока действует сертификат (год).
3. Берёт подписанный `.app` прямо из архива и пакует в `.dmg`
   (`scripts/build_dmg.sh`).
4. Публикует GitHub Release с этим DMG, тегом (тем, что ты введёшь при
   запуске) и текстом из секции `[Unreleased]` в `CHANGELOG.md`.

**Важно:** это не даёт нотаризацию. Скачавший DMG человек всё равно
увидит блокировку Gatekeeper (см. ниже, «Что получит скачавший»).

## Разовая настройка секретов (нужно сделать один раз, руками)

Нужны 2 секрета в **Settings → Secrets and variables → Actions** этого
репозитория — сертификат и пароль к нему. Провижининг-профили не нужны.
Если от старой схемы остались секреты `MACOS_PROFILE_APP_BASE64` и
`MACOS_PROFILE_WIDGET_BASE64` — их можно удалить.

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

### 2. Добавление секретов на GitHub

Через веб-интерфейс: **Settings → Secrets and variables → Actions → New
repository secret** — вставить то, что скопировано в буфер, под нужным
именем. Либо, если установлен `gh` (`brew install gh && gh auth login`):

```bash
gh secret set MACOS_CERT_P12_BASE64 < <(base64 -i ~/Desktop/wplan-cert.p12)
gh secret set MACOS_CERT_PASSWORD -b "придумай-пароль-для-экспорта"
```

`GITHUB_TOKEN` для создания релиза ничего настраивать не нужно — GitHub
подставляет его сам, workflow уже просит `permissions: contents: write`.

## Как выпустить релиз

1. Обнови `CHANGELOG.md` — допиши в `[Unreleased]`, что изменилось.
2. **Actions → Release → Run workflow** — выбери ветку, впиши тег (например
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

## Если сборка падает на этапе Archive

Скорее всего дело в версии Xcode на раннере `macos-latest` — она может
не совпадать с той, что стоит у тебя локально (SDK новее/старше). Проверить
можно через отдельный шаг `xcodebuild -version` в начале workflow, а зафиксировать
конкретную версию — либо явным `runs-on: macos-15` (конкретный образ вместо
`latest`), либо шагом `sudo xcode-select -s /Applications/Xcode_16.x.app`,
если на раннере доступно несколько версий Xcode одновременно (обычно да,
см. `ls /Applications | grep Xcode`).

## Срок жизни сборки

Провижининг-профиля в сборке нет, поэтому недельного срока бесплатного
аккаунта тоже нет. Ограничение одно — сам сертификат «Apple Development»
действует год. Проверить дату:
```bash
security find-certificate -a -c "Apple Development" -p | openssl x509 -noout -enddate
```
Когда срок подойдёт к концу — Xcode → Settings → Accounts → Manage
Certificates выпустит новый, после чего пересобери приложение
(`scripts/build_and_run.sh`) и обнови секрет `MACOS_CERT_P12_BASE64`.

## Когда появится платный аккаунт

Замени сертификат «Apple Development» на «Developer ID Application» (те же
секреты, переэкспортированные под новый сертификат, и `CODE_SIGN_IDENTITY`
в `project.yml`), и добавь в workflow после сборки DMG два шага:
```bash
xcrun notarytool submit "$RUNNER_TEMP/Wplan-${{ inputs.version }}.dmg" \
  --apple-id ... --team-id 8W787APH48 --password ... --wait
xcrun stapler staple "$RUNNER_TEMP/Wplan-${{ inputs.version }}.dmg"
```
(`--password` — app-specific-password, отдельный секрет). После этого DMG
открывается у любого без единого предупреждения.
