#!/usr/bin/env bash
# Builds Wplan Widget under the Apple ID of whoever runs it, installs it into
# /Applications and launches it.
#
#   scripts/build_and_run.sh              # Team ID from your "Apple Development" certificate
#   scripts/build_and_run.sh ABCDE12345   # explicit Team ID
#
# The Team ID is passed to xcodebuild as DEVELOPMENT_TEAM; the App Group
# (<TeamID>.com.wplanwidget.app) is derived from it at build time, so no files
# in the repository are changed.
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
PROJECT_DIR="$REPO_ROOT/WplanWidgetApp"
DERIVED_DATA="$PROJECT_DIR/DerivedData"
APP_NAME="WplanWidgetApp.app"
BUNDLE_ID="com.wplanwidget.app"
INSTALL_PATH="/Applications/$APP_NAME"

step() { printf '\n\033[1m==> %s\033[0m\n' "$*"; }
fail() { printf '\033[31mОшибка:\033[0m %s\n' "$*" >&2; exit 1; }

command -v xcodebuild >/dev/null || fail "не найден xcodebuild — установите Xcode из App Store."

team_id_of() {
  security find-certificate -c "$1" -p 2>/dev/null \
    | openssl x509 -noout -subject 2>/dev/null \
    | sed -n 's/.*OU *= *\([A-Z0-9]\{10\}\).*/\1/p'
}

resolve_team_id() {
  if [[ $# -gt 0 && -n "$1" ]]; then
    [[ "$1" =~ ^[A-Z0-9]{10}$ ]] || fail "Team ID должен состоять из 10 латинских букв/цифр: $1"
    echo "$1"
    return
  fi

  local names=()
  while IFS= read -r name; do names+=("$name"); done < <(
    security find-identity -v -p codesigning | sed -n 's/.*"\(Apple Development: [^"]*\)".*/\1/p' | sort -u
  )

  if [[ ${#names[@]} -eq 0 ]]; then
    fail "в Keychain нет сертификата «Apple Development».
  Xcode → Settings → Accounts → войдите своим Apple ID → Manage Certificates → «+» → Apple Development.
  Затем запустите скрипт снова."
  fi

  local chosen="${names[0]}"
  if [[ ${#names[@]} -gt 1 ]]; then
    echo "Найдено несколько сертификатов «Apple Development»:" >&2
    local i=1
    for name in "${names[@]}"; do
      echo "  $i) $name (Team ID $(team_id_of "$name"))" >&2
      i=$((i + 1))
    done
    local choice
    read -r -p "Какой использовать? [1-${#names[@]}] " choice </dev/tty
    [[ "$choice" =~ ^[0-9]+$ && "$choice" -ge 1 && "$choice" -le ${#names[@]} ]] || fail "нет такого варианта: $choice"
    chosen="${names[$((choice - 1))]}"
  fi

  local team
  team="$(team_id_of "$chosen")"
  [[ -n "$team" ]] || fail "не удалось прочитать Team ID из сертификата «$chosen»."
  echo "$team"
}

TEAM_ID="$(resolve_team_id "${1:-}")"
step "Team ID: $TEAM_ID (App Group $TEAM_ID.com.wplanwidget.app)"

XCODEGEN="$(command -v xcodegen || ls /opt/homebrew/bin/xcodegen /usr/local/bin/xcodegen 2>/dev/null | head -1 || true)"
if [[ -z "$XCODEGEN" ]]; then
  BREW="$(command -v brew || ls /opt/homebrew/bin/brew /usr/local/bin/brew 2>/dev/null | head -1 || true)"
  [[ -n "$BREW" ]] || fail "не найден xcodegen и Homebrew. Установите Homebrew (https://brew.sh) или xcodegen."
  step "Устанавливаю xcodegen через Homebrew"
  "$BREW" install xcodegen
  XCODEGEN="$(dirname "$BREW")/xcodegen"
fi

step "Генерирую Xcode-проект"
(cd "$PROJECT_DIR" && "$XCODEGEN" generate --quiet)

step "Собираю Release"
BUILD_LOG="$DERIVED_DATA/build.log"
mkdir -p "$DERIVED_DATA"
if ! xcodebuild \
  -project "$PROJECT_DIR/WplanWidgetApp.xcodeproj" \
  -scheme WplanWidgetApp \
  -configuration Release \
  -destination 'platform=macOS' \
  -derivedDataPath "$DERIVED_DATA" \
  DEVELOPMENT_TEAM="$TEAM_ID" \
  build >"$BUILD_LOG" 2>&1; then
  grep -E "error:" "$BUILD_LOG" | sort -u | head -20 >&2 || true
  fail "сборка не удалась, полный лог: $BUILD_LOG"
fi
BUILT_APP="$DERIVED_DATA/Build/Products/Release/$APP_NAME"
codesign --verify --deep --strict "$BUILT_APP" || fail "у собранного приложения невалидная подпись."

if pgrep -f "$APP_NAME/Contents/MacOS/" >/dev/null; then
  step "Закрываю запущенную копию"
  osascript -e "quit app id \"$BUNDLE_ID\"" >/dev/null 2>&1 || true
  for _ in {1..20}; do
    pgrep -f "$APP_NAME/Contents/MacOS/" >/dev/null || break
    sleep 0.5
  done
  pgrep -f "$APP_NAME/Contents/MacOS/" >/dev/null && fail "приложение не закрылось — закройте его вручную и запустите скрипт снова."
fi

step "Устанавливаю в $INSTALL_PATH"
rm -rf "$INSTALL_PATH"
ditto "$BUILT_APP" "$INSTALL_PATH"
# The widget extension process outlives a reinstall and keeps serving the old
# build; macOS relaunches it from the new bundle on demand.
pkill -f "WplanWidgetExtension.appex/Contents/MacOS/" 2>/dev/null || true

step "Запускаю"
open "$INSTALL_PATH"

VERSION="$(defaults read "$INSTALL_PATH/Contents/Info" CFBundleShortVersionString) ($(defaults read "$INSTALL_PATH/Contents/Info" CFBundleVersion))"
CERT_END="$(security find-certificate -a -c "Apple Development" -p 2>/dev/null | openssl x509 -noout -enddate 2>/dev/null | cut -d= -f2 || true)"
printf '\nГотово: Wplan %s запущен из %s.\n' "$VERSION" "$INSTALL_PATH"
[[ -n "$CERT_END" ]] && printf 'Сертификат подписи действует до %s — после этого просто запустите скрипт снова.\n' "$CERT_END"
