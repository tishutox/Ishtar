import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'models/llama_config.dart';
import 'models/generation_params.dart';
import 'models/llama_response.dart';
import 'models/model_source.dart';
import 'models/preset_model.dart';
import 'services/model_manager.dart';
import 'backend/backend.dart';
import 'backend/channel_backend.dart';
import 'backend/select.dart';
import 'chat/chat_engine.dart';
import 'chat/classify.dart';
import 'fit/device_fit.dart' as fit;
import 'fit/device_fit.dart' show ModelRef;
import 'lifecycle.dart';
import 'chat/families.dart' show templateFamily;
import 'models/chat.dart';

/// Main class for interacting with llama.cpp models
class FlutterLlama {
  static const MethodChannel _channel = MethodChannel('flutter_llama');

  static FlutterLlama? _instance;
  bool _isInitialized = false;
  bool _isModelLoaded = false;
  String? _modelPath;

  FlutterLlama._();

  /// Get singleton instance
  static FlutterLlama get instance {
    _instance ??= FlutterLlama._();
    return _instance!;
  }

  static LlamaBackend? _backend;

  /// The native side for this platform (1.2): method channels on Android / iOS / macOS, FFI on Windows / Linux,
  /// none on the web.
  static LlamaBackend get backend => _backend ??= createPlatformBackend();

  /// Replaces the backend (tests, custom builds). null restores the platform one.
  @visibleForTesting
  static set debugBackend(LlamaBackend? b) {
    _backend = b;
    _instance = null;
  }

  /// Whether on-device models can run here: false on the web and when the native library is missing.
  static bool get isSupported => !kIsWeb && backend.isSupported;

  LlamaChatEngine? _chat;
  LlamaChatEngine get _engine => _chat ??= LlamaChatEngine(backend);

  LlamaLifecycle _policy = LlamaLifecycle();
  LifecycleWatcher? _watcher;
  LlamaConfig? _lastConfig;
  bool _autoUnloaded = false;
  int _busy = 0;

  /// When the model is unloaded on its own: in the background, after an idle timeout, on memory pressure. The next
  /// call reloads it.
  LlamaLifecycle get lifecycle => _policy;
  set lifecycle(LlamaLifecycle p) {
    _policy = p;
    _watcher?.detach();
    _watcher = null;
    if (_isModelLoaded) _watch();
  }

  void _watch() {
    _watcher ??= LifecycleWatcher(_policy, unload: _autoUnload, isBusy: () => _busy > 0)..attach();
    _watcher!.touch();
  }

  Future<void> _autoUnload(String why) async {
    if (!_isModelLoaded) return;
    if (kDebugMode) print('[FlutterLlama] Unloading ($why); the next call reloads the model');
    if (_busy > 0) await stopGeneration();
    await unloadModel();
    _autoUnloaded = true;
  }

  Future<T> _use<T>(Future<T> Function() f) async {
    if (!isSupported) throw const UnsupportedPlatform();
    if (_autoUnloaded && !_isModelLoaded && _lastConfig != null) await loadModel(_lastConfig!);
    _busy++;
    try {
      return await f();
    } finally {
      _busy--;
      _watcher?.touch();
    }
  }

  /// A chat reply for [messages]; with [ChatParams.tools] the reply may be [ChatResult.toolCalls] instead of text.
  /// Throws [UnsupportedPlatform] where nothing runs on device, [ModelNotLoaded] before a load, and
  /// [ToolParseFailed] when a tool call does not parse after the repair retry.
  Future<ChatResult> chat(List<LlamaMessage> messages, [ChatParams params = const ChatParams()]) =>
      _use(() => _engine.chat(messages, params));

  /// [chat] as a stream: [ChatText] pieces, then [ChatToolCalls] when the model called tools, then [ChatDone].
  Stream<ChatChunk> chatStream(List<LlamaMessage> messages, [ChatParams params = const ChatParams()]) async* {
    if (!isSupported) throw const UnsupportedPlatform();
    if (_autoUnloaded && !_isModelLoaded && _lastConfig != null) await loadModel(_lastConfig!);
    _busy++;
    try {
      yield* _engine.chatStream(messages, params);
    } finally {
      _busy--;
      _watcher?.touch();
    }
  }

