import 'dart:io';
import 'dart:typed_data';

Future<Uint8List> readMediaFile(String path) => File(path).readAsBytes();

Future<void> writeMediaFile(String path, Uint8List bytes) async {
  final file = File(path);
  await file.parent.create(recursive: true);
  await file.writeAsBytes(bytes, flush: true);
}
