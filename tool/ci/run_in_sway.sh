#!/usr/bin/env bash
# Runs a command inside a headless Wayland session (sway, software rendering), for the Linux
# desktop tests: GTK talks Wayland, wl-clipboard and wtype act as other apps and the keyboard.
#
#   tool/ci/run_in_sway.sh flutter test integration_test/linux_desktop_test.dart -d linux
set -euo pipefail
export XDG_RUNTIME_DIR="${XDG_RUNTIME_DIR:-$(mktemp -d)}"
chmod 700 "$XDG_RUNTIME_DIR"
export WLR_BACKENDS=headless WLR_LIBINPUT_NO_DEVICES=1 WLR_RENDERER=pixman
config="$XDG_RUNTIME_DIR/sway.conf"
cat >"$config" <<'EOF'
output HEADLESS-1 resolution 1440x900
default_border none
focus_on_window_activation focus
EOF
sway -c "$config" >"$XDG_RUNTIME_DIR/sway.log" 2>&1 &
sway_pid=$!
socket=""
for _ in $(seq 1 100); do
  socket=$(find "$XDG_RUNTIME_DIR" -maxdepth 1 -name 'wayland-*' -type s -printf '%f\n' 2>/dev/null | head -n1)
  [[ -n "$socket" ]] && break
  sleep 0.1
done
if [[ -z "$socket" ]]; then
  echo "sway did not start:" >&2
  cat "$XDG_RUNTIME_DIR/sway.log" >&2
  exit 1
fi
echo "Wayland session on $socket (sway $(sway --version | awk '{print $3}'))"
export WAYLAND_DISPLAY="$socket" GDK_BACKEND=wayland LIBGL_ALWAYS_SOFTWARE=1 XDG_SESSION_TYPE=wayland
unset DISPLAY
status=0
"$@" || status=$?
kill "$sway_pid" 2>/dev/null || true
exit "$status"