  /// One of [labels] for [text], with probabilities. The label log-probability method needs no grammar and decodes
  /// the shared prompt once; the embedding method needs a model loaded with embeddings and examples per label.
  Future<ClassifyResult> classify(String text, List<String> labels, {ClassifyParams params = const ClassifyParams()}) =>
      _use(() => _engine.classify(text, labels, params));

  /// Tokens of [text] with the loaded model's tokenizer.
  Future<int> countTokens(String text) => _use(() => backend.countTokens(text));

  /// Tokens of the rendered chat prompt (tools and template included).
  Future<int> countChatTokens(List<LlamaMessage> messages, {ChatParams? params}) =>
      _use(() async => backend.countTokens(await _engine.render(messages, params ?? const ChatParams())));

  /// A mean-pooled, L2-normalised embedding (models loaded with embeddings).
  Future<List<double>> embed(String text) => _use(() => backend.embed(text));

  /// What the loaded model is; null when none is loaded. ([getModelInfo] stays as the 1.1 raw map.)
  Future<ModelInfo?> modelInfo() async {
    if (!isSupported || !await backend.isLoaded) return null;
    final f = await backend.facts();
    final t = await _engine.traits();
    final gguf = <String, String>{};
    for (final k in const ['general.name', 'general.license', 'general.basename', 'general.size_label', 'general.organization', 'general.base_model.0.name', 'general.languages']) {
      final v = await backend.meta(k);
      if (v != null) gguf[k] = v;
    }
    // llama.cpp's file-type name: "Q4_K - Medium" → Q4_K_M, "Q8_0", "IQ4_XS - 4.25 bpw" → IQ4_XS, "F16", "BF16".
    final q = RegExp(r'\b(I?Q\d+_[A-Z0-9]+|BF16|F16|F32)(?: - (Medium|Small|Large))?').firstMatch(f.description);
    final quant = q == null ? f.description : '${q.group(1)}${q.group(2) == null ? '' : '_${q.group(2)![0]}'}';
    return ModelInfo(
      architecture: t.architecture ?? 'unknown',
      parameters: f.parameters,
      quantization: quant,
      contextLength: f.context,
      trainedContext: f.trainedContext,
      hasChatTemplate: f.hasTemplate,
      templateFamily: templateFamily(t.template, t.architecture),
      nativeToolCalls: t.nativeTools,
      fileSize: f.sizeBytes,
      description: f.description,
      gguf: gguf,
    );
  }

  /// Whether [model] fits this device now (RAM, disk for a download, platform).
  Future<DeviceFit> canLoad(ModelRef model) => fit.canLoad(model);

  /// Desktop (FFI) with the core library present: the 1.1 calls go through the backend. Otherwise they keep the
  /// 1.1 method-channel path (and its errors) unchanged.
  static bool get _viaBackend => backend is! ChannelBackend && backend.isSupported;

  /// Check if model is loaded
  bool get isModelLoaded => _isModelLoaded;

  /// Check if instance is initialized
  bool get isInitialized => _isInitialized;

  /// Get current model path
  String? get modelPath => _modelPath;

  /// Initialize and load a GGUF model
  /// 
  /// Returns true if successful, false otherwise
  Future<bool> loadModel(LlamaConfig config) async {
    try {
      if (kDebugMode) {
        print('[FlutterLlama] Loading model: ${config.modelPath}');
      }

      final bool? result;
      if (_viaBackend) {
        await backend.load(config.modelPath, contextSize: config.contextSize, gpuLayers: config.useGpu ? config.nGpuLayers : 0, threads: config.nThreads);
        result = true;
      } else {
        result = await _channel.invokeMethod<bool>(
          'loadModel',
          config.toMap(),
        );
      }

      _chat?.invalidate();
      _isModelLoaded = result ?? false;
      _isInitialized = _isModelLoaded;
      
      if (_isModelLoaded) {
        _modelPath = config.modelPath;
        _lastConfig = config;
        _autoUnloaded = false;
        _watch();
        if (kDebugMode) {
          print('[FlutterLlama] Model loaded successfully');
          print('[FlutterLlama] Config: $config');
        }
      } else {
        if (kDebugMode) {
          print('[FlutterLlama] Failed to load model');
        }
      }

      return _isModelLoaded;
    } catch (e) {
      if (kDebugMode) {
        print('[FlutterLlama] Error loading model: $e');
      }
      _isModelLoaded = false;
      _isInitialized = false;
      return false;
    }
  }

