# Changelog

All notable changes to QuickShare Studio. Versions follow [semantic versioning](https://semver.org).

## [2.0.10] - 2026-10-06

### Fixed
- Prevent the Windows release build from failing on current MSVC because of the deprecated coroutine header used by `permission_handler_windows`.
- Universal Clipboard no longer appears selected on the Dashboard before it is opened.

## [2.0.9] - 2026-10-06

### Fixed
- Universal Clipboard no longer appears selected on the Dashboard before it is opened.

## [2.0.8] - 2026-10-06

### Added
- **Internet-first pairing:** Select Internet or Same Wi-Fi on Device Pairing; route changes rotate the six-digit PeerJS ID and QR credentials.
- **Linux AppImage:** Publish a native Linux AppImage alongside the existing web launcher package.

### Changed
- Same Wi-Fi QR pairing tries the local connection first and falls back to Internet automatically; six-digit code entry uses Internet by default.
- Linux AppImage, Windows installer, and Android APK releases support verified in-app updates.

### Fixed
- Correct five-minute pairing expiry and automatic credential regeneration at expiry.
- Remove QR paste controls, reject invalid scans with concise feedback, and direct Linux users to six-digit code entry.
- Reject pairing input unless it contains exactly six decimal digits.

## [2.0.7] - 2026-10-05

### Added
- **Cross-network WebRTC candidate logging:** ICE candidates (host, srflx, relay) logged in real-time for transparent network diagnostics.
- **Receiver-side verification:** Immediate SHA-256 verification and logging upon receiving all chunks (`all chunks received, file verified, saved path`).
- **In-app update check:** Automatically detects releases published to GitHub and displays update prompts.

### Changed
- **Windows app icon:** Replaced window title bar, taskbar, and executable icon with multi-size ICO (16-256px) derived from the official QuickShare logo.
- **Scan QR Code:** Simplified scanner view, keeping camera scan as the primary flow.
- **Release packaging:** Publish native Windows setup and portable packages, Linux bundle, and Android APK from tagged GitHub releases.

### Fixed
- **Release artifacts:** Include and checksum every required release artifact in the updater manifest.
- **Pairing and transfer:** Robust cross-network pairing and reliable chunked transfer over WebRTC.

## [2.0.1] - 2026-10-05

### Changed
- Use the complete QuickShare Studio logo for Android, iOS, macOS, Windows, and PWA icons.
- Refresh the PWA icon cache when the updated service worker is installed.
- Improve the pairing and dashboard layouts for narrow phones, tablets, and wide screens.

### Fixed
- Request camera permission before scanning, restart the scanner when returning to the app, and show clear retry/settings guidance when camera access is blocked.

## [2.0.0] - 2026-10-05

> **Updating from 1.x: install this version once by hand.** Versions before 2.0 have no
> in-app updater, so they cannot install 2.0 by themselves. Download 2.0 from this page
> (Android: `QuickShareStudio-Android.apk`; Windows/Linux: the zip/tarball, extracted over
> your old folder). From 2.0 on, QuickShare finds and installs updates itself.
>
> **Android:** if Android says *"App not installed"*, the old APK was signed with a
> different key: uninstall the old version first (received files in Download/QuickShare
> are kept), then install this one.
>
> **Both devices need 2.0.** Transfers now ask the receiver first and are end-to-end
> encrypted; a 1.x device cannot send to a 2.0 device (it is told to update).

### Added
- **Connect over the internet:** devices on different networks (home/office, mobile data) connect with the same 6-digit code or QR code. Signaling via PeerJS Cloud, data directly between devices over WebRTC, with a TURN relay fallback for strict networks.
- **Bluetooth for offline transfers (Android 10+):** nearby phones find each other over Bluetooth, agree on an encryption key, and send the files over Wi-Fi Direct. No Wi-Fi network or internet needed.
- **Automatic fallback:** QuickShare looks on your Wi-Fi first and, if the device is not there within 5 seconds, tries the internet; Bluetooth is offered when you are offline.
- **Accept before receiving:** you see who is sending which files (names, count, total size) and tap Accept or Decline. Nothing is received before that.
- **Verification code:** both devices show the same 4 digits for a connection; if they differ, someone is in the middle.
- **End-to-end encryption everywhere:** WebRTC (DTLS) over the internet; X25519 + AES-256-GCM for same-Wi-Fi and Bluetooth transfers.
- **Large files and many files:** 16 KB chunks with sequence numbers and flow control, SHA-256 verification per file, live progress, speed and time left, cancel at any time, and resume after a dropped connection.
- **In-app updates:** Android downloads, verifies (SHA-256 and signing key) and installs new versions; the desktop app updates and restarts itself. Very old versions are asked to update.
- **Settings > Connections:** auto-accept (off by default), default connection method, automatic internet fallback, internet reachability.
- A first-run guide to the three ways to connect, a QR camera scanner on phones, and transfers that keep running in the background on Android.

### Changed
- Pairing codes are generated with a secure random generator, work once, and expire after 5 minutes (or after 5 failed attempts).
- Same-Wi-Fi transfers use protocol v2 (discovery and pairing are unchanged).
- Received files are written straight to disk (Download/QuickShare), so very large files no longer need to fit in memory.

### Fixed
- Pairing behind port forwarding kept the wrong port.
- Several issues found while testing on Android 14: permission prompts, cancelling an interrupted transfer, and reconnecting to the internet service after a network change.

## [1.6.0]
- Device-to-device sharing on the same Wi-Fi, offline OCR and PDF tools, update checks.
