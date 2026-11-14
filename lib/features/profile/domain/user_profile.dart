import 'package:flutter/material.dart';

enum BioAlignment {
  left,
  center,
  right,
  justify;

  String get label => switch (this) {
    BioAlignment.left => 'Left',
    BioAlignment.center => 'Center',
    BioAlignment.right => 'Right',
    BioAlignment.justify => 'Justify',
  };

  TextAlign get textAlign => switch (this) {
    BioAlignment.left => TextAlign.left,
    BioAlignment.center => TextAlign.center,
    BioAlignment.right => TextAlign.right,
    BioAlignment.justify => TextAlign.justify,
  };

  static BioAlignment fromDatabase(String? value) {
    return BioAlignment.values.firstWhere(
      (alignment) => alignment.name == value,
      orElse: () => BioAlignment.left,
    );
  }
}

class ProfileMention {
  const ProfileMention({
    required this.username,
    required this.displayName,
    required this.tag,
    this.avatarUrl,
  });

  final String username;
  final String displayName;
  final String tag;
  final String? avatarUrl;
}

class UserProfile {
  const UserProfile({
    required this.id,
    required this.username,
    required this.displayName,
    required this.bio,
    required this.bioAlignment,
    required this.mentions,
    required this.backgroundColor,
    required this.accentColor,
    this.avatarUrl,
    this.bannerUrl,
    this.zodiac,
  });

  final String id;
  final String username;
  final String displayName;
  final String bio;
  final BioAlignment bioAlignment;
  final String? avatarUrl;
  final String? bannerUrl;
  final String? zodiac;
  final List<ProfileMention> mentions;
  final Color backgroundColor;
  final Color accentColor;
}

class ProfileDraft {
  const ProfileDraft({
    required this.displayName,
    required this.bio,
    required this.bioAlignment,
    required this.avatarUrl,
    required this.bannerUrl,
    required this.mentions,
    required this.backgroundColor,
    required this.accentColor,
  });

  final String displayName;
  final String bio;
  final BioAlignment bioAlignment;
  final String? avatarUrl;
  final String? bannerUrl;
  final List<ProfileMention> mentions;
  final Color backgroundColor;
  final Color accentColor;
}

Color profileColorFromHex(String? value, Color fallback) {
  final normalized = value?.trim().replaceFirst('#', '');
  if (normalized == null || !RegExp(r'^[0-9A-Fa-f]{6}$').hasMatch(normalized)) {
    return fallback;
  }
  return Color(int.parse('FF$normalized', radix: 16));
}

String profileColorToHex(Color color) {
  final rgb = color.toARGB32() & 0x00FFFFFF;
  return '#${rgb.toRadixString(16).padLeft(6, '0').toUpperCase()}';
}