  /// Generate text from a prompt
  /// 
  /// Returns [LlamaResponse] with generated text and metadata
  Future<LlamaResponse> generate(GenerationParams params) async {
    if (!_isModelLoaded) {
      throw StateError('Model not loaded. Call loadModel() first.');
    }

    try {
      if (kDebugMode) {
        print('[FlutterLlama] Generating with params: $params');
      }

      final result = _viaBackend
          ? await _generateViaBackend(params)
          : await _channel.invokeMethod<Map<dynamic, dynamic>>(
              'generate',
              params.toMap(),
            );

      if (result == null) {
        throw Exception('Generation returned null result');
      }

      final response = LlamaResponse.fromMap(Map<String, dynamic>.from(result));
      
      if (kDebugMode) {
        print('[FlutterLlama] Generated: $response');
      }

      return response;
    } catch (e) {
      if (kDebugMode) {
        print('[FlutterLlama] Error generating: $e');
      }
      rethrow;
    }
  }

  /// Generate text as a stream (token by token)
  /// 
  /// Returns Stream of strings (individual tokens)
  Stream<String> generateStream(GenerationParams params) async* {
    if (!_isModelLoaded) {
      throw StateError('Model not loaded. Call loadModel() first.');
    }

    try {
      if (kDebugMode) {
        print('[FlutterLlama] Streaming generation with params: $params');
      }

      if (_viaBackend) {
        await for (final e in backend.generate(params.prompt, _sampling(params))) {
          if (e is String) yield e;
        }
        return;
      }

      // Set up event channel for streaming
      final eventChannel = EventChannel('flutter_llama/stream');
      
      // Send generation request
      await _channel.invokeMethod('generateStream', params.toMap());

      // Listen to token stream
      await for (final token in eventChannel.receiveBroadcastStream()) {
        if (token is String) {
          yield token;
        }
      }
    } catch (e) {
      if (kDebugMode) {
        print('[FlutterLlama] Error in streaming generation: $e');
      }
      rethrow;
    }
  }

  /// Unload the current model and free resources
  Future<void> unloadModel() async {
    try {
      if (kDebugMode) {
        print('[FlutterLlama] Unloading model');
      }

      if (_viaBackend) {
        await backend.unload();
      } else {
        await _channel.invokeMethod<void>('unloadModel');
      }
      
      _chat?.invalidate();
      _isModelLoaded = false;
      _modelPath = null;
      
      if (kDebugMode) {
        print('[FlutterLlama] Model unloaded successfully');
      }
    } catch (e) {
      if (kDebugMode) {
        print('[FlutterLlama] Error unloading model: $e');
      }
      rethrow;
    }
  }

  /// Get model information
  Future<Map<String, dynamic>?> getModelInfo() async {
    if (!_isModelLoaded) {
      return null;
    }

    try {
      final result = _viaBackend
          ? await _modelInfoViaBackend()
          : await _channel.invokeMethod<Map<dynamic, dynamic>>(
              'getModelInfo',
            );
      
      return result != null ? Map<String, dynamic>.from(result) : null;
    } catch (e) {
      if (kDebugMode) {
        print('[FlutterLlama] Error getting model info: $e');
      }
      return null;
    }
  }

  static RawSampling _sampling(GenerationParams p) => RawSampling(
        temperature: p.temperature,
        topP: p.topP,
        topK: p.topK,
        repeatPenalty: p.repeatPenalty,
        maxTokens: p.maxTokens,
        stop: p.stopSequences,
      );

