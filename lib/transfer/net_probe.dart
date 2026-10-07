import 'net_probe_io.dart' if (dart.library.js_interop) 'net_probe_web.dart' as impl;

/// Whether [host] resolves within [timeout]: a cheap "is there really no internet?" check
/// for when the OS network service reports none (Linux NetworkManager does that for
/// connections it does not manage, e.g. systemd-networkd, iwd or many VMs).
Future<bool> hostResolves(String host, {Duration timeout = const Duration(seconds: 2)}) =>
    impl.hostResolves(host, timeout);
