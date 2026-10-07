import '../../models/app_update_info.dart';
import 'platform_updater_io.dart' if (dart.library.js_interop) 'platform_updater_web.dart' as impl;

/// Outcome of installing an update on this platform.
class InstallResult {
  const InstallResult(
    this.ok,
    this.message, {
    this.openReleasePage = false,
    this.signatureMismatch = false,
  });
  final bool ok;
  final String message;

  /// The update cannot be applied in-app; send the user to the download page.
  final bool openReleasePage;

  /// Android rejected the package because its signing certificate differs.
  final bool signatureMismatch;
}

/// Whether this platform can download and install updates by itself.
bool get canSelfUpdate => impl.canSelfUpdate;

/// Linux release assets: the AppImage (main), the Debian package and the portable tarball.
const linuxAppImageAsset = 'QuickShareStudio-Linux-x86_64.AppImage';
const linuxDebAsset = 'QuickShareStudio-Linux-x86_64.deb';
const linuxTarballAsset = 'QuickShareStudio-Linux-x86_64.tar.gz';

/// The Linux asset this copy updates from (it depends on how it was installed).
String get linuxAssetName => impl.linuxAssetName;

/// Downloads [update]'s package for this platform, verifies its SHA-256 and installs it
/// (Android: system installer after a signer check; desktop: the launcher swaps the bundle and
/// restarts). [onProgress] receives 0..1.
Future<InstallResult> downloadAndInstall(AppUpdateInfo update, void Function(double progress) onProgress) =>
    impl.downloadAndInstall(update, onProgress);
