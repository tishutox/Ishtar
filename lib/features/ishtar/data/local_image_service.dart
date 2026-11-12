import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';

/// On-device Stable Diffusion (SD-Turbo) image generation via ONNX Runtime.
///
/// This is the foundation: model download and storage. The actual inference
/// (tokenizer + scheduler + UNet/VAE through `onnxruntime`) is the next
/// iteration and is not wired yet — see [generateImage].
class LocalImageService {
  LocalImageService._();
  static final LocalImageService instance = LocalImageService._();

  /// Public ONNX export of SD-Turbo (fp16, static shapes, pruned ops).
  /// `gated: false`, so no Hugging Face token is required. 512x512, 1 step.
  /// License: Stability AI Non-Commercial Research Community License.
  static const String _baseUrl =
      'https://huggingface.co/webnn/sd-turbo-webnn/resolve/main';

  static const String _textEncoderName = 'text_encoder_model_f16.onnx';
  static const String _unetName = 'unet_model_f16.onnx';
  static const String _vaeName = 'vae_decoder_model_f16.onnx';
  static const String _tokenizerName = 'tokenizer.json';

  Future<Directory> _modelDir() async {
    final docs = await getApplicationDocumentsDirectory();
    return Directory('${docs.path}/ishtar_sd');
  }

  Future<File> _file(String name) async {
    final dir = await _modelDir();
    return File('${dir.path}/$name');
  }

  /// Whether every model file has finished downloading.
  Future<bool> isDownloaded() async {
    for (final name in _fileNames) {
      if (!(await _file(name)).existsSync()) return false;
    }
    return true;
  }

  /// Downloads any missing model files, reporting overall [onProgress] (0..1).
  ///
  /// The four files total ~2 GB (the fp16 UNet is the bulk), so this is meant
  /// to run over Wi-Fi and be cancellable by the caller.
  Future<void> ensureDownloaded({
    void Function(double progress)? onProgress,
  }) async {
    final dir = await _modelDir();
    await dir.create(recursive: true);

    // Clear leftover partial downloads from an earlier interrupted run.
    for (final name in _fileNames) {
      final part = File('${dir.path}/$name.part');
      if (part.existsSync()) {
        try {
          await part.delete();
        } catch (_) {}
      }
    }

    var done = 0;
    for (final (remotePath, name) in _remoteEntries) {
      final file = await _file(name);
      if (file.existsSync()) {
        done++;
        continue;
      }
      await _download(
        '$_baseUrl/$remotePath',
        file,
        onProgress: (p) => onProgress?.call((done + p) / _remoteEntries.length),
      );
      done++;
    }
  }

  static const List<String> _fileNames = [
    _textEncoderName,
    _unetName,
    _vaeName,
    _tokenizerName,
  ];

  static const List<(String, String)> _remoteEntries = [
    ('onnx/$_textEncoderName', _textEncoderName),
    ('onnx/$_unetName', _unetName),
    ('onnx/$_vaeName', _vaeName),
    ('tokenizer/$_tokenizerName', _tokenizerName),
  ];

  /// Downloads [url] into [file], reporting [onProgress] (0..1).
  Future<File> _download(
    String url,
    File file, {
    void Function(double progress)? onProgress,
  }) async {
    final part = File('${file.path}.part');

    final request = http.Request('GET', Uri.parse(url));
    final client = http.Client();
    try {
      final streamed = await client
          .send(request)
          .timeout(const Duration(seconds: 60));
      final total = streamed.contentLength ?? 0;
      var received = 0;
      final sink = part.openWrite();
      try {
        await for (final chunk
            in streamed.stream.timeout(const Duration(seconds: 30))) {
          received += chunk.length;
          sink.add(chunk);
          if (total > 0 && onProgress != null) {
            onProgress(received / total);
          }
        }
      } finally {
        await sink.close();
      }
    } catch (_) {
      if (part.existsSync()) {
        try {
          await part.delete();
        } catch (_) {}
      }
      rethrow;
    } finally {
      client.close();
    }

    if (file.existsSync()) {
      await file.delete();
    }
    await part.rename(file.path);
    return file;
  }

  /// Generates an image from [prompt] on-device.
  ///
  /// NOT IMPLEMENTED YET — model download/storage is in place, but the
  /// tokenizer, Euler scheduler and the ONNX UNet/VAE inference loop are the
  /// next iteration. Do not wire this into the send flow until it works.
  Future<Uint8List> generateImage(String prompt) {
    throw UnimplementedError(
      'On-device image generation is not wired yet (iteration 1).',
    );
  }
}
