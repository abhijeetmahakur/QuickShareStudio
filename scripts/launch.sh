#!/usr/bin/env bash
# QuickShare Studio launcher for Linux (and macOS).
# Starts the local app server (server.py) and opens the app in a Chromium-based app window.
set -euo pipefail

APP_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SERVER_PY="$APP_DIR/server.py"
WEB_DIR="$APP_DIR/web"
PORT_FILE="$APP_DIR/active_port.txt"

if ! command -v python3 >/dev/null 2>&1; then
  echo "QuickShare Studio needs Python 3. Install it (e.g. 'sudo apt install python3') and try again." >&2
  exit 1
fi

# Reuse a running server if its port still answers.
PORT=""
if [[ -f "$PORT_FILE" ]]; then
  SAVED="$(tr -dc '0-9' < "$PORT_FILE")"
  if [[ -n "$SAVED" ]] && (exec 3<>"/dev/tcp/127.0.0.1/$SAVED") 2>/dev/null; then
    PORT="$SAVED"
  fi
fi

if [[ -z "$PORT" ]]; then
  rm -f "$PORT_FILE"
  nohup python3 "$SERVER_PY" "$WEB_DIR" >/dev/null 2>&1 &
  for _ in $(seq 1 25); do
    sleep 0.2
    if [[ -s "$PORT_FILE" ]]; then
      PORT="$(tr -dc '0-9' < "$PORT_FILE")"
      break
    fi
  done
fi

URL="http://127.0.0.1:${PORT:-52830}/index.html"
PROFILE_DIR="${XDG_DATA_HOME:-$HOME/.local/share}/QuickShareStudio/AppProfile"
mkdir -p "$PROFILE_DIR"

for BROWSER in google-chrome google-chrome-stable chromium chromium-browser microsoft-edge brave-browser; do
  if command -v "$BROWSER" >/dev/null 2>&1; then
    nohup "$BROWSER" --app="$URL" --window-size=1366,850 --user-data-dir="$PROFILE_DIR" >/dev/null 2>&1 &
    exit 0
  fi
done

# No Chromium-based browser found: fall back to the default browser.
if command -v xdg-open >/dev/null 2>&1; then
  xdg-open "$URL"
elif command -v open >/dev/null 2>&1; then
  open "$URL"
else
  echo "Open $URL in your browser."
fi
