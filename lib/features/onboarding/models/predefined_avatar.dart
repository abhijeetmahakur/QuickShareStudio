import 'package:flutter/material.dart';

class PredefinedAvatar {
  final String id;
  final String label;
  final IconData icon;
  final Color accentColor;

  const PredefinedAvatar({
    required this.id,
    required this.label,
    required this.icon,
    this.accentColor = const Color(0xFFD5FF40),
  });

  static const List<PredefinedAvatar> all = [
    PredefinedAvatar(
      id: 'laptop',
      label: 'Laptop',
      icon: Icons.laptop_mac_rounded,
      accentColor: Color(0xFFD5FF40),
    ),
    PredefinedAvatar(
      id: 'desktop',
      label: 'Desktop Monitor',
      icon: Icons.desktop_windows_rounded,
      accentColor: Color(0xFFD5FF40),
    ),
    PredefinedAvatar(
      id: 'smartphone',
      label: 'Smartphone',
      icon: Icons.phone_android_rounded,
      accentColor: Color(0xFFD5FF40),
    ),
    PredefinedAvatar(
      id: 'tablet',
      label: 'Tablet',
      icon: Icons.tablet_mac_rounded,
      accentColor: Color(0xFFD5FF40),
    ),
    PredefinedAvatar(
      id: 'game_controller',
      label: 'Game Controller',
      icon: Icons.sports_esports_rounded,
      accentColor: Color(0xFFD5FF40),
    ),
    PredefinedAvatar(
      id: 'headphones',
      label: 'Headphones',
      icon: Icons.headphones_rounded,
      accentColor: Color(0xFFD5FF40),
    ),
    PredefinedAvatar(
      id: 'robot',
      label: 'Robot',
      icon: Icons.smart_toy_rounded,
      accentColor: Color(0xFFD5FF40),
    ),
    PredefinedAvatar(
      id: 'futuristic_robot',
      label: 'Futuristic Robot',
      icon: Icons.precision_manufacturing_rounded,
      accentColor: Color(0xFFD5FF40),
    ),
    PredefinedAvatar(
      id: 'fox',
      label: 'Fox',
      icon: Icons.cruelty_free_rounded,
      accentColor: Color(0xFFD5FF40),
    ),
    PredefinedAvatar(
      id: 'cat',
      label: 'Cat',
      icon: Icons.pets_rounded,
      accentColor: Color(0xFFD5FF40),
    ),
    PredefinedAvatar(
      id: 'leaf',
      label: 'Leaf',
      icon: Icons.eco_rounded,
      accentColor: Color(0xFFD5FF40),
    ),
    PredefinedAvatar(
      id: 'default_person',
      label: 'Default Person',
      icon: Icons.person_rounded,
      accentColor: Color(0xFFD5FF40),
    ),
  ];

  static PredefinedAvatar findById(String id) {
    return all.firstWhere(
      (a) => a.id == id,
      orElse: () => all.first,
    );
  }
}
