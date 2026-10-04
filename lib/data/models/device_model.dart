import 'package:uuid/uuid.dart';

enum DeviceType { desktop, mobile, tablet, browser }

class DeviceModel {
  final String id;
  final String name;
  final String ip;
  final int port;
  final DeviceType deviceType;
  final bool isTrusted;
  final bool isOnline;
  final DateTime lastSeen;
  final String fingerprint;
  final String? platform;

  DeviceModel({
    String? id,
    required this.name,
    required this.ip,
    required this.port,
    this.deviceType = DeviceType.desktop,
    this.isTrusted = false,
    this.isOnline = true,
    DateTime? lastSeen,
    String? fingerprint,
    this.platform,
  })  : id = id ?? const Uuid().v4(),
        lastSeen = lastSeen ?? DateTime.now(),
        fingerprint = fingerprint ?? name.hashCode.toRadixString(16);

  DeviceModel copyWith({
    String? name,
    String? ip,
    int? port,
    DeviceType? deviceType,
    bool? isTrusted,
    bool? isOnline,
    DateTime? lastSeen,
    String? fingerprint,
    String? platform,
  }) {
    return DeviceModel(
      id: id,
      name: name ?? this.name,
      ip: ip ?? this.ip,
      port: port ?? this.port,
      deviceType: deviceType ?? this.deviceType,
      isTrusted: isTrusted ?? this.isTrusted,
      isOnline: isOnline ?? this.isOnline,
      lastSeen: lastSeen ?? this.lastSeen,
      fingerprint: fingerprint ?? this.fingerprint,
      platform: platform ?? this.platform,
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'ip': ip,
        'port': port,
        'deviceType': deviceType.index,
        'isTrusted': isTrusted,
        'isOnline': isOnline,
        'lastSeen': lastSeen.toIso8601String(),
        'fingerprint': fingerprint,
        'platform': platform,
      };

  factory DeviceModel.fromJson(Map<String, dynamic> json) => DeviceModel(
        id: json['id'] as String,
        name: json['name'] as String,
        ip: json['ip'] as String,
        port: json['port'] as int,
        deviceType: DeviceType.values[json['deviceType'] as int? ?? 0],
        isTrusted: json['isTrusted'] as bool? ?? false,
        isOnline: json['isOnline'] as bool? ?? true,
        lastSeen: DateTime.tryParse(json['lastSeen'] as String? ?? '') ?? DateTime.now(),
        fingerprint: json['fingerprint'] as String? ?? '',
        platform: json['platform'] as String?,
      );
}
