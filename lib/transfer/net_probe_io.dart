import 'dart:io';

Future<bool> hostResolves(String host, Duration timeout) async {
  try {
    final addresses = await InternetAddress.lookup(host).timeout(timeout);
    return addresses.isNotEmpty;
  } catch (_) {
    return false;
  }
}
