#!/usr/bin/env bash
# Glass Arc for Zen Browser (Linux): installs Zen if it is missing, then puts
# the Glass Arc mod, its settings and the Edit Theme style switch into your
# Zen profile.
#
#   curl -fsSL https://raw.githubusercontent.com/OlehDo27/zen-glass-arc/main/install.sh | bash
#
# Options: --uninstall, --yes (no questions), --profile DIR, --no-loader
# (skip the style switch in Edit Theme, which needs a file in Zen's folder).
set -euo pipefail

REPO="${GLASSARC_REPO:-OlehDo27/zen-glass-arc}"
BRANCH="${GLASSARC_BRANCH:-main}"
FLATPAK_ID=app.zen_browser.zen

ACTION=install YES=0 PROFILE="" LOADER=1
while [[ $# -gt 0 ]]; do
  case $1 in
    --uninstall) ACTION=uninstall ;;
    --yes | -y) YES=1 ;;
    --profile) PROFILE=$2; shift ;;
    --no-loader) LOADER=0 ;;
    *) echo "неизвестный параметр: $1" >&2; exit 2 ;;
  esac
  shift
done

say() { printf '\033[1;35m::\033[0m %s\n' "$*"; }
warn() { printf '\033[1;33m!!\033[0m %s\n' "$*"; }
die() { printf '\033[1;31m!!\033[0m %s\n' "$*" >&2; exit 1; }
ask() {
  [[ $YES == 1 ]] && return 0
  local answer
  read -r -p "$1 [Y/n] " answer </dev/tty || return 1
  [[ -z $answer || $answer == [yYдД]* ]]
}

command -v python3 >/dev/null || die "Нужен python3"

# ---- repo files: next to this script, or downloaded --------------------------
SRC=""
if [[ -n ${BASH_SOURCE[0]:-} && -f ${BASH_SOURCE[0]} ]]; then
  SRC=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
fi
if [[ ! -f $SRC/mod/local-glass-arc/chrome.css ]]; then
  SRC=$(mktemp -d)
  trap 'rm -rf "$SRC"' EXIT
  say "Скачиваю Glass Arc ($REPO)"
  curl -fsSL "https://github.com/$REPO/archive/refs/heads/$BRANCH.tar.gz" | tar -xz -C "$SRC" --strip-components=1
fi

# ---- Zen itself --------------------------------------------------------------
FLATPAK=0
zen_installed() {
  command -v zen-browser >/dev/null || command -v zen >/dev/null || [[ -x $HOME/.tarball-installations/zen/zen ]] && return 0
  command -v flatpak >/dev/null && flatpak info "$FLATPAK_ID" >/dev/null 2>&1 && FLATPAK=1 && return 0
  return 1
}

