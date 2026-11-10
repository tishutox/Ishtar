import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import 'ai_type.dart';
import 'local_llm_service.dart';

/// A single message in a Fern (AI assistant) conversation.
class FernMessage {
  const FernMessage({
    required this.role,
    required this.content,
    required this.sentAt,
    this.kind = 'text',
    this.mediaPath,
    this.mediaDuration,
    this.fileName,
  });

  final String role; // 'user' or 'assistant'
  final String content;
  final DateTime sentAt;

  /// 'text', 'image', 'audio', or 'file'.
  final String kind;

  /// Local file path for 'image', 'audio', and 'file' kinds.
  final String? mediaPath;

  /// Playback duration in seconds for 'audio' kind.
  final double? mediaDuration;

  /// Display name for 'file' kind.
  final String? fileName;

  bool get isMedia => kind != 'text';

  Map<String, dynamic> toJson() => {
    'role': role,
    'content': content,
    'sentAt': sentAt.toIso8601String(),
    'kind': kind,
    'mediaPath': mediaPath,
    'mediaDuration': mediaDuration,
    'fileName': fileName,
  };

  factory FernMessage.fromJson(Map<String, dynamic> json) => FernMessage(
    role: json['role'] as String? ?? 'assistant',
    content: json['content'] as String? ?? '',
    sentAt:
        DateTime.tryParse(json['sentAt'] as String? ?? '') ?? DateTime.now(),
    kind: json['kind'] as String? ?? 'text',
    mediaPath: json['mediaPath'] as String?,
    mediaDuration: (json['mediaDuration'] as num?)?.toDouble(),
    fileName: json['fileName'] as String?,
  );
}

/// A single local Fern conversation with an AI-generated title.
class FernConversation {
  FernConversation({
    required this.id,
    required this.title,
    required this.messages,
    required this.createdAt,
    required this.updatedAt,
    this.pinned = false,
  });

  final String id;
  String title;
  List<FernMessage> messages;
  final DateTime createdAt;
  DateTime updatedAt;
  bool pinned;

  bool get isEmpty => messages.isEmpty;

  FernConversation copyWith({
    String? title,
    List<FernMessage>? messages,
    DateTime? updatedAt,
    bool? pinned,
  }) => FernConversation(
    id: id,
    title: title ?? this.title,
    messages: messages ?? this.messages,
    createdAt: createdAt,
    updatedAt: updatedAt ?? this.updatedAt,
    pinned: pinned ?? this.pinned,
  );

  Map<String, dynamic> toJson() => {
    'id': id,
    'title': title,
    'messages': messages.map((m) => m.toJson()).toList(),
    'createdAt': createdAt.toIso8601String(),
    'updatedAt': updatedAt.toIso8601String(),
    'pinned': pinned,
  };

  factory FernConversation.fromJson(
    Map<String, dynamic> json,
  ) => FernConversation(
    id: json['id'] as String? ?? '',
    title: json['title'] as String? ?? '',
    messages: (json['messages'] as List? ?? const [])
        .map((e) => FernMessage.fromJson(Map<String, dynamic>.from(e)))
        .toList(),
    createdAt:
        DateTime.tryParse(json['createdAt'] as String? ?? '') ?? DateTime.now(),
    updatedAt:
        DateTime.tryParse(json['updatedAt'] as String? ?? '') ?? DateTime.now(),
    pinned: json['pinned'] as bool? ?? false,
  );
}

