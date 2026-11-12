import 'dart:convert';

/// CLIP/OpenCLIP byte-pair-encoding tokenizer used by the SD-Turbo text
/// encoder. Parses the `tokenizer.json` shipped with the model and produces
/// the fixed-length token sequence expected by the ONNX `text_encoder`.
///
/// The flow mirrors the CLIP tokenizer: NFC + collapse whitespace + lowercase,
/// GPT-2 byte-level encoding, GPT-2 regex split, BPE merge, then wrap with
/// `<|startoftext|>` / `<|endoftext|>` and pad/truncate to 77.
class ClipTokenizer {
  ClipTokenizer._(this._vocab, this._merges, this._sotId, this._eotId);

  final Map<String, int> _vocab;
  final Map<(String, String), int> _merges;
  final int _sotId;
  final int _eotId;

  static const int _maxLength = 77;

  /// Builds the tokenizer from the raw contents of `tokenizer.json`.
  factory ClipTokenizer.fromJson(String json) {
    final data = jsonDecode(json) as Map<String, dynamic>;
    final model = data['model'] as Map<String, dynamic>;

    final vocabRaw = model['vocab'] as Map<String, dynamic>;
    final vocab = vocabRaw.map((k, v) => MapEntry(k, (v as num).toInt()));

    final mergesRaw = model['merges'] as List<dynamic>;
    final merges = <(String, String), int>{};
    for (var i = 0; i < mergesRaw.length; i++) {
      final parts = (mergesRaw[i] as String).split(' ');
      if (parts.length == 2) {
        merges[(parts[0], parts[1])] = i;
      }
    }

    final added = (data['added_tokens'] as List<dynamic>)
        .cast<Map<String, dynamic>>();
    int idOf(String content) =>
        added.firstWhere((e) => e['content'] == content)['id'] as int;

    return ClipTokenizer._(
      vocab,
      merges,
      idOf('<|startoftext|>'),
      idOf('<|endoftext|>'),
    );
  }

  /// Tokenizes [text] into exactly [_maxLength] token ids.
  List<int> tokenize(String text) {
    // Normalizer: NFC (identity for ASCII), collapse whitespace, lowercase.
    var normalized = text.replaceAll(RegExp(r'\s+'), ' ').toLowerCase();

    // GPT-2 byte-level encoding: map each UTF-8 byte to a Unicode char.
    final byteToUnicode = _bytesToUnicode();
    final encoded = utf8
        .encode(normalized)
        .map((b) => byteToUnicode[b]!)
        .join();

    // GPT-2 regex split into word pieces.
    final pattern = RegExp(
      r"'s|'t|'re|'ve|'m|'ll|'d|[\p{L}]+|[\p{N}]|[^\s\p{L}\p{N}]+",
      unicode: true,
    );
    final pieces = pattern
        .allMatches(encoded)
        .map((m) => m.group(0)!)
        .toList();

    final ids = <int>[];
    for (final piece in pieces) {
      ids.addAll(_bpe(piece));
    }

    // Post-processor (RobertaProcessing): wrap with SOT/EOT.
    final result = <int>[_sotId, ...ids, _eotId];
    if (result.length > _maxLength) {
      return result.sublist(0, _maxLength);
    }
    return [
      ...result,
      ...List<int>.filled(_maxLength - result.length, _eotId),
    ];
  }

  /// BPE-encodes a single already-split word piece into token ids.
  List<int> _bpe(String piece) {
    final word = piece.split('').toList();
    while (word.length > 1) {
      int? bestRank;
      var bestIndex = -1;
      for (var i = 0; i < word.length - 1; i++) {
        final rank = _merges[(word[i], word[i + 1])];
        if (rank != null && (bestRank == null || rank < bestRank)) {
          bestRank = rank;
          bestIndex = i;
        }
      }
      if (bestIndex == -1) break;
      word[bestIndex] = word[bestIndex] + word[bestIndex + 1];
      word.removeAt(bestIndex + 1);
    }
    return word.map((w) => _vocab[w] ?? _eotId).toList();
  }

  /// The GPT-2 `bytes_to_unicode()` mapping: printable bytes map to themselves,
  /// the rest map to U+0100 and up in byte order.
  Map<int, String> _bytesToUnicode() {
    final bs = <int>[
      for (var b = 33; b <= 126; b++) b, // ! .. ~
      for (var b = 161; b <= 172; b++) b, // ¡ .. ¬
      for (var b = 174; b <= 255; b++) b, // ® .. ÿ
    ];
    final cs = List<int>.from(bs);
    var n = 0;
    for (var b = 0; b < 256; b++) {
      if (!bs.contains(b)) {
        bs.add(b);
        cs.add(256 + n);
        n++;
      }
    }
    return {
      for (var i = 0; i < 256; i++) bs[i]: String.fromCharCode(cs[i]),
    };
  }
}
