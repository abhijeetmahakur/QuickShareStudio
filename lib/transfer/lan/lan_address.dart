/// Picks the IPv4 address other devices on the same Wi-Fi can reach: a private address on a
/// real Wi-Fi/Ethernet adapter rather than a container, VM or VPN bridge (Linux machines often
/// have docker0 / virbr0, Windows has "vEthernet (WSL)"). Returns null when there is none.
String? pickLanAddress(Iterable<({String interface, String address})> candidates) {
  String? best;
  var bestScore = -1 << 30;
  for (final c in candidates) {
    final score = _score(c.interface, c.address);
    if (score != null && score > bestScore) {
      bestScore = score;
      best = c.address;
    }
  }
  return best;
}

final _virtual = RegExp(
  r'^(docker|br-|veth|virbr|vmnet|vboxnet|tun|tap|tailscale|zt|wg|lxc|lxd|cni|flannel|cali|kube|podman|utun|ppp)'
  r'|vethernet|virtualbox|vmware|hyper-v|wsl|tailscale|zerotier|vpn|loopback',
  caseSensitive: false,
);
final _physical = RegExp(r'^(wl|wlan|wifi|en|eth)|wi-fi|wireless|ethernet', caseSensitive: false);

int? _score(String interface, String address) {
  final parts = address.split('.').map(int.tryParse).toList();
  if (parts.length != 4 || parts.any((p) => p == null || p < 0 || p > 255)) return null;
  final a = parts[0]!, b = parts[1]!;
  if (a == 127 || a == 0 || (a == 169 && b == 254)) return null; // loopback, unset, link-local
  var score = 0;
  if (a == 192 && b == 168) {
    score += 30;
  } else if (a == 10) {
    score += 20;
  } else if (a == 172 && b >= 16 && b <= 31) {
    score += 10;
  } else if (a == 100 && b >= 64 && b <= 127) {
    score -= 20; // carrier-grade NAT range, used by Tailscale
  }
  if (_virtual.hasMatch(interface)) score -= 100;
  if (_physical.hasMatch(interface)) score += 50;
  return score;
}
