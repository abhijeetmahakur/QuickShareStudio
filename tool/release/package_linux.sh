#!/usr/bin/env bash
# Builds the Linux release packages from a `flutter build linux --release` bundle:
#
#   QuickShareStudio-Linux-x86_64.AppImage   main package; updates itself from inside the app
#   QuickShareStudio-Linux-x86_64.deb        Debian, Ubuntu, Linux Mint (apt install ./...)
#   QuickShareStudio-Linux-x86_64.tar.gz     portable folder with an install.sh for the menu
#
# Run it on the oldest supported distribution (Ubuntu 22.04, glibc 2.35) so the binaries also
# run on newer ones. Needs: imagemagick, dpkg-dev, file, curl, and tesseract-ocr with the eng
# and hin language data (bundled into the AppImage and tarball for OCR).
#
#   BUNDLE=build/linux/x64/release/bundle OUT=dist tool/release/package_linux.sh
set -euo pipefail
cd "$(dirname "$0")/../.."

BUNDLE=${BUNDLE:-build/linux/x64/release/bundle}
OUT=${OUT:-dist}
VERSION=${VERSION:-$(grep '^version:' pubspec.yaml | sed -E 's/version:[[:space:]]*([0-9.]+).*/\1/')}
APP_ID=com.quickshare.quickshare
NAME=QuickShareStudio-Linux-x86_64
WORK=$(mktemp -d)
trap 'rm -rf "$WORK"' EXIT
mkdir -p "$OUT"

[[ -x "$BUNDLE/quickshare" ]] || { echo "No Flutter bundle at $BUNDLE" >&2; exit 1; }
echo "Packaging QuickShare Studio $VERSION from $BUNDLE"

# ---------------------------------------------------------------------------------------------
# The app folder all three packages share.
# ---------------------------------------------------------------------------------------------
APP="$WORK/app"
cp -a "$BUNDLE" "$APP"
# Built only for an Android plugin; on Linux it would just drag in a JVM dependency.
rm -f "$APP/lib/libdartjni.so"

# The binaries must not need a newer glibc than the build system has.
glibc=$(find "$APP" -type f \( -name 'quickshare' -o -name '*.so*' \) -exec objdump -T {} \; 2>/dev/null |
  grep -o 'GLIBC_[0-9][0-9.]*' | sort -Vu | tail -n1 | cut -d_ -f2)
glibcxx=$(find "$APP" -type f \( -name 'quickshare' -o -name '*.so*' \) -exec objdump -T {} \; 2>/dev/null |
  grep -o 'GLIBCXX_[0-9][0-9.]*' | sort -Vu | tail -n1 | cut -d_ -f2)
echo "Highest symbol versions needed: glibc $glibc, libstdc++ ${glibcxx:-none}"

# Icons in every hicolor size, from the QuickShare logo.
ICONS="$WORK/icons"
for size in 16 22 24 32 48 64 128 256 512; do
  mkdir -p "$ICONS/hicolor/${size}x${size}/apps"
  convert assets/logo.png -resize "${size}x${size}" "$ICONS/hicolor/${size}x${size}/apps/$APP_ID.png"
done

desktop_entry() { sed "s|@EXEC@|$1|" "linux/packaging/$APP_ID.desktop"; }
metainfo() { sed -e "s/@VERSION@/$VERSION/" -e "s/@DATE@/$(date -u +%F)/" "linux/packaging/$APP_ID.metainfo.xml"; }

