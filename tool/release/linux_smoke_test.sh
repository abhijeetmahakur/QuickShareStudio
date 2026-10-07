#!/usr/bin/env bash
# Starts a QuickShare Studio Linux package on the distribution this runs on (a container of
# Ubuntu, Debian, Fedora or Linux Mint) under a virtual X server and checks that the window
# appears, that no library is missing, and that the bundled OCR engine runs.
#
#   tool/release/linux_smoke_test.sh appimage|deb|tarball <package> <output dir>
set -euo pipefail
kind="$1"
package="$2"
out="${3:-/tmp/smoke}"
mkdir -p "$out"
. /etc/os-release
tag="${ID}-${VERSION_ID:-rolling}-${kind}"
echo "== $PRETTY_NAME: $kind"

# Only what a desktop already has (GTK 3, Mesa) plus a virtual display and its tools.
if command -v apt-get >/dev/null; then
  export DEBIAN_FRONTEND=noninteractive
  apt-get update -qq
  gtk=libgtk-3-0
  apt-cache show libgtk-3-0t64 >/dev/null 2>&1 && gtk=libgtk-3-0t64
  apt-get install -y -qq --no-install-recommends "$gtk" libgl1 libgl1-mesa-dri libegl1 xvfb xauth x11-utils \
    imagemagick dbus-x11 ca-certificates file >/dev/null
elif command -v dnf >/dev/null; then
  dnf install -y -q gtk3 mesa-dri-drivers mesa-libEGL xorg-x11-server-Xvfb xwininfo ImageMagick dbus-x11 file \
    >/dev/null
fi

case "$kind" in
  appimage)
    cp "$package" /tmp/QuickShareStudio.AppImage
    chmod +x /tmp/QuickShareStudio.AppImage
    # Containers have no FUSE; the runtime can unpack itself instead.
    (cd /tmp && ./QuickShareStudio.AppImage --appimage-extract >/dev/null)
    app_dir=/tmp/squashfs-root/usr/lib/quickshare-studio
    cmd=(/tmp/squashfs-root/AppRun)
    ;;
  deb)
    apt-get install -y -qq "$package" >/dev/null
    app_dir=/usr/lib/quickshare-studio
    cmd=(quickshare-studio)
    command -v quickshare-studio
    test -f /usr/share/applications/com.quickshare.quickshare.desktop
    test -f /usr/share/icons/hicolor/256x256/apps/com.quickshare.quickshare.png
    ;;
  tarball)
    tar -xzf "$package" -C /opt
    app_dir=/opt/QuickShareStudio-Linux-x86_64
    cmd=("$app_dir/quickshare")
    ;;
esac

echo "-- shared libraries"
missing=$(cd "$app_dir" && ldd quickshare lib/*.so 2>/dev/null | grep 'not found' | sort -u || true)
if [[ -n "$missing" ]]; then
  echo "Missing libraries on $PRETTY_NAME:"
  echo "$missing"
  exit 1
fi
echo "all resolved"

if [[ -x "$app_dir/tesseract/bin/tesseract" ]]; then
  echo "-- bundled OCR engine"
  langs=$(LD_LIBRARY_PATH="$app_dir/tesseract/lib" "$app_dir/tesseract/bin/tesseract" \
    --tessdata-dir "$app_dir/tesseract/tessdata" --list-langs 2>&1)
  echo "$langs"
  grep -qx eng <<<"$langs" && grep -qx hin <<<"$langs"
fi

echo "-- start"
Xvfb :99 -screen 0 1280x800x24 >/dev/null 2>&1 &
export DISPLAY=:99
sleep 1
dbus-launch --exit-with-session "${cmd[@]}" >"$out/$tag.log" 2>&1 &
app=$!
found=""
for _ in $(seq 1 60); do
  sleep 0.5
  if ! kill -0 "$app" 2>/dev/null; then break; fi
  if xwininfo -root -tree 2>/dev/null | grep -q '"QuickShare Studio"'; then
    found=1
    break
  fi
done
sleep 3 # let the first frames render
if [[ -z "$found" ]] || ! kill -0 "$app" 2>/dev/null; then
  echo "QuickShare Studio did not open a window on $PRETTY_NAME. Log:"
  cat "$out/$tag.log"
  exit 1
fi
import -window root "$out/$tag.png"
echo "window open, screenshot $tag.png"
kill "$app" 2>/dev/null || true
echo "PASS $PRETTY_NAME $kind"