  /// The 1.1 `generate` map, produced by the backend (desktop).
  Future<Map<dynamic, dynamic>> _generateViaBackend(GenerationParams params) async {
    final sw = Stopwatch()..start();
    final text = StringBuffer();
    var tokens = 0;
    await for (final e in backend.generate(params.prompt, _sampling(params))) {
      if (e is String) text.write(e);
      if (e is RawDone) tokens = e.completionTokens;
    }
    return {'text': text.toString(), 'tokensGenerated': tokens, 'generationTimeMs': sw.elapsedMilliseconds};
  }

  /// The 1.1 `getModelInfo` map (desktop).
  Future<Map<dynamic, dynamic>> _modelInfoViaBackend() async {
    final f = await backend.facts();
    return {'modelPath': _modelPath, 'nParams': f.parameters, 'contextSize': f.context, 'sizeBytes': f.sizeBytes, 'description': f.description};
  }

  /// Stop ongoing generation
  Future<void> stopGeneration() async {
    try {
      if (_viaBackend) {
        await backend.stop();
      } else {
        await _channel.invokeMethod<void>('stopGeneration');
      }
    } catch (e) {
      if (kDebugMode) {
        print('[FlutterLlama] Error stopping generation: $e');
      }
    }
  }

  /// Clear the model's KV cache so the next generation starts from a fresh
  /// context (no memory of previous generations).
  Future<void> clearContext() async {
    try {
      if (_viaBackend) {
        // Desktop FFI: the core does not expose a KV-cache clear yet; its
        // context is only reset by unload/reload.
      } else {
        await _channel.invokeMethod<void>('clearContext');
      }
    } catch (e) {
      if (kDebugMode) {
        print('[FlutterLlama] Error clearing context: $e');
      }
    }
  }

  /// Load model with automatic download from HuggingFace or Ollama
  /// 
  /// This method will:
  /// 1. Check if model is already downloaded
  /// 2. If not, download it from the specified source
  /// 3. Load the model into memory
  /// 
  /// Returns true if successful, false otherwise
  Future<bool> loadModelWithAutoDownload({
    required String modelId,
    ModelSource source = ModelSource.huggingFace,
    String? variant,
    String? specificFile,
    LlamaConfig? config,
    required DownloadProgressCallback onProgress,
    bool autoDownload = true,
  }) async {
    try {
      if (kDebugMode) {
        print('[FlutterLlama] Loading model with auto-download: $modelId');
      }
      
      // Create model manager
      final manager = ModelManager(
        modelId: modelId,
        source: source,
        variant: variant,
        specificFile: specificFile,
      );
      
      // Ensure model is loaded (with auto-download if needed)
      final modelPath = await manager.ensureModelLoaded(
        onProgress: onProgress,
        autoDownload: autoDownload,
      );
      
      if (kDebugMode) {
        print('[FlutterLlama] Model path: $modelPath');
      }
      
      // Create config or use provided one
      final llamaConfig = config ?? LlamaConfig(
        modelPath: modelPath,
        nThreads: 8,
        nGpuLayers: -1, // Use all GPU layers
        contextSize: 2048,
        batchSize: 512,
        useGpu: true,
        verbose: false,
      );
      
      // Load model into llama.cpp
      return await loadModel(llamaConfig.copyWith(modelPath: modelPath));
    } catch (e) {
      if (kDebugMode) {
        print('[FlutterLlama] Error loading model with auto-download: $e');
      }
      return false;
    }
  }
  
  /// Load preset model with automatic download
  /// 
  /// Convenience method for loading predefined models
  Future<bool> loadPresetModel({
    required PresetModel preset,
    LlamaConfig? config,
    required DownloadProgressCallback onProgress,
  }) async {
    return await loadModelWithAutoDownload(
      modelId: preset.id,
      source: preset.source,
      variant: preset.variant,
      specificFile: preset.files.isNotEmpty ? preset.files.first : null,
      config: config,
      onProgress: onProgress,
    );
  }
}





