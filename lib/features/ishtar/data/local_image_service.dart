import 'dart:async';
import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:http/http.dart' as http;
import 'package:image/image.dart' as img;
import 'package:onnxruntime/onnxruntime.dart';
import 'package:path_provider/path_provider.dart';

import 'clip_tokenizer.dart';

/// On-device Stable Diffusion (SD-Turbo) image generation via ONNX Runtime.
///
/// ITERATION 1 — the tokenizer is verified locally, but the scheduler
/// timesteps, ONNX tensor names and VAE scaling below are best-effort and MUST
/// be validated on-device against the actual `webnn/sd-turbo-webnn` files.
class LocalImageService {
  LocalImageService._();
  static final LocalImageService instance = LocalImageService._();

  static const String _baseUrl =
      'https://huggingface.co/webnn/sd-turbo-webnn/resolve/main';

  static const String _textEncoderName = 'text_encoder_model_f16.onnx';
  static const String _unetName = 'unet_model_f16.onnx';
  static const String _vaeName = 'vae_decoder_model_f16.onnx';
  static const String _tokenizerName = 'tokenizer.json';

  final Map<String, OrtSession> _sessions = {};

  // ---------------------------------------------------------------------
  // Model download & storage
  // ---------------------------------------------------------------------

  Future<Directory> _modelDir() async {
    final docs = await getApplicationDocumentsDirectory();
    return Directory('${docs.path}/ishtar_sd');
  }

