#!/bin/bash
# Fixes RollerCoaster Tycoon 3: Complete Edition (Epic Games) under CrossOver on macOS.
#
#  1. Startup crash: sets a valid resolution in Options.txt (the default "0 0"
#     makes the game load a 640px GUI that the Epic version doesn't ship).
#  2. Black-screen lock-up: forces windowed mode ("Fullscreen 0").
#  3. No music: converts the WMA soundtrack to PCM WAV (keeping the .wma names),
#     because CrossOver's GStreamer has no WMA decoder. Originals are backed up.
#  4. Adds a "RollerCoaster Tycoon 3" shortcut to the bottle in CrossOver.
#
# Usage: ./fix-rct3.sh [--bottle "Epic Games Store"] [--resolution 1920x1200]
#                      [--no-music] [--no-shortcut]
set -euo pipefail

BOTTLE="Epic Games Store"
RES=""
MUSIC=1
SHORTCUT=1
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

while [ $# -gt 0 ]; do
  case "$1" in
    --bottle) BOTTLE="$2"; shift 2 ;;
    --resolution) RES="$2"; shift 2 ;;
    --no-music) MUSIC=0; shift ;;
    --no-shortcut) SHORTCUT=0; shift ;;
    -h|--help) sed -n '2,12p' "$0"; exit 0 ;;
    *) echo "Unknown option: $1" >&2; exit 1 ;;
  esac
done

BOTTLE_DIR="$HOME/Library/Application Support/CrossOver/Bottles/$BOTTLE"
[ -d "$BOTTLE_DIR" ] || { echo "Bottle not found: $BOTTLE_DIR" >&2; exit 1; }

GAME_EXE=$(find "$BOTTLE_DIR/drive_c" -maxdepth 5 -name RCT3.exe -print -quit 2>/dev/null || true)
[ -n "$GAME_EXE" ] || { echo "RCT3.exe not found in bottle '$BOTTLE'" >&2; exit 1; }
GAME_DIR=$(dirname "$GAME_EXE")
echo "Game:   $GAME_DIR"

if pgrep -f 'RCT3.exe' >/dev/null; then
  echo "RCT3 is running - quit it first." >&2; exit 1
fi

# --- 1+2: resolution and windowed mode -------------------------------------
if [ -z "$RES" ]; then
  # Largest common mode that fits the usable screen area (below the menu bar /
  # notch, beside the Dock), leaving ~28pt for the window title bar.
  read -r VW VH < <(osascript -l JavaScript -e \
    'ObjC.import("AppKit"); var v=$.NSScreen.mainScreen.visibleFrame; Math.floor(v.size.width)+" "+Math.floor(v.size.height)')
  VH=$((VH - 28))
  for m in 2560x1600 2560x1440 1920x1200 1920x1080 1680x1050 1440x900 1280x800 1024x768; do
    if [ "${m%x*}" -le "$VW" ] && [ "${m#*x}" -le "$VH" ]; then RES=$m; break; fi
  done
  RES=${RES:-1024x768}
  echo "Screen: usable ${VW}x${VH} -> picking $RES"
fi
W=${RES%x*}; H=${RES#*x}
if [ "$W" -lt 800 ]; then
  echo "Resolution must be at least 800 wide (the Epic version has no 640 GUI)." >&2; exit 1
fi

OPTS_DIR="$BOTTLE_DIR/drive_c/users/crossover/AppData/Roaming/Frontier/RCT3"
OPTS="$OPTS_DIR/Options.txt"
mkdir -p "$OPTS_DIR"
if [ -f "$OPTS" ]; then
  [ -f "$OPTS.bak" ] || cp "$OPTS" "$OPTS.bak"
  if grep -q '^Resolution ' "$OPTS"; then
    sed -i '' "s/^Resolution .*/Resolution $W $H/" "$OPTS"
  else
    printf 'Resolution %s %s\n' "$W" "$H" >> "$OPTS"
  fi
  if grep -q '^Fullscreen' "$OPTS"; then
    sed -i '' 's/^Fullscreen.*/Fullscreen 0/' "$OPTS"
  else
    printf 'Fullscreen 0\n' >> "$OPTS"
  fi
else
  # The game fills in all other settings with defaults on first start.
  printf 'Resolution %s %s\nFullscreen 0\n' "$W" "$H" > "$OPTS"
fi
echo "Options: $(grep -E '^(Resolution|Fullscreen)' "$OPTS" | tr '\n' ' ')"

# --- 3: music ---------------------------------------------------------------
if [ "$MUSIC" -eq 1 ]; then
  command -v ffmpeg >/dev/null || { echo "ffmpeg not found (brew install ffmpeg), or rerun with --no-music" >&2; exit 1; }
  MUSIC_DIR="$GAME_DIR/Music"
  BACKUP="$GAME_DIR/Music.orig-wma"
  [ -d "$BACKUP" ] || cp -Rp "$MUSIC_DIR" "$BACKUP"
  n=0
  for src in "$BACKUP"/*.wma; do
    dst="$MUSIC_DIR/$(basename "$src")"
    # Skip tracks that are already WAV.
    [ "$(head -c 4 "$dst" 2>/dev/null)" = "RIFF" ] && continue
    ffmpeg -nostdin -loglevel error -y -i "$src" -c:a pcm_s16le -ar 44100 -ac 2 -f wav "$dst"
    n=$((n + 1))
  done
  echo "Music:  converted $n track(s), originals in $BACKUP"
fi

# --- 4: CrossOver shortcut ---------------------------------------------------
# A Start Menu .lnk shows up as "RollerCoaster Tycoon 3" in the bottle in
# CrossOver, so the game starts without going through the Epic launcher.
if [ "$SHORTCUT" -eq 1 ]; then
  CX="/Applications/CrossOver.app/Contents/SharedSupport/CrossOver"
  PROGRAMS="$BOTTLE_DIR/drive_c/users/crossover/AppData/Roaming/Microsoft/Windows/Start Menu/Programs"
  WIN_DIR="C:\\$(printf '%s' "${GAME_DIR#"$BOTTLE_DIR/drive_c/"}" | tr '/' '\\')"
  mkdir -p "$PROGRAMS"
  python3 -I "$SCRIPT_DIR/make_lnk.py" "$PROGRAMS/RollerCoaster Tycoon 3.lnk" \
    "$WIN_DIR\\RCT3.exe" "$WIN_DIR" "RollerCoaster Tycoon 3: Complete Edition"
  "$CX/bin/cxmenu" --bottle "$BOTTLE" --sync --mode install >/dev/null 2>&1 || true
  echo "Shortcut: 'RollerCoaster Tycoon 3' added to the bottle in CrossOver"
fi

echo "Done. Start the game from CrossOver or the Epic Games Launcher."