# Tesseract for OCR, with private copies of the libraries whose versions differ between
# distributions (Leptonica, ICU, libtiff, libjpeg, ...). The system core (glibc, libstdc++,
# GLib/GTK, cairo/pango, X11, fontconfig) comes from the host. The app sets LD_LIBRARY_PATH
# for tesseract only, so these copies never affect the app itself.
bundle_tesseract() {
  local dest="$1/tesseract" tessdata lib
  mkdir -p "$dest/bin" "$dest/lib" "$dest/tessdata"
  cp "$(command -v tesseract)" "$dest/bin/tesseract"
  tessdata=$(dirname "$(find /usr/share -name eng.traineddata -path '*tessdata*' | head -n1)")
  cp "$tessdata/eng.traineddata" "$tessdata/hin.traineddata" "$tessdata/osd.traineddata" "$tessdata/pdf.ttf" "$dest/tessdata/"
  ldd "$dest/bin/tesseract" | awk '/=> \// {print $3}' | while read -r lib; do
    case "$(basename "$lib")" in
      ld-linux* | libc.so* | libm.so* | libdl.so* | libpthread.so* | librt.so* | libresolv.so* | libutil.so* | \
        libgcc_s.so* | libstdc++.so* | libz.so* | libX* | libxcb* | libGL* | libEGL* | libdrm* | libgbm* | \
        libglib-2.0* | libgobject-2.0* | libgio-2.0* | libgmodule-2.0* | libcairo* | libpango* | libharfbuzz* | \
        libfreetype* | libfontconfig* | libpixman* | libexpat* | libffi* | libpcre* | libselinux* | libmount* | \
        libblkid* | libuuid* | libbrotli* | libpng16* | libbz2* | libgraphite2* | libfribidi* | libthai* | \
        libdatrie* | libsystemd* | libcap* | libgcrypt* | libgpg-error* | liblz4* | libzstd* | liblzma*)
        continue ;;
    esac
    cp -L "$lib" "$dest/lib/"
  done
  echo "Bundled Tesseract: $(LD_LIBRARY_PATH="$dest/lib" "$dest/bin/tesseract" --version 2>&1 | head -n1)"
  LD_LIBRARY_PATH="$dest/lib" "$dest/bin/tesseract" --tessdata-dir "$dest/tessdata" --list-langs
}

# ---------------------------------------------------------------------------------------------
# AppImage
# ---------------------------------------------------------------------------------------------
APPDIR="$WORK/QuickShareStudio.AppDir"
mkdir -p "$APPDIR/usr/lib" "$APPDIR/usr/share/applications" "$APPDIR/usr/share/metainfo" "$APPDIR/usr/share/icons"
cp -a "$APP" "$APPDIR/usr/lib/quickshare-studio"
bundle_tesseract "$APPDIR/usr/lib/quickshare-studio"
cp -a "$ICONS/hicolor" "$APPDIR/usr/share/icons/"
desktop_entry quickshare-studio >"$APPDIR/usr/share/applications/$APP_ID.desktop"
cp "$APPDIR/usr/share/applications/$APP_ID.desktop" "$APPDIR/$APP_ID.desktop"
cp "$ICONS/hicolor/256x256/apps/$APP_ID.png" "$APPDIR/$APP_ID.png"
ln -s "$APP_ID.png" "$APPDIR/.DirIcon"
metainfo >"$APPDIR/usr/share/metainfo/$APP_ID.appdata.xml"
cat >"$APPDIR/AppRun" <<'EOF'
#!/bin/sh
# Flutter finds its data/ and lib/ folders next to the real executable.
HERE="$(dirname "$(readlink -f "$0")")"
exec "$HERE/usr/lib/quickshare-studio/quickshare" "$@"
EOF
chmod 755 "$APPDIR/AppRun"

APPIMAGETOOL="$WORK/appimagetool"
curl -fsSL --retry 3 -o "$APPIMAGETOOL" \
  https://github.com/AppImage/appimagetool/releases/download/continuous/appimagetool-x86_64.AppImage
chmod +x "$APPIMAGETOOL"
ARCH=x86_64 APPIMAGE_EXTRACT_AND_RUN=1 "$APPIMAGETOOL" --no-appstream "$APPDIR" "$OUT/$NAME.AppImage"

# ---------------------------------------------------------------------------------------------
# Debian package (Ubuntu, Debian, Linux Mint). OCR uses the distribution's Tesseract, which
# apt installs by default through Recommends.
# ---------------------------------------------------------------------------------------------
DEB="$WORK/deb"
mkdir -p "$DEB/DEBIAN" "$DEB/usr/lib" "$DEB/usr/bin" "$DEB/usr/share/applications" "$DEB/usr/share/metainfo" \
  "$DEB/usr/share/icons" "$DEB/usr/share/doc/quickshare-studio"
