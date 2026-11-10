import 'dart:async';
import 'dart:io';

import 'package:flutter_llama/flutter_llama.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';

/// On-device LLM inference for Ishtar (llama.cpp via flutter_llama).
///
/// Runs a single uncensored GGUF model (Hermes-3) for every AI type — the
/// earlier two-model split (Qwen knowledge + Hermes roleplay) was removed.
class LocalLlmService {
  LocalLlmService._();
  static final LocalLlmService instance = LocalLlmService._();

  /// Uncensored roleplay model (Hermes-3, 3B) used for all local chats. Reuses
  /// the existing file name so users who already downloaded it keep it.
  static const String modelUrl =
      'https://huggingface.co/bartowski/Hermes-3-Llama-3.2-3B-GGUF/resolve/main/Hermes-3-Llama-3.2-3B-Q4_K_M.gguf';
  static const String _modelFileName = 'ishtar_model_v2.gguf';

  // Stale files from the earlier two-model setup, removed on load.
  static const String _legacyModelFileName = 'ishtar_model.gguf';
  static const String _oldKnowledgeModelFileName = 'ishtar_knowledge_v1.gguf';
  static const String _knowledgeModelFileName = 'ishtar_knowledge_v2.gguf';

  FlutterLlama get _llama => FlutterLlama.instance;

  /// Whether on-device inference can run on this platform.
  bool get isSupported => FlutterLlama.isSupported;

  /// Whether a model is currently loaded into memory.
  bool get isModelLoaded => _llama.isModelLoaded;

  /// Whether Ishtar currently uses an on-device model instead of the (SFW) cloud
  /// fallback. Toggled from the chat app bar.
  bool useLocal = false;

  /// Kept for the Settings "Keep Memories" toggle. The native KV cache is now
  /// always cleared inside the native `generate` bridge before every local
  /// generation — the full bounded history is re-sent in the prompt each turn,
  /// so persisting the cache would duplicate it and overflow the context.
  bool keepMemories = true;

  Future<File> _modelFile(String fileName) async {
    final dir = await getApplicationDocumentsDirectory();
    return File('${dir.path}/$fileName');
  }

  /// Whether the local (Hermes) model has finished downloading.
  Future<bool> isDownloaded() async =>
      (await _modelFile(_modelFileName)).existsSync();

  /// Deletes stale model files and leftover partial (`.part`) downloads so a
  /// corrupt or outdated model never blocks loading.
  Future<void> _cleanupStaleModels() async {
    final dir = await getApplicationDocumentsDirectory();
    final staleNames = <String>{
      _legacyModelFileName,
      _oldKnowledgeModelFileName,
      _knowledgeModelFileName,
      '$_legacyModelFileName.part',
      '$_oldKnowledgeModelFileName.part',
      '$_knowledgeModelFileName.part',
      '$_modelFileName.part',
    };
    for (final name in staleNames) {
      final file = File('${dir.path}/$name');
      if (file.existsSync()) {
        try {
          await file.delete();
        } catch (_) {}
      }
    }
  }

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
      // Bound the connect/header phase so a stalled server never hangs the UI.
      final streamed = await client
          .send(request)
          .timeout(const Duration(seconds: 60));
      final total = streamed.contentLength ?? 0;
      var received = 0;
      final sink = part.openWrite();
      try {
        // Per-chunk idle timeout: a live download keeps flowing, a stalled one
        // fails fast instead of spinning forever.
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
      // A failed/interrupted download must never leave a partial file behind.
      if (part.existsSync()) {
        try {
          await part.delete();
        } catch (_) {}
      }
      rethrow;
    } finally {
      client.close();
    }

    // Only expose the model once the download is complete (a partial file must
    // never be mistaken for a loadable model).
    if (file.existsSync()) {
      await file.delete();
    }
    await part.rename(file.path);
    return file;
  }

  /// Downloads (if needed) and loads the single Hermes model into memory.
  Future<bool> ensureLoaded({
    void Function(double progress)? onProgress,
  }) async {
    if (_llama.isModelLoaded) {
      return true;
    }

    final file = await _modelFile(_modelFileName);

    // Ishtar's model "reset": remove stale models and leftover partial downloads
    // so a corrupt or outdated file never blocks loading.
    await _cleanupStaleModels();

    if (!file.existsSync()) {
      await _download(modelUrl, file, onProgress: onProgress);
    }

    return _llama.loadModel(
      LlamaConfig(
        modelPath: file.path,
        nThreads: 4,
        nGpuLayers: 0, // CPU-only (Vulkan build not yet working on Windows)
        contextSize: 4096,
        batchSize:
            4096, // must be >= the full prompt (system + history) or llama.cpp aborts
        useGpu: false,
        verbose: false,
      ),
    );
  }

  /// Runs a chat completion with the Hermes model.
  ///
  /// Uses the 1.1 `generate` path (the 1.2 chat engine needs native `core.*`
  /// methods the Android plugin does not implement) and applies the Llama-3.2
  /// chat template manually.
  Future<String> chat(List<Map<String, String>> messages) async {
    // The native bridge clears the KV cache before every generation, so the
    // full bounded history (already re-sent in [messages]) never duplicates
    // itself in the context. No separate clearContext call here — that would
    // run on the Flutter main thread and could block behind a running decode.
    print('[Ishtar] chat: isModelLoaded=${_llama.isModelLoaded}');
    if (!_llama.isModelLoaded) {
      print('[Ishtar] chat: loading model...');
      await ensureLoaded();
      print('[Ishtar] chat: model loaded');
    }
    try {
      print('[Ishtar] chat: generating (maxTokens=256)...');
      final response = await _llama
          .generate(
            GenerationParams(
              prompt: _renderLlama32Prompt(messages),
              temperature: 0.8,
              topP: 0.95,
              topK: 40,
              maxTokens: 256,
              repeatPenalty: 1.1,
            ),
          )
          .timeout(const Duration(seconds: 300));
      final text = response.text.trim();
      print('[Ishtar] chat: done (${text.length} chars)');
      if (text.isEmpty) {
        throw Exception(
          'The on-device model returned an empty reply. Please try again.',
        );
      }
      return text;
    } on TimeoutException {
      print('[Ishtar] chat: TIMEOUT');
      throw Exception(
        'The on-device model took too long to answer. Please try again.',
      );
    }
  }

  /// Chat template for the Llama-based roleplay model (Hermes-3).
  String _renderLlama32Prompt(List<Map<String, String>> messages) {
    final buffer = StringBuffer('<|begin_of_text|>');
    for (final m in messages) {
      final role = m['role'] ?? 'user';
      final content = m['content'] ?? '';
      buffer.write(
        '<|start_header_id|>$role<|end_header_id|>\n\n$content<|eot_id|>',
      );
    }
    buffer.write('<|start_header_id|>assistant<|end_header_id|>\n\n');
    return buffer.toString();
  }

  /// Returns the native crash log (if any) written by the native crash handler.
  Future<String?> readCrashLog() async {
    try {
      final dir = await getApplicationSupportDirectory();
      final file = File('${dir.path}/crash.log');
      if (!file.existsSync()) return null;
      return await file.readAsString();
    } catch (_) {
      return null;
    }
  }
}
