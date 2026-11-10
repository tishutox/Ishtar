import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:win32/win32.dart';

void registerAppProtocol() {
  if (defaultTargetPlatform != TargetPlatform.windows) return;

  const prefix = r'SOFTWARE\Classes\lumiiquest';
  final command = '"${Platform.resolvedExecutable}" "%1"';
  _setRegistryValue(prefix, '', 'URL:Ishtar');
  _setRegistryValue(prefix, 'URL Protocol', '');
  _setRegistryValue('$prefix\\shell\\open\\command', '', command);
}

void _setRegistryValue(String key, String valueName, String data) {
  final keyPointer = key.toPcwstr();
  final namePointer = valueName.toPcwstr();
  final dataPointer = data.toPcwstr();
  try {
    RegSetKeyValue(
      HKEY_CURRENT_USER,
      keyPointer,
      namePointer,
      REG_SZ,
      dataPointer,
      data.length * 2 + 2,
    );
  } finally {
    free(keyPointer);
    free(namePointer);
    free(dataPointer);
  }
}