cp -a "$APP" "$DEB/usr/lib/quickshare-studio"
ln -s ../lib/quickshare-studio/quickshare "$DEB/usr/bin/quickshare-studio"
cp -a "$ICONS/hicolor" "$DEB/usr/share/icons/"
desktop_entry quickshare-studio >"$DEB/usr/share/applications/$APP_ID.desktop"
metainfo >"$DEB/usr/share/metainfo/$APP_ID.metainfo.xml"
cp LICENSE "$DEB/usr/share/doc/quickshare-studio/copyright"
cat >"$DEB/DEBIAN/control" <<EOF
Package: quickshare-studio
Version: $VERSION
Section: net
Priority: optional
Architecture: amd64
Maintainer: Abhijeet Mahakur <abhijeetmahakur@users.noreply.github.com>
Installed-Size: $(du -sk "$DEB/usr" | cut -f1)
Depends: libgtk-3-0 | libgtk-3-0t64, libc6 (>= $glibc), libstdc++6 (>= 12)
Recommends: tesseract-ocr, tesseract-ocr-eng, tesseract-ocr-hin, xdg-desktop-portal-gtk | xdg-desktop-portal, zenity
Homepage: https://github.com/abhijeetmahakur/QuickShareStudio
Description: Share files, clipboard and PDFs between your devices
 QuickShare Studio sends files and clipboard text or images between Linux,
 Windows and Android devices over the same Wi-Fi or the internet, end-to-end
 encrypted, after pairing with a 6-digit code or QR code. It also builds PDFs
 from screenshots and merges, splits, compresses and OCRs PDFs.
EOF
find "$DEB" -type d -exec chmod 755 {} +
dpkg-deb --build --root-owner-group -Zxz "$DEB" "$OUT/$NAME.deb"

# ---------------------------------------------------------------------------------------------
# Portable tarball: unpack anywhere, run ./quickshare, or ./install.sh to add a menu entry.
# ---------------------------------------------------------------------------------------------
TAR="$WORK/$NAME"
cp -a "$APP" "$TAR"
cp -a "$APPDIR/usr/lib/quickshare-studio/tesseract" "$TAR/tesseract"
mkdir -p "$TAR/share"
cp -a "$ICONS/hicolor" "$TAR/share/icons"
cp "linux/packaging/$APP_ID.desktop" "$TAR/share/$APP_ID.desktop.in"
cp LICENSE "$TAR/LICENSE"
cat >"$TAR/install.sh" <<'EOF'
#!/bin/sh
# Adds QuickShare Studio from this folder to your applications menu (no root needed).
# Run ./install.sh --remove to take it out again.
set -eu
HERE="$(cd "$(dirname "$0")" && pwd)"
DATA="${XDG_DATA_HOME:-$HOME/.local/share}"
ID=com.quickshare.quickshare
if [ "${1:-}" = "--remove" ]; then
  rm -f "$DATA/applications/$ID.desktop" "$DATA"/icons/hicolor/*/apps/$ID.png
  echo "Removed QuickShare Studio from the applications menu."
  exit 0
fi
for dir in "$HERE"/share/icons/hicolor/*/apps; do
  size=$(basename "$(dirname "$dir")")
  mkdir -p "$DATA/icons/hicolor/$size/apps"
  cp "$dir/$ID.png" "$DATA/icons/hicolor/$size/apps/"
done
mkdir -p "$DATA/applications"
exec_path=$(printf '%s' "$HERE/quickshare" | sed 's/[\\"`$]/\\&/g')
sed "s|@EXEC@|\"$exec_path\"|" "$HERE/share/$ID.desktop.in" >"$DATA/applications/$ID.desktop"
update-desktop-database "$DATA/applications" >/dev/null 2>&1 || true
gtk-update-icon-cache -q "$DATA/icons/hicolor" >/dev/null 2>&1 || true
echo "Added QuickShare Studio to your applications menu."
EOF
chmod 755 "$TAR/install.sh"
cat >"$TAR/README.txt" <<EOF
QuickShare Studio $VERSION for Linux (x86_64)

Run:            ./quickshare
Add to menu:    ./install.sh        (remove again with ./install.sh --remove)
Updates:        Settings & Privacy > Updates replaces this folder with the new version.
Firewall (ufw): sudo ufw allow 8088:8097/tcp && sudo ufw allow 8089/udp
EOF
tar -C "$WORK" -czf "$OUT/$NAME.tar.gz" "$NAME"

ls -la "$OUT"/"$NAME".*