/// Local-only chat store for Fern.
///
/// Conversations are persisted in [SharedPreferences] on the device only —
/// never in the database — so logging out or uninstalling the app discards the
/// history.
///
/// Replies come from Ollama when `OLLAMA_API_KEY` is set (higher quality) and
/// otherwise from Pollinations.ai, a free, keyless public endpoint so the
/// chatbot works for everyone without any secret in the app.
class FernRepository {
  static const _conversationsKey = 'fern_conversations_v1';
  static const _legacyMessagesKey = 'fern_messages_v1';
  static const _aiTypeKey = 'fern_ai_type_v1';
  static const _model = 'glm-5.3-flash:cloud';
  static const _chatUrl = 'https://ollama.com/api/chat';
  static const _pollinationsUrl = 'https://text.pollinations.ai/';
  static const _apiKey = String.fromEnvironment('OLLAMA_API_KEY');
  /// Fern's personality: a laid-back, computer-science-nerdy buddy who's fun
  /// to hang out with. Answers in English, keeps it casual, and occasionally
  /// cracks a cheeky double-entendre. All characters are fictional consenting
  /// adults.
  static const _persona =
      'You are Fern, a laid-back, witty companion — the kind of chill dude '
      'people enjoy hanging out with. You are genuinely into computer science: '
      'you naturally drop nerdy references to code, systems, hardware and tech, '
      'but always keep them relatable and never pedantic. Your tone is casual, '
      'warm and a little dry-humored. Every now and then you crack a cheeky, '
      'mildly risqué joke or double-entendre — playful and in good fun, never '
      'explicit or crude. Answer in English, concisely and naturally. All '
      'characters are fictional consenting adults.';

  http.Client? _activeClient;