zen_installed || true
if [[ $ACTION == install ]] && ! zen_installed; then
  say "Zen Browser не установлен"
  helper=$(command -v paru || command -v yay || true)
  if [[ -n $helper ]] && ask "Установить zen-browser-bin из AUR через $(basename "$helper")?"; then
    "$helper" -S --needed zen-browser-bin
  elif command -v flatpak >/dev/null && ask "Установить Zen из Flathub?"; then
    flatpak install -y flathub "$FLATPAK_ID"
    FLATPAK=1
  elif ask "Установить Zen официальным скриптом (в ~/.tarball-installations/zen)?"; then
    bash <(curl -fsSL https://updates.zen-browser.app/install.sh)
  else
    die "Сначала установите Zen Browser: https://zen-browser.app/download"
  fi
  zen_installed || die "Zen так и не найден"
fi

if [[ $FLATPAK == 1 ]]; then
  ZEN_CMD=(flatpak run "$FLATPAK_ID")
elif command -v zen-browser >/dev/null; then
  ZEN_CMD=(zen-browser)
elif command -v zen >/dev/null; then
  ZEN_CMD=(zen)
else
  ZEN_CMD=("$HOME/.tarball-installations/zen/zen")
fi

# ---- the profile -------------------------------------------------------------
# Older installs keep profiles in ~/.zen, newer ones in ~/.config/zen
if [[ $FLATPAK == 1 ]]; then
  ZEN_HOMES=("$HOME/.var/app/$FLATPAK_ID/.zen" "$HOME/.var/app/$FLATPAK_ID/config/zen")
else
  ZEN_HOMES=("$HOME/.zen" "${XDG_CONFIG_HOME:-$HOME/.config}/zen")
fi

default_profile() {
  local home
  for home in "${ZEN_HOMES[@]}"; do
    if [[ -f $home/profiles.ini ]]; then
      ZEN_HOME=$home
      break
    fi
  done
  [[ -n ${ZEN_HOME:-} ]] || return 1
  python3 -I - "$ZEN_HOME" <<'PY'
import configparser, os, sys
home = sys.argv[1]
ini = configparser.RawConfigParser()
ini.optionxform = str
ini.read(os.path.join(home, "profiles.ini"))
path = None
for s in ini.sections():  # the profile Zen actually opens
    if s.startswith("Install") and ini.has_option(s, "Default"):
        path = ini.get(s, "Default")
        break
if path is None:
    for s in ini.sections():
        if ini.has_option(s, "Path") and ini.get(s, "Default", fallback="0") == "1":
            path = ini.get(s, "Path")
if path is None:
    sys.exit(1)
print(path if os.path.isabs(path) else os.path.join(home, path))
PY
}

if [[ -z $PROFILE ]]; then
  if ! PROFILE=$(default_profile); then
    say "Создаю профиль Zen (Zen откроется в фоне на несколько секунд)"
    shot=$(mktemp --suffix=.png)
    timeout 90 "${ZEN_CMD[@]}" --headless --no-remote --screenshot "$shot" about:blank >/dev/null 2>&1 || true
    rm -f "$shot"
    PROFILE=$(default_profile) || die "Профиль Zen не найден (${ZEN_HOMES[*]})"
  fi
fi
[[ -d $PROFILE ]] || die "Папка профиля не найдена: $PROFILE"
say "Профиль: $PROFILE"

# ---- Zen has to be closed: it rewrites prefs.js when it quits -----------------
profile_in_use() {
  if [[ $FLATPAK == 1 ]]; then  # the lock holds a pid from the sandbox
    pgrep -x zen-bin >/dev/null
    return
  fi
  local lock
  lock=$(readlink "$PROFILE/lock" 2>/dev/null) || return 1
  kill -0 "${lock##*+}" 2>/dev/null
}
if profile_in_use; then
  warn "Закройте Zen Browser (Ctrl+Q), жду..."
  while profile_in_use; do sleep 1; done
  sleep 1
fi

python3 -I "$SRC/tools/setup_profile.py" "$ACTION" "$PROFILE" "$SRC" linux

# ---- loader for the style switch in Edit Theme (a file in Zen's folder) --------
zen_dir() {
  local candidate
  for candidate in \
    "$(dirname "$(readlink -f "$(command -v zen-browser 2>/dev/null || echo /nonexistent)")")" \
    "$(sed -n 's/^exec \(.*\)\/zen-bin.*/\1/p' "$(command -v zen-browser 2>/dev/null || echo /dev/null)" 2>/dev/null)" \
    "$(dirname "$(readlink -f "$(command -v zen 2>/dev/null || echo /nonexistent)")")" \
    "$HOME/.tarball-installations/zen" /opt/zen-browser-bin /opt/zen-browser /opt/zen /usr/lib/zen-browser; do
    if [[ -n $candidate && -f $candidate/application.ini && -d $candidate/defaults/pref ]]; then
      echo "$candidate"
      return 0
    fi
  done
  return 1
}

as_owner() {  # runs with sudo only when the folder is not ours
  if [[ -w $1 ]]; then "${@:2}"; else sudo "${@:2}"; fi
}

if [[ $FLATPAK == 1 ]]; then
  warn "Zen из Flatpak: переключатель стиля в Edit Theme не добавить (папка Zen только для чтения)."
  warn "Стиль выбирается в Настройки -> Zen Mods -> Glass Arc."
elif [[ $LOADER == 1 ]] && ZEN_DIR=$(zen_dir); then
  if [[ $ACTION == install ]]; then
    if [[ -w $ZEN_DIR ]] || ask "Добавить переключатель стиля в Edit Theme? Нужен sudo, чтобы положить config.js в $ZEN_DIR"; then
      as_owner "$ZEN_DIR" install -m 644 "$SRC/loader/config.js" "$ZEN_DIR/config.js"
      as_owner "$ZEN_DIR" install -m 644 "$SRC/loader/defaults/pref/config-prefs.js" "$ZEN_DIR/defaults/pref/config-prefs.js"
      say "Переключатель стиля добавлен в Edit Theme ($ZEN_DIR)"
    fi
  elif [[ -f $ZEN_DIR/config.js ]] && grep -q "Glass Arc loader" "$ZEN_DIR/config.js"; then
    as_owner "$ZEN_DIR" rm -f "$ZEN_DIR/config.js" "$ZEN_DIR/defaults/pref/config-prefs.js"
  fi
elif [[ $LOADER == 1 ]]; then
  warn "Папка Zen не найдена: стиль выбирается только в Настройки -> Zen Mods -> Glass Arc."
fi

if [[ $ACTION == uninstall ]]; then
  say "Glass Arc удалён. Настройки Zen остались как есть (старый prefs.js лежит в резервной копии выше)."
  exit 0
fi

if [[ -n ${HYPRLAND_INSTANCE_SIGNATURE:-} ]]; then
  say "Hyprland: чтобы страницы и видео никогда не просвечивали, добавьте правило из extras/hyprland.conf:"
  echo "   https://github.com/$REPO/blob/$BRANCH/extras/hyprland.conf"
fi

say "Готово. Запустите Zen. Стиль стекла: правый клик по боковой панели -> Edit Theme."
