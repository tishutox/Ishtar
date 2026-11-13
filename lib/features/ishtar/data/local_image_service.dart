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

  // ONNX TensorElementDataType values.
  static const int _kFloat32 = 1;
  static const int _kInt32 = 6;
  static const int _kFloat16 = 10;

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
      ..setIntraOpNumThreads(2)
      ..setSessionGraphOptimizationLevel(GraphOptimizationLevel.ortEnableBasic);
    final session = OrtSession.fromFile(file, options);
    _sessions[name] = session;
    return session;
  }

  void _releaseSession(String name) {
    final session = _sessions.remove(name);
    session?.release();
  }

  /// Records the current inference step to logcat and a small file so the
  /// crash point survives a native abort.
  Future<void> _checkpoint(String step) async {
    print('[Ishtar] local-image: $step');
    try {
      final dir = await getApplicationSupportDirectory();
      await File('${dir.path}/ishtar_img_step.txt').writeAsString(step);
    } catch (_) {}
  }

  static Future<String?> readLastStep() async {
    try {
      final dir = await getApplicationSupportDirectory();
      final file = File('${dir.path}/ishtar_img_step.txt');
      if (!file.existsSync()) return null;
      return await file.readAsString();
    } catch (_) {
      return null;
    }
  }

  Future<Uint8List> generateImage(String prompt) async {
    await ensureDownloaded();

    final tokenizerJson = await _file(_tokenizerName).then((f) => f.readAsString());
    final tokenizer = ClipTokenizer.fromJson(tokenizerJson);
    final inputIds = tokenizer.tokenize(prompt);
    await _checkpoint('tokenized');

    // 1) Text encoder: input_ids -> last_hidden_state.
    final encoder = await _session(_textEncoderName);
    final encInput = _intTensor(
      encoder.inputElementTypes.first,
      inputIds,
      encoder.inputShapes.first,
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
    _releaseSession(_textEncoderName);
    await _checkpoint('text encoder done');

    // 2) UNet session + its latent ("sample") shape.
    await _checkpoint('loading UNet');
    final unet = await _session(_unetName);
    final latentShape = _sampleShape(unet);
    final latent = _randn(_product(latentShape));

    // 3) UNet: single denoising step.
    //    ITERATION-1 TODO: verify the SD-Turbo timestep schedule. SD-Turbo
    //    runs EulerAncestralDiscrete with `timestep_spacing="trailing"` and
    //    1..4 steps; below we use t=999 and a plain DDPM epsilon->x0 step.
    final unetInputs = _unetInputs(unet, latent, 999, textEmb);
    final unetOutputs = unet.run(OrtRunOptions(), unetInputs);
    final noise = _toFloat32(unetOutputs[0]?.value);
    for (final v in unetInputs.values) {
      v.release();
    }
    for (final o in unetOutputs) {
      o?.release();
    }
    _releaseSession(_unetName);
    await _checkpoint('UNet done');

    // 4) Denoise to x0.
    final denoised = _denoise(latent, noise, 999);

    // 5) VAE decoder: latent_sample -> sample.
    //    SD VAE latent scale factor 0.18215.
    await _checkpoint('loading VAE');
    final vae = await _session(_vaeName);
    final vaeInput = _floatTensor(
      vae.inputElementTypes.first,
      _scaleBy(denoised, 1 / 0.18215),
      vae.inputShapes.first,
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
    await _checkpoint('VAE done');

    // 6) VAE output [1,3,512,512] in [-1,1] -> RGB JPEG bytes.
    return _vaeToJpeg(image);
  }

  /// Maps the UNet's three inputs by name, matching each tensor's dtype to the
  /// session's expected input type. The names differ across ONNX exports, so
  /// match heuristically on the lower-cased name.
  Map<String, OrtValue> _unetInputs(
    OrtSession session,
    Float32List latent,
    int timestep,
    Float32List textEmb,
  ) {
    final inputs = <String, OrtValue>{};
    final names = session.inputNames;
    final types = session.inputElementTypes;
    final shapes = session.inputShapes;
    for (var i = 0; i < names.length; i++) {
      final name = names[i];
      final type = types[i];
      final shape = shapes[i];
      final lower = name.toLowerCase();
      if (lower.contains('sample') || lower.contains('latent')) {
        inputs[name] = _floatTensor(type, latent, shape);
      } else if (lower.contains('time')) {
        inputs[name] = (type == _kFloat16 || type == _kFloat32)
            ? _floatTensor(
                type,
                Float32List.fromList([timestep.toDouble()]),
                shape,
              )
            : _intTensor(type, [timestep], shape);
      } else {
        inputs[name] = _floatTensor(type, textEmb, shape);
      }
    }
    return inputs;
  }

  /// Finds the UNet's latent ("sample") input shape.
  List<int> _sampleShape(OrtSession session) {
    for (var i = 0; i < session.inputNames.length; i++) {
      final lower = session.inputNames[i].toLowerCase();
      if (lower.contains('sample') || lower.contains('latent')) {
        return session.inputShapes[i];
      }
    }
    return [1, 4, 64, 64];
  }

  int _product(List<int> shape) => shape.fold(1, (a, b) => a * b);

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

  Uint16List _toHalf(Float32List data) {
    final out = Uint16List(data.length);
    for (var i = 0; i < data.length; i++) {
      out[i] = _floatToHalf(data[i]);
    }
    return out;
  }

  /// Creates a float tensor matching the model's expected [expectedType].
  OrtValueTensor _floatTensor(
    int expectedType,
    Float32List data,
    List<int> shape,
  ) {
    if (expectedType == _kFloat16) {
      return OrtValueTensor.createFloat16Tensor(_toHalf(data), shape);
    }
    return OrtValueTensor.createTensorWithDataList(data, shape);
  }

  /// Creates an integer tensor matching the model's expected [expectedType].
  OrtValueTensor _intTensor(int expectedType, List<int> data, List<int> shape) {
    if (expectedType == _kInt32) {
      return OrtValueTensor.createTensorWithDataList(
        Int32List.fromList(data),
        shape,
      );
    }
    return OrtValueTensor.createTensorWithDataList(data, shape);
  }

  /// Converts a float32 value to its IEEE 754 half-precision bit pattern.
  int _floatToHalf(double value) {
    final bd = ByteData(4)..setFloat32(0, value);
    final bits = bd.getUint32(0);
    final sign = (bits >> 16) & 0x8000;
    final exponent = ((bits >> 23) & 0xFF) - 127 + 15;
    var mantissa = bits & 0x7FFFFF;

    if (exponent <= 0) {
      // subnormal or zero
      if (exponent < -10) {
        return sign;
      }
      mantissa = (mantissa | 0x800000) >> (1 - exponent);
      return sign | (mantissa >> 13);
    } else if (exponent >= 31) {
      // infinity or NaN
      return sign | 0x7C00 | (mantissa != 0 ? 0x200 : 0);
    }
    return sign | (exponent << 10) | ((mantissa + 0x1000) >> 13);
  }

  void dispose() {
    for (final s in _sessions.values) {
      s.release();
    }
    _sessions.clear();
  }
}