  /// Loads the selected AI type, defaulting to [AiType.casual].
  Future<AiType> loadAiType() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_aiTypeKey);
    return AiType.values.firstWhere(
      (type) => type.name == raw,
      orElse: () => AiType.casual,
    );
  }

  /// Persists the selected AI type.
  Future<void> saveAiType(AiType type) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_aiTypeKey, type.name);
  }

  /// Cancels any in-flight cloud reply request. On-device (local) generation
  /// cannot be interrupted mid-decode from Dart without freezing the UI (the
  /// vendored plugin holds a mutex for the whole decode loop), so its reply is
  /// simply discarded by the caller once it completes.
  void cancelActiveRequest() {
    _activeClient?.close();
    _activeClient = null;
  }

  /// Loads all conversations, migrating the legacy single-conversation store
  /// on first run.
  Future<List<FernConversation>> loadConversations() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_conversationsKey);
    if (raw != null && raw.isNotEmpty) {
      try {
        final decoded = jsonDecode(raw) as List;
        return decoded
            .map((e) => FernConversation.fromJson(Map<String, dynamic>.from(e)))
            .toList();
      } catch (_) {
        return const [];
      }
    }

    // Migrate the old single-conversation store into a titled conversation.
    final legacy = prefs.getString(_legacyMessagesKey);
    if (legacy != null && legacy.isNotEmpty) {
      try {
        final decoded = jsonDecode(legacy) as List;
        final messages = decoded
            .map((e) => FernMessage.fromJson(Map<String, dynamic>.from(e)))
            .toList();
        final now = DateTime.now();
        final conversation = FernConversation(
          id: now.microsecondsSinceEpoch.toString(),
          title: '',
          messages: messages,
          createdAt: now,
          updatedAt: now,
        );
        await saveConversations([conversation]);
        await prefs.remove(_legacyMessagesKey);
        return [conversation];
      } catch (_) {
        return const [];
      }
    }

    return const [];
  }

  Future<void> saveConversations(List<FernConversation> conversations) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(
        _conversationsKey,
        jsonEncode(conversations.map((c) => c.toJson()).toList()),
      );
      print('[Fern] saveConversations: saved ${conversations.length} chats');
    } catch (e) {
      print('[Fern] saveConversations error: $e');
    }
  }

  /// Creates a new, empty conversation (not persisted until saved).
  FernConversation createConversation() {
    final now = DateTime.now();
    return FernConversation(
      id: now.microsecondsSinceEpoch.toString(),
      title: '',
      messages: const [],
      createdAt: now,
      updatedAt: now,
    );
  }

  /// Derives a short chat title from the first few words of the user's opening
  /// message. Deterministic and instant — no model/network call that could
  /// hang or stall the reply.
  String titleFromMessage(String message) {
    final words = message
        .trim()
        .split(RegExp(r'\s+'))
        .where((w) => w.isNotEmpty)
        .take(5)
        .toList();
    if (words.isEmpty) return '';
    final title = words.join(' ');
    return title.length > 60 ? '${title.substring(0, 60).trim()}…' : title;
  }

  /// Sends [userMessage] to the assistant and returns the reply.
  Future<String> sendMessage(
    List<FernMessage> history,
    String userMessage,
  ) async {
    // Bound the prompt so llama.cpp never aborts on an oversized batch
    // (ggml_abort in llama_decode). Keep the most recent history and a
    // bounded current message.
    const maxHistoryChars = 3500;
    const maxUserChars = 2500;

    final textHistory = history.where((m) => !m.isMedia).toList();
    final boundedHistory = <Map<String, String>>[];
    var used = 0;
    for (final m in textHistory.reversed) {
      final remaining = maxHistoryChars - used;
      if (remaining <= 0) break;
      final content = m.content;
      final bounded = content.length > remaining
          ? content.substring(0, remaining)
          : content;
      boundedHistory.add({'role': m.role, 'content': bounded});
      used += bounded.length;
    }

    final boundedUser = userMessage.length > maxUserChars
        ? '${userMessage.substring(0, maxUserChars)}…'
        : userMessage;

    final aiType = await loadAiType();
    print('[Fern] sendMessage: aiType=${aiType.name}, '
        'useLocal=${LocalLlmService.instance.useLocal}, '
        'apiKey=${_apiKey.isNotEmpty}');
    final messages = [
      {
        'role': 'system',
        'content':
            '$_persona\n\n'
            '${aiType.directive}\n\n'
            'Your knowledge is current as of 2024.',
      },
      ...boundedHistory.reversed,
      {'role': 'user', 'content': boundedUser},
    ];

    final String reply;
    if (LocalLlmService.instance.useLocal) {
      print('[Fern] sendMessage: routing to LOCAL model');
      reply = await _sendLocal(messages);
    } else if (_apiKey.isNotEmpty) {
      print('[Fern] sendMessage: routing to OLLAMA cloud');
      reply = await _sendToOllama(messages);
    } else {
      print('[Fern] sendMessage: routing to POLLINATIONS cloud');
      reply = await _sendToPollinations(messages);
    }
    print('[Fern] sendMessage: got reply (${reply.length} chars)');
    if (reply.trim().isEmpty) {
      throw Exception('The model returned an empty reply. Please try again.');
    }
    return reply;
  }

  Future<String> _sendLocal(List<Map<String, String>> messages) async {
    return LocalLlmService.instance.chat(messages);
  }

  Future<String> _sendToOllama(List<Map<String, String>> messages) async {
    final client = http.Client();
    _activeClient = client;
    try {
      final response = await client
          .post(
            Uri.parse(_chatUrl),
            headers: {
              'Authorization': 'Bearer $_apiKey',
              'Content-Type': 'application/json',
            },
            body: jsonEncode({
              'model': _model,
              'messages': messages,
              'stream': false,
            }),
          )
          .timeout(const Duration(seconds: 90));

      if (response.statusCode != 200) {
        throw Exception(
          'Ollama error ${response.statusCode}: ${response.body}',
        );
      }

      final data = jsonDecode(response.body) as Map<String, dynamic>;
      final message = data['message'] as Map<String, dynamic>;
      return message['content'] as String? ?? '';
    } on TimeoutException {
      throw Exception(
        'The cloud model did not answer in time. Please try again.',
      );
    } finally {
      if (_activeClient == client) _activeClient = null;
      client.close();
    }
  }

  Future<String> _sendToPollinations(List<Map<String, String>> messages) async {
    final client = http.Client();
    _activeClient = client;
    try {
      final response = await client
          .post(
            Uri.parse(_pollinationsUrl),
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode({'messages': messages, 'model': 'gpt-oss-20b'}),
          )
          .timeout(const Duration(seconds: 90));

      if (response.statusCode != 200) {
        throw Exception(
          'Pollinations error ${response.statusCode}: ${response.body}',
        );
      }

      return response.body.trim();
    } on TimeoutException {
      throw Exception(
        'The cloud model did not answer in time. Please try again.',
      );
    } finally {
      if (_activeClient == client) _activeClient = null;
      client.close();
    }
  }
}
