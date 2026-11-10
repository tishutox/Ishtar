import 'dart:typed_data';

import 'media_file_io_stub.dart'
    if (dart.library.io) 'media_file_io_io.dart' as impl;

/// Reads the bytes of a locally stored Ishtar media file.
Future<Uint8List> readMediaFile(String path) => impl.readMediaFile(path);

/// Writes [bytes] to [path], creating parent directories as needed.
Future<void> writeMediaFile(String path, Uint8List bytes) =>
    impl.writeMediaFile(path, bytes);
