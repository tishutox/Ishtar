import 'dart:io';

import 'package:flutter_llama/flutter_llama.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';

/// On-device LLM inference for Fern (llama.cpp via flutter_llama).
///
/// Downloads a small GGUF model on first use and runs completions locally, so
/// Fern works without any server or API key. The model URL is a single constant
/// and can be swapped for any other GGUF (e.g. an abliterated/uncensored model).
class LocalLlmService {
  LocalLlmService._();
  static final LocalLlmService instance = LocalLlmService._();

  /// 3B GGUF (~1.9 GB). Hermes-3 is steerable/uncensored (good for adult
  /// roleplay); public and ungated. Swap this for another GGUF URL to use a
  /// different model.
  static const String modelUrl =
      'https://huggingface.co/bartowski/Hermes-3-Llama-3.2-3B-GGUF/resolve/main/Hermes-3-Llama-3.2-3B-Q4_K_M.gguf';
  static const String _modelFileName = 'fern_model_v2.gguf';
  static const String _legacyModelFileName = 'fern_model.gguf';

  FlutterLlama get _llama => FlutterLlama.instance;

  /// Whether on-device inference can run on this platform.
  bool get isSupported => FlutterLlama.isSupported;

  /// Whether a model is currently loaded into memory.
  bool get isModelLoaded => _llama.isModelLoaded;

  /// Whether Fern currently uses the on-device (NSFW) model instead of the
  /// (SFW) cloud fallback. Toggled from the chat app bar.
  bool useLocal = false;

  /// Whether Fern keeps its memory between chats. When turned off in Settings
  /// ("Keep Memories" off), the model context is cleared before every local
  /// generation so each chat starts fresh.
  bool keepMemories = true;

  Future<File> modelFile() async {
    final dir = await getApplicationDocumentsDirectory();
    return File('${dir.path}/$_modelFileName');
  }

  /// Whether the model file has finished downloading.
  Future<bool> isDownloaded() async => (await modelFile()).existsSync();

  /// Downloads the model, reporting [onProgress] (0..1). Returns the file.
  Future<File> downloadModel({void Function(double progress)? onProgress}) async {
    final file = await modelFile();
    final part = File('${file.path}.part');

    final request = http.Request('GET', Uri.parse(modelUrl));
    final client = http.Client();
    final streamed = await client.send(request);
    final total = streamed.contentLength ?? 0;
    var received = 0;
    final sink = part.openWrite();
    try {
      await for (final chunk in streamed.stream) {
        received += chunk.length;
        sink.add(chunk);
        if (total > 0 && onProgress != null) {
          onProgress(received / total);
        }
      }
    } finally {
      await sink.close();
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

  /// Downloads (if needed) and loads the model into memory.
  Future<bool> ensureLoaded({void Function(double progress)? onProgress}) async {
    if (isModelLoaded) return true;
    final file = await modelFile();
    // Free space from the previous model when the model was switched.
    if (!file.existsSync()) {
      final dir = await getApplicationDocumentsDirectory();
      final legacy = File('${dir.path}/$_legacyModelFileName');
      if (legacy.existsSync()) {
        try {
          await legacy.delete();
        } catch (_) {}
      }
    }
    if (!file.existsSync()) {
      await downloadModel(onProgress: onProgress);
    }
    return _llama.loadModel(
      LlamaConfig(
        modelPath: file.path,
        nThreads: 4,
        nGpuLayers: 0, // CPU-only for broad device compatibility
        contextSize: 4096,
        batchSize: 4096, // must be >= the full prompt (system + history) or llama.cpp aborts
        useGpu: false,
        verbose: false,
      ),
    );
  }

  /// Runs a chat completion with the loaded model.
  ///
  /// Uses the 1.1 `generate` path (the 1.2 chat engine needs native `core.*`
  /// methods the Android plugin does not implement) and applies the Llama-3.2
  /// chat template manually.
  Future<String> chat(List<Map<String, String>> messages) async {
    if (!keepMemories) {
      await _llama.clearContext();
    }
    final response = await _llama.generate(
      GenerationParams(
        prompt: _renderLlama32Prompt(messages),
        temperature: 0.8,
        topP: 0.95,
        topK: 40,
        maxTokens: 256,
        repeatPenalty: 1.1,
      ),
    );
    return response.text.trim();
  }

  String _renderLlama32Prompt(List<Map<String, String>> messages) {
    final buffer = StringBuffer('<|begin_of_text|>');
    for (final m in messages) {
      final role = m['role'] ?? 'user';
      final content = m['content'] ?? '';
      buffer.write('<|start_header_id|>$role<|end_header_id|>\n\n$content<|eot_id|>');
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