  Future<File> _file(String name) async {
    final dir = await _modelDir();
    return File('${dir.path}/$name');
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

  Future<bool> isDownloaded() async {
    for (final name in _fileNames) {
      if (!(await _file(name)).existsSync()) return false;
    }
    return true;
  }

  Future<void> ensureDownloaded({
    void Function(double progress)? onProgress,
  }) async {
    final dir = await _modelDir();
    await dir.create(recursive: true);
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

  // ---------------------------------------------------------------------
  // Inference (ITERATION 1 — untested on-device)
  // ---------------------------------------------------------------------

  Future<OrtSession> _session(String name) async {
    final cached = _sessions[name];
    if (cached != null) return cached;
    OrtEnv.instance.init();
    final file = await _file(name);
    final options = OrtSessionOptions()
      ..setIntraOpNumThreads(4)
      ..setSessionGraphOptimizationLevel(GraphOptimizationLevel.ortEnableAll);
    final session = OrtSession.fromFile(file, options);
    _sessions[name] = session;
    return session;
  }

  Future<Uint8List> generateImage(String prompt) async {
    await ensureDownloaded();

    final tokenizerJson = await _file(_tokenizerName).then((f) => f.readAsString());
    final tokenizer = ClipTokenizer.fromJson(tokenizerJson);
    final inputIds = tokenizer.tokenize(prompt);

    // 1) Text encoder: input_ids [1,77] -> last_hidden_state [1,77,1024].
    final encoder = await _session(_textEncoderName);
    // WebNN export expects int32 for input_ids (not the diffusers int64).
    final encInput = OrtValueTensor.createTensorWithDataList(
      Int32List.fromList(inputIds),
      [1, 77],
    );
    final encOutputs = encoder.run(
      OrtRunOptions(),
      {encoder.inputNames.first: encInput},
    );
    final textEmb = _toFloat32(encOutputs[0]?.value);
    encInput.release();
    for (final o in encOutputs) {
      o?.release();
    }

    // 2) Random latent [1,4,64,64] (gaussian).
    final latent = _randn(4 * 64 * 64);

    // 3) UNet: single denoising step.
    //    ITERATION-1 TODO: verify the SD-Turbo timestep schedule. SD-Turbo
    //    runs EulerAncestralDiscrete with `timestep_spacing="trailing"` and
    //    1..4 steps; below we use t=999 and a plain DDPM epsilon->x0 step.
    final unet = await _session(_unetName);
    final unetInputs = _unetInputs(unet, latent, 999, textEmb);
    final unetOutputs = unet.run(OrtRunOptions(), unetInputs);
    final noise = _toFloat32(unetOutputs[0]?.value);
    for (final v in unetInputs.values) {
      v.release();
    }
    for (final o in unetOutputs) {
      o?.release();
    }

    // 4) Denoise to x0.
    final denoised = _denoise(latent, noise, 999);

    // 5) VAE decoder: latent_sample [1,4,64,64] -> sample [1,3,512,512].
    //    SD VAE latent scale factor 0.18215.
    final vae = await _session(_vaeName);
    final vaeInput = OrtValueTensor.createTensorWithDataList(
      _scaleBy(denoised, 1 / 0.18215),
      [1, 4, 64, 64],
    );
    final vaeOutputs = vae.run(
      OrtRunOptions(),
      {vae.inputNames.first: vaeInput},
    );
    final image = vaeOutputs[0]?.value;
    vaeInput.release();
    for (final o in vaeOutputs) {
      o?.release();
    }

    // 6) VAE output [1,3,512,512] in [-1,1] -> RGB JPEG bytes.
    return _vaeToJpeg(image);
  }

  /// Maps the UNet's three inputs by name. The names differ across ONNX
  /// exports, so match heuristically on the lower-cased name.
  Map<String, OrtValue> _unetInputs(
    OrtSession session,
    Float32List latent,
    int timestep,
    Float32List textEmb,
  ) {
    final inputs = <String, OrtValue>{};
    for (final name in session.inputNames) {
      final lower = name.toLowerCase();
      if (lower.contains('sample') || lower.contains('latent')) {
        inputs[name] =
            OrtValueTensor.createTensorWithDataList(latent, [1, 4, 64, 64]);
      } else if (lower.contains('time')) {
        inputs[name] = OrtValueTensor.createTensorWithDataList(
          Int32List.fromList([timestep]),
          [1],
        );
      } else {
        inputs[name] =
            OrtValueTensor.createTensorWithDataList(textEmb, [1, 77, 1024]);
      }
    }
    return inputs;
  }

  /// DDPM epsilon-prediction -> x0.
  /// ITERATION-1 TODO: replace with the exact SD-Turbo sigma schedule.
  Float32List _denoise(Float32List latent, Float32List noise, int timestep) {
    const steps = 1000;
    const betaStart = 0.00085;
    const betaEnd = 0.012;
    final alphaBar = List<double>.filled(steps, 1.0);
    for (var i = 0; i < steps; i++) {
      final beta = betaStart + (betaEnd - betaStart) * i / (steps - 1);
      final alpha = 1 - beta;
      alphaBar[i] = (i == 0 ? 1 : alphaBar[i - 1]) * alpha;
    }
    final ab = alphaBar[timestep];
    final sqrtAb = math.sqrt(ab);
    final sqrtOneMinusAb = math.sqrt(1 - ab);
    final out = Float32List(latent.length);
    for (var i = 0; i < latent.length; i++) {
      out[i] = (latent[i] - sqrtOneMinusAb * noise[i]) / sqrtAb;
    }
    return out;
  }

  Float32List _scaleBy(Float32List data, double factor) {
    final out = Float32List(data.length);
    for (var i = 0; i < data.length; i++) {
      out[i] = data[i] * factor;
    }
    return out;
  }

  Uint8List _vaeToJpeg(dynamic vaeOutput) {
    final flat = _toFloat32(vaeOutput); // [1,3,512,512]
    const c = 3;
    const h = 512;
    const w = 512;
    final rgb = Uint8List(h * w * c);
    for (var y = 0; y < h; y++) {
      for (var x = 0; x < w; x++) {
        for (var ch = 0; ch < c; ch++) {
          final v = ((flat[ch * h * w + y * w + x] + 1) / 2 * 255)
              .clamp(0, 255);
          rgb[(y * w + x) * c + ch] = v.toInt();
        }
      }
    }
    final image = img.Image.fromBytes(
      width: w,
      height: h,
      bytes: rgb.buffer,
      order: img.ChannelOrder.rgb,
    );
    return img.encodeJpg(image, quality: 90);
  }

  Float32List _randn(int count) {
    final rnd = math.Random();
    final out = Float32List(count);
    for (var i = 0; i < count; i += 2) {
      final u1 = math.max(rnd.nextDouble(), 1e-9);
      final u2 = rnd.nextDouble();
      final r = math.sqrt(-2 * math.log(u1));
      out[i] = r * math.cos(2 * math.pi * u2);
      if (i + 1 < count) {
        out[i + 1] = r * math.sin(2 * math.pi * u2);
      }
    }
    return out;
  }

  Float32List _toFloat32(dynamic value) {
    final flat = <double>[];
    void rec(dynamic v) {
      if (v is List) {
        for (final e in v) {
          rec(e);
        }
      } else if (v is num) {
        flat.add(v.toDouble());
      }
    }

    rec(value);
    return Float32List.fromList(flat);
  }

  void dispose() {
    for (final s in _sessions.values) {
      s.release();
    }
    _sessions.clear();
  }
}
