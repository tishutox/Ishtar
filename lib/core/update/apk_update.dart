import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

class ApkUpdate {
  const ApkUpdate._();

  // Point this to your hosted release file (same file as the website download).
  static const String latestApkUrl =
      'https://tishutox.github.io/Amatsumara/downloads/lumii-quest-android-v1.0.86-arm64-v8a.apk';

  static Future<void> openLatestApk(BuildContext context) async {
    final uri = Uri.parse(latestApkUrl);
    final launched = await launchUrl(uri, mode: LaunchMode.externalApplication);

    if (!context.mounted) {
      return;
    }

    if (!launched) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('The APK link could not be opened.')),
      );
    }
  }
}
