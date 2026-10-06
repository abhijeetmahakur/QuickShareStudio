# Changelog

All notable changes to QuickShare Studio. Versions follow [semantic versioning](https://semver.org).

## [2.0.19] - 2026-10-07

### Fixed
- Android release builds require the permanent release keystore, and CI verifies the APK certificate against a pinned SHA-256 fingerprint.
- Android signature mismatch errors appear once in the update dialog with a release-page action and reinstall guidance.
- Release-note headings are cleaned up, and empty release notes use a readable fallback.

## [2.0.18] - 2026-10-07

### Fixed
- **Received Files fits phones:** file cards show the name, sender, size and location across the full width with Open and Download underneath, instead of squeezing the details into a one-letter-wide column; the status card, title and filter chips fit small screens too.
- **Download saves to Downloads on Android:** Download makes sure the file is in Downloads/QuickShare, copying in files received before 2.0.17 from app storage, and offers to open it.
- **Smoother Android saving:** received files are written to Downloads off the UI thread in 512 KB blocks, and a transfer falls back to app storage instead of failing when Downloads cannot be used.

## [2.0.17] - 2026-10-07

### Fixed
- Android receives now stream verified files into the public Downloads/QuickShare folder using MediaStore.
- The mobile update dialog now fits small screens, removes raw Markdown from release notes, and shows update failures only once.
- Dashboard workspace cards now show a clear lime glow while hovered by a mouse.
- Android's minimum SDK is aligned with the current cryptography plugin requirement (API 24).

## [2.0.16] - 2026-10-07

### Fixed
- Windows releases now validate the x64 launcher and plugin DLL, extract and start the ZIP build, and silently install and start the installer build before publishing.

## [2.0.15] - 2026-10-07

### Fixed
- Dashboard cards now navigate directly instead of retaining a persistent selected glow; mouse hover and touch feedback are independent per card and reset on exit, navigation, and app deactivation.
- Dashboard sidebar items now use isolated mouse hover state and keyboard-only focus highlighting.

## [2.0.14] - 2026-10-07

### Fixed
- Cancel timed-out connection attempts and enforce a single eight-second budget for each WebRTC path, including ICE retries.
- Require the supplied one-time code (and QR nonce when present) for Bluetooth pairing; rotate LAN, Internet, and Bluetooth pairing credentials after successful use.
- Keep the connection panel to one status line and a single Retry action after all supported transports fail.

## [2.0.13] - 2026-10-07

### Added
- Silent auto-fallback chain for device pairing: LAN direct connection (~4s), PeerJS WebRTC with STUN (~8s), WebRTC with forced TURN relay (~12s), and Bluetooth fallback.
- Parallel racing across direct LAN, WebRTC STUN, and WebRTC Relay connection attempts, automatically adopting the first to connect and cancelling the remainder.
- Enhanced ICE configuration with multiple STUN pools (Google, Cloudflare, Open Relay) and TURN relay servers with credentials.
- Automatic ICE failure and disconnection handling with auto-retry up to 2 times before escalating.

### Fixed
- Replaced manual choice prompts ("Couldn't find the device on this Wi-Fi") with a streamlined single status line ("Connecting..." -> "Connected via Wi-Fi / Internet / Relay / Bluetooth") and a single Retry button on complete failure.

## [2.0.12] - 2026-10-07

### Fixed
- Dashboard workspace cards now use a neutral hover state; only a card explicitly selected by the user receives the lime selected outline and icon.

## [2.0.11] - 2026-10-07

### Fixed
- Fixed Dashboard workspace card selection/active-state logic: cards start in a neutral "nothing selected" state on Dashboard display, Universal Clipboard is not selected by default, clicking a card activates it with accent highlight and immediately clears previous card selection, and returning to Dashboard clears card selection.
- Fixed GitHub Actions release workflow Android signing step to build and publish downloadable desktop application release artifacts without failing on missing keystore secrets.

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
