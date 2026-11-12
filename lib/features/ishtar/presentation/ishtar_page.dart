import 'dart:async';

import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:file_picker/file_picker.dart';
import 'package:image_picker/image_picker.dart';
import 'package:lumii_quest/core/icons/app_icons.dart';
import 'package:lumii_quest/features/ishtar/data/ai_type.dart';
import 'package:lumii_quest/features/ishtar/data/gen_type.dart';
import 'package:lumii_quest/features/ishtar/data/image_tag.dart';
import 'package:lumii_quest/features/ishtar/data/ishtar_repository.dart';
import 'package:lumii_quest/features/ishtar/data/local_image_service.dart';
import 'package:lumii_quest/features/ishtar/data/local_llm_service.dart';
import 'package:lumii_quest/features/ishtar/data/media_file_io.dart';
import 'package:lumii_quest/features/ishtar/presentation/code_highlight.dart';
import 'package:path_provider/path_provider.dart';
import 'package:speech_to_text/speech_to_text.dart';

const Color ishtarGreen = Color(0xFF34C759);
const Color ishtarCloud = Color(0xFFFFA000);

/// Local-only chat with Ishtar, the built-in AI assistant.
///
/// Messages are stored on-device (not in the database) and replies come from
/// the Ollama cloud API.
class IshtarPage extends StatefulWidget {
  const IshtarPage({
    super.key,
    required this.conversation,
    required this.onChanged,
    required this.onToggleSidebar,
  });

  final IshtarConversation conversation;
  final ValueChanged<IshtarConversation> onChanged;
  final VoidCallback onToggleSidebar;

  @override
  State<IshtarPage> createState() => _IshtarPageState();
}

class _IshtarPageState extends State<IshtarPage> {
  final _repository = IshtarRepository();
  final _controller = TextEditingController();
  final _scrollController = ScrollController();
  final _speech = SpeechToText();
  late List<IshtarMessage> _messages;
  bool _sending = false;
  bool _generating = false;
  bool _abortRequested = false;
  int _generationId = 0;
  bool _downloadingModel = false;
  bool _modelDownloaded = false;
  bool _isListening = false;
  bool _showAttachMenu = false;
  final _inputAreaKey = GlobalKey();
  double _inputAreaHeight = 0;
  AiType _aiType = AiType.casual;
  GenType _genType = GenType.text;
  ImageTag _imageTag = ImageTag.anime;

  bool get _supportsMedia =>
      !kIsWeb &&
      (defaultTargetPlatform == TargetPlatform.android ||
          defaultTargetPlatform == TargetPlatform.windows);

  @override
  void initState() {
    super.initState();
    _messages = List.of(widget.conversation.messages);
    _controller.addListener(_handleTextChanged);
    unawaited(_checkCrashLog());
    unawaited(_loadAiType());
    unawaited(_loadGenType());
    unawaited(_loadImageTag());
    unawaited(_loadModelDownloaded());
    // When a chat is opened (or switched to), start at the latest message
    // instead of the top of the history.
    _scrollToBottom(force: true);
  }

  @override
  void dispose() {
    _controller.removeListener(_handleTextChanged);
    _controller.dispose();
    _scrollController.dispose();
    if (_speech.isAvailable) unawaited(_speech.cancel());
    super.dispose();
  }

  void _scrollToBottom({bool force = false}) {
    // Decide synchronously, before the new message changes the scroll extent,
    // so a tall image or long reply doesn't read as "the user scrolled up".
    final nearBottom = !_scrollController.hasClients ||
        _scrollController.position.maxScrollExtent -
                _scrollController.position.pixels <=
            240;
    if (!force && !nearBottom) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_scrollController.hasClients) return;
      _scrollController.jumpTo(_scrollController.position.maxScrollExtent);
    });
  }

  void _measureInputArea() {
    final box = _inputAreaKey.currentContext?.findRenderObject() as RenderBox?;
    if (box == null || !box.hasSize) return;
    if (box.size.height != _inputAreaHeight) {
      setState(() => _inputAreaHeight = box.size.height);
    }
  }

  void _handleTextChanged() {
    if (!mounted) return;
    if (_controller.text.trim().isNotEmpty && _showAttachMenu) {
      setState(() => _showAttachMenu = false);
    } else {
      setState(() {});
    }
  }

  void _persist({String? title}) {
    try {
      widget.onChanged(
        widget.conversation.copyWith(
          title: title,
          messages: List.of(_messages),
          updatedAt: DateTime.now(),
        ),
      );
    } catch (e) {
      // Persistence must never break the send flow (which would leave the
      // input stuck in a loading state with no reply and no error).
      print('[Ishtar] _persist error: $e');
    }
  }

  Future<void> _checkCrashLog() async {
    final log = await LocalLlmService.instance.readCrashLog();
    if (!mounted || log == null || log.trim().isEmpty) return;
    await showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Native crash log'),
        content: SizedBox(
          width: double.maxFinite,
          child: SingleChildScrollView(
            child: SelectableText(log, style: const TextStyle(fontSize: 12)),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () {
              Clipboard.setData(ClipboardData(text: log));
              Navigator.of(context).pop();
            },
            child: const Text('Copy'),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Close'),
          ),
        ],
      ),
    );
  }

  Future<void> _loadAiType() async {
    final type = await _repository.loadAiType();
    if (mounted) setState(() => _aiType = type);
  }

  Future<void> _loadGenType() async {
    final type = await _repository.loadGenType();
    if (mounted) setState(() => _genType = type);
  }

  Future<void> _loadImageTag() async {
    final tag = await _repository.loadImageTag();
    if (mounted) setState(() => _imageTag = tag);
  }

  Future<void> _loadModelDownloaded() async {
    final downloaded = await LocalLlmService.instance.isDownloaded();
    if (mounted) setState(() => _modelDownloaded = downloaded);
  }

  Future<void> _openAiSettings() async {
    final result = await showModalBottomSheet<_AiSettingsResult>(
      context: context,
      backgroundColor: Colors.white,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (context) => _AiSettingsSheet(
        initialGenType: _genType,
        initialAiType: _aiType,
        initialImageTag: _imageTag,
      ),
    );
    if (result == null || !mounted) return;
    setState(() {
      _genType = result.genType;
      _aiType = result.aiType;
      _imageTag = result.imageTag;
    });
    await _repository.saveGenType(result.genType);
    await _repository.saveAiType(result.aiType);
    await _repository.saveImageTag(result.imageTag);
  }

  Future<void> _toggleLocalModel() async {
    final service = LocalLlmService.instance;
    if (service.useLocal) {
      // Switch back to the (SFW) cloud model.
      setState(() => service.useLocal = false);
      return;
    }
    if (_downloadingModel) return;
    setState(() => _downloadingModel = true);
    try {
      final ok = await service.ensureLoaded();
      if (mounted) {
        if (ok) {
          setState(() {
            service.useLocal = true;
            _modelDownloaded = true;
          });
        } else {
          _showSnack('Could not load the local model.');
        }
      }
    } catch (error) {
      if (mounted) {
        _showSnack('Model download failed: $error');
      }
    } finally {
      if (mounted) setState(() => _downloadingModel = false);
    }
  }

  void _showSnack(String message) {
    if (mounted) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(message)));
    }
  }

  Future<void> _send() async {
    final text = _controller.text.trim();
    if (text.isEmpty || _sending) return;
    final shouldTitle = _messages.isEmpty && widget.conversation.title.isEmpty;
    _controller.clear();

    final generationId = ++_generationId;

    final history = List<IshtarMessage>.of(_messages);
    setState(() {
      _messages = [
        ..._messages,
        IshtarMessage(role: 'user', content: text, sentAt: DateTime.now()),
      ];
      _sending = true;
      _generating = true;
    });
    _abortRequested = false;
    // Persist the user message immediately so the chat is saved even if the
    // reply is slow or fails.
    _persist();
    _scrollToBottom(force: true);

    if (_genType == GenType.image) {
      await _generateImageReply(text, generationId, shouldTitle);
      return;
    }

    String? reply;
    Object? error;
    try {
      print('[Ishtar] _send: calling sendMessage (useLocal='
          '${LocalLlmService.instance.useLocal})');
      reply = await _repository
          .sendMessage(history, text)
          .timeout(const Duration(seconds: 360));
      print('[Ishtar] _send: got reply (${reply.length} chars)');
    } catch (e) {
      print('[Ishtar] _send: error: $e');
      error = e;
    }

    if (!mounted || generationId != _generationId) return;
    // The reply has arrived (or the request failed): spin the stop icon back.
    setState(() => _generating = false);

    if (_abortRequested) {
      // Cancelled by the user: keep their message, drop the reply.
      _persist();
      setState(() => _sending = false);
      _scrollToBottom();
      return;
    }

    if (error != null) {
      setState(() {
        _messages = [
          ..._messages,
          IshtarMessage(
            role: 'assistant',
            content: 'Sorry, something went wrong: $error',
            sentAt: DateTime.now(),
          ),
        ];
      });
      _persist();
      setState(() => _sending = false);
      _scrollToBottom();
      return;
    }

    setState(() {
      _messages = [
        ..._messages,
        IshtarMessage(role: 'assistant', content: reply!, sentAt: DateTime.now()),
      ];
    });
    _scrollToBottom();

    // Persist the reply immediately, deriving a deterministic title from the
    // first few words of the user's message — no second LLM/network call that
    // could hang and leave the chat unsaved.
    final derivedTitle = shouldTitle
        ? _repository.titleFromMessage(text)
        : '';
    _persist(title: derivedTitle.isEmpty ? null : derivedTitle);
    setState(() => _sending = false);
  }

  Future<void> _generateImageReply(
    String prompt,
    int generationId,
    bool shouldTitle,
  ) async {
    String? imagePath;
    Object? error;
    try {
      final useLocal = LocalLlmService.instance.useLocal;
      final bytes = useLocal
          ? await LocalImageService.instance
              .generateImage(prompt)
              .timeout(const Duration(minutes: 30))
          : await _repository
              .generateImage(prompt)
              .timeout(const Duration(seconds: 150));
      if (!mounted || generationId != _generationId) return;
      final dir = await _mediaDir();
      imagePath =
          '$dir/ishtar_img_${DateTime.now().microsecondsSinceEpoch}.jpg';
      await writeMediaFile(imagePath, bytes);
    } catch (e) {
      error = e;
    }

    if (!mounted || generationId != _generationId) return;
    setState(() => _generating = false);

    if (_abortRequested) {
      _persist();
      setState(() => _sending = false);
      _scrollToBottom();
      return;
    }

    if (error != null) {
      setState(() {
        _messages = [
          ..._messages,
          IshtarMessage(
            role: 'assistant',
            content: 'Sorry, something went wrong: $error',
            sentAt: DateTime.now(),
          ),
        ];
      });
      _persist();
      setState(() => _sending = false);
      _scrollToBottom();
      return;
    }

    setState(() {
      _messages = [
        ..._messages,
        IshtarMessage(
          role: 'assistant',
          content: '',
          sentAt: DateTime.now(),
          kind: 'image',
          mediaPath: imagePath,
        ),
      ];
    });
    _scrollToBottom();

    final derivedTitle = shouldTitle ? _repository.titleFromMessage(prompt) : '';
    _persist(title: derivedTitle.isEmpty ? null : derivedTitle);
    setState(() => _sending = false);
  }

  void _cancelGeneration() {
    if (!_generating) return;
    _abortRequested = true;
    _repository.cancelActiveRequest();
    // Invalidate the in-flight generation so its reply is discarded, and
    // unlock the input (mic/attach) immediately. The on-device model cannot
    // be interrupted mid-decode, but the stale reply is dropped once it ends.
    _generationId++;
    setState(() {
      _generating = false;
      _sending = false;
    });
  }

  Future<String> _mediaDir() async {
    final docs = await getApplicationDocumentsDirectory();
    return '${docs.path}/ishtar_media';
  }

  Future<void> _sendImages() async {
    if (_sending || _isListening) return;
    final images = await ImagePicker().pickMultiImage(
      maxWidth: 1600,
      imageQuality: 85,
    );
    if (images.isEmpty || !mounted) return;
    await _sendPickedImages(images);
  }

  Future<void> _takePhoto() async {
    if (_sending || _isListening) return;
    final image = await ImagePicker().pickImage(
      source: ImageSource.camera,
      maxWidth: 1600,
      imageQuality: 85,
    );
    if (image == null || !mounted) return;
    await _sendPickedImages([image]);
  }

  Future<void> _sendPickedImages(List<XFile> images) async {
    setState(() {
      _sending = true;
      _showAttachMenu = false;
    });
    try {
      final dir = await _mediaDir();
      final messages = <IshtarMessage>[];
      for (final image in images) {
        final extension = _imageExtension(image.name);
        final dest =
            '$dir/ishtar_${DateTime.now().microsecondsSinceEpoch}.$extension';
        final bytes = await image.readAsBytes();
        await writeMediaFile(dest, bytes);
        messages.add(
          IshtarMessage(
            role: 'user',
            content: '',
            sentAt: DateTime.now(),
            kind: 'image',
            mediaPath: dest,
          ),
        );
      }
      setState(() => _messages = [..._messages, ...messages]);
      _persist();
      _scrollToBottom();
      await _acknowledgeMedia('image');
    } catch (error) {
      _showSnack('Image could not be sent: $error');
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  Future<void> _pickFile() async {
    if (_sending || _isListening) return;
    final file = await FilePicker.pickFile(
      type: FileType.custom,
      allowedExtensions: ['pdf'],
    );
    if (file == null || !mounted) return;
    final path = file.path;
    if (path == null) {
      _showSnack('Could not read the selected file.');
      return;
    }
    setState(() {
      _sending = true;
      _showAttachMenu = false;
    });
    try {
      final dir = await _mediaDir();
      final name = file.name.isNotEmpty ? file.name : 'document.pdf';
      final dest = '$dir/ishtar_${DateTime.now().microsecondsSinceEpoch}_$name';
      final bytes = await readMediaFile(path);
      await writeMediaFile(dest, bytes);
      setState(() {
        _messages = [
          ..._messages,
          IshtarMessage(
            role: 'user',
            content: '',
            sentAt: DateTime.now(),
            kind: 'file',
            mediaPath: dest,
            fileName: name,
          ),
        ];
      });
      _persist();
      _scrollToBottom();
      await _acknowledgeMedia('file');
    } catch (error) {
      _showSnack('File could not be sent: $error');
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  void _toggleAttachMenu() {
    setState(() => _showAttachMenu = !_showAttachMenu);
  }

  Future<void> _toggleDictation() async {
    if (_isListening) {
      await _stopDictation();
    } else {
      await _startDictation();
    }
  }

  Future<void> _startDictation() async {
    if (_sending) return;
    if (!_speech.isAvailable) {
      final available = await _speech.initialize();
      if (!available) {
        _showSnack('Speech recognition is not available on this device.');
        return;
      }
    }
    if (mounted) {
      setState(() {
        _isListening = true;
        _showAttachMenu = false;
      });
    }
    try {
      await _speech.listen(
        onResult: (result) {
          if (!result.finalResult) return;
          _insertRecognizedText(result.recognizedWords);
          if (mounted) setState(() => _isListening = false);
        },
        listenOptions: SpeechListenOptions(
          partialResults: false,
          listenMode: ListenMode.dictation,
        ),
      );
    } catch (error) {
      if (mounted) {
        setState(() => _isListening = false);
        _showSnack('Speech recognition failed: $error');
      }
    }
  }

  Future<void> _stopDictation() async {
    await _speech.stop();
    if (mounted) setState(() => _isListening = false);
  }

  void _insertRecognizedText(String text) {
    final words = text.trim();
    if (words.isEmpty) return;
    final value = _controller.value;
    final selection = value.selection;
    final start = selection.isValid ? selection.start : value.text.length;
    final end = selection.isValid ? selection.end : value.text.length;
    _controller.value = TextEditingValue(
      text: value.text.replaceRange(start, end, words),
      selection: TextSelection.collapsed(offset: start + words.length),
    );
  }

  Future<void> _acknowledgeMedia(String kind) async {
    final reply = switch (kind) {
      'file' =>
        "I can only read text, so I can't open files. Tell me what it says.",
      _ => "I can only read text, so I can't see images. Tell me what it says.",
    };
    setState(() {
      _messages = [
        ..._messages,
        IshtarMessage(role: 'assistant', content: reply, sentAt: DateTime.now()),
      ];
    });
    _persist();
    _scrollToBottom();
  }

  @override
  Widget build(BuildContext context) {
    WidgetsBinding.instance.addPostFrameCallback((_) => _measureInputArea());
    final useLocal = LocalLlmService.instance.useLocal;
    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          tooltip: 'Menu',
          onPressed: widget.onToggleSidebar,
          icon: const AppIcon(AppIcons.equal),
        ),
        actions: [
          IconButton(
            tooltip: useLocal ? 'Switch to cloud model' : 'Use on-device model',
            onPressed: _toggleLocalModel,
            style: useLocal
                ? IconButton.styleFrom(
                    backgroundColor: ishtarGreen.withValues(alpha: 0.18),
                  )
                : _modelDownloaded
                ? IconButton.styleFrom(
                    backgroundColor: ishtarCloud.withValues(alpha: 0.18),
                  )
                : null,
            icon: _downloadingModel
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: ishtarGreen,
                    ),
                  )
                : AppIcon(
                    useLocal
                        ? AppIcons.sprout
                        : (_modelDownloaded
                              ? AppIcons.cloud
                              : AppIcons.arrowBigDownDash),
                    color: useLocal
                        ? ishtarGreen
                        : (_modelDownloaded ? ishtarCloud : Colors.black),
                  ),
          ),
          IconButton(
            tooltip: 'AI settings',
            onPressed: _openAiSettings,
            icon: const AppIcon(AppIcons.toolCase),
          ),
        ],
        surfaceTintColor: Colors.transparent,
      ),
      body: Stack(
        clipBehavior: Clip.none,
        children: [
          Column(
            children: [
              Expanded(
                child: _messages.isEmpty
                    ? _buildEmptyState()
                    : ListView.builder(
                        controller: _scrollController,
                        padding: const EdgeInsets.all(16),
                        itemCount: _messages.length,
                        itemBuilder: (context, index) {
                          return _IshtarBubble(
                            message: _messages[index],
                            isMine: _messages[index].role == 'user',
                          );
                        },
                      ),
              ),
              KeyedSubtree(
                key: _inputAreaKey,
                child: SafeArea(top: false, child: _buildInputBar()),
              ),
            ],
          ),
          if (_showAttachMenu)
            Positioned(
              right: 16,
              bottom: _inputAreaHeight + 8,
              child: _AttachMenu(
                onCamera: _takePhoto,
                onFile: _pickFile,
                onGallery: _sendImages,
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildInputBar() {
    if (_supportsMedia) {
      if (_isListening) {
        return _ListeningInputBar(onStop: _stopDictation);
      }
      return _IshtarMediaInputBar(
        controller: _controller,
        isSending: _sending,
        isGenerating: _generating,
        showAttachMenu: _showAttachMenu,
        onSend: _send,
        onCancel: _cancelGeneration,
        onToggleAttachMenu: _toggleAttachMenu,
        onToggleDictation: _toggleDictation,
      );
    }
    return _IshtarTextInputBar(
      controller: _controller,
      isSending: _sending,
      onSend: _send,
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const AppIcon(AppIcons.bot, size: 42, color: Colors.black),
            const SizedBox(height: 12),
            Text(
              'Say hoi to Ishtar :3',
              style: Theme.of(
                context,
              ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800),
            ),
          ],
        ),
      ),
    );
  }
}

class _IshtarMediaInputBar extends StatelessWidget {
  const _IshtarMediaInputBar({
    required this.controller,
    required this.isSending,
    required this.isGenerating,
    required this.showAttachMenu,
    required this.onSend,
    required this.onCancel,
    required this.onToggleAttachMenu,
    required this.onToggleDictation,
  });

  final TextEditingController controller;
  final bool isSending;
  final bool isGenerating;
  final bool showAttachMenu;
  final Future<void> Function() onSend;
  final VoidCallback onCancel;
  final VoidCallback onToggleAttachMenu;
  final Future<void> Function() onToggleDictation;

  @override
  Widget build(BuildContext context) {
    final primary = Theme.of(context).colorScheme.primary;
    final surface = Theme.of(context).colorScheme.surfaceContainerHighest;
    final hasText = controller.text.trim().isNotEmpty;

    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        decoration: BoxDecoration(
          color: surface,
          borderRadius: BorderRadius.circular(50),
        ),
        child: Row(
          children: [
            Expanded(
              child: TextField(
                controller: controller,
                minLines: 1,
                maxLines: 4,
                keyboardType: TextInputType.multiline,
                textInputAction: TextInputAction.newline,
                decoration: const InputDecoration(
                  hintText: 'Message Ishtar',
                  border: InputBorder.none,
                  enabledBorder: InputBorder.none,
                  focusedBorder: InputBorder.none,
                  filled: false,
                  contentPadding: EdgeInsets.symmetric(
                    horizontal: 14,
                    vertical: 10,
                  ),
                ),
              ),
            ),
            if (isGenerating)
              AnimatedRotation(
                turns: 0.125,
                duration: const Duration(milliseconds: 200),
                child: _CircleIconButton(
                  tooltip: 'Stop',
                  icon: AppIcons.circlePlus,
                  backgroundColor: primary,
                  iconColor: Colors.white,
                  onPressed: onCancel,
                ),
              )
            else if (hasText)
              _CircleIconButton(
                tooltip: 'Send',
                icon: isSending
                    ? AppIcons.loaderCircle
                    : AppIcons.sendHorizontal,
                backgroundColor: primary,
                iconColor: Colors.white,
                onPressed: isSending ? null : onSend,
              )
            else ...[
              IconButton(
                tooltip: 'Dictate message',
                onPressed: isSending ? null : onToggleDictation,
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(minWidth: 44, minHeight: 44),
                icon: AppIcon(AppIcons.mic, color: primary),
              ),
              AnimatedRotation(
                turns: showAttachMenu ? 0.125 : 0,
                duration: const Duration(milliseconds: 200),
                child: _CircleIconButton(
                  tooltip: 'Attach',
                  icon: AppIcons.circlePlus,
                  backgroundColor: primary,
                  iconColor: Colors.white,
                  onPressed: isSending ? null : onToggleAttachMenu,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _IshtarTextInputBar extends StatelessWidget {
  const _IshtarTextInputBar({
    required this.controller,
    required this.isSending,
    required this.onSend,
  });

  final TextEditingController controller;
  final bool isSending;
  final Future<void> Function() onSend;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
      child: Row(
        children: [
          Expanded(
            child: TextField(
              controller: controller,
              minLines: 1,
              maxLines: 4,
              enabled: !isSending,
              keyboardType: TextInputType.multiline,
              textInputAction: TextInputAction.newline,
              decoration: InputDecoration(
                hintText: 'Message Ishtar',
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(18),
                ),
              ),
            ),
          ),
          const SizedBox(width: 8),
          FilledButton(
            onPressed: isSending ? null : onSend,
            child: AppIcon(
              isSending ? AppIcons.loaderCircle : AppIcons.sendHorizontal,
            ),
          ),
        ],
      ),
    );
  }
}

class _AttachMenu extends StatelessWidget {
  const _AttachMenu({
    required this.onCamera,
    required this.onFile,
    required this.onGallery,
  });

  final VoidCallback onCamera;
  final VoidCallback onFile;
  final VoidCallback onGallery;

  @override
  Widget build(BuildContext context) {
    final primary = Theme.of(context).colorScheme.primary;
    final surface = Theme.of(context).colorScheme.surfaceContainerHighest;
    return Material(
      color: surface,
      elevation: 4,
      shadowColor: Colors.black54,
      borderRadius: BorderRadius.circular(16),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            _AttachOption(
              icon: AppIcons.camera,
              label: 'Camera',
              color: primary,
              onTap: onCamera,
            ),
            const SizedBox(width: 4),
            _AttachOption(
              icon: AppIcons.file,
              label: 'File',
              color: primary,
              onTap: onFile,
            ),
            const SizedBox(width: 4),
            _AttachOption(
              icon: AppIcons.image,
              label: 'Gallery',
              color: primary,
              onTap: onGallery,
            ),
          ],
        ),
      ),
    );
  }
}

class _AttachOption extends StatelessWidget {
  const _AttachOption({
    required this.icon,
    required this.label,
    required this.color,
    required this.onTap,
  });

  final String icon;
  final String label;
  final Color color;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: label,
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 10),
          child: AppIcon(icon, color: color),
        ),
      ),
    );
  }
}

class _ListeningInputBar extends StatelessWidget {
  const _ListeningInputBar({required this.onStop});

  final VoidCallback onStop;

  @override
  Widget build(BuildContext context) {
    final primary = Theme.of(context).colorScheme.primary;
    final surface = Theme.of(context).colorScheme.surfaceContainerHighest;

    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        decoration: BoxDecoration(
          color: surface,
          borderRadius: BorderRadius.circular(50),
        ),
        child: Row(
          children: [
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                'Listening...',
                style: Theme.of(
                  context,
                ).textTheme.bodyMedium?.copyWith(color: primary),
              ),
            ),
            _CircleIconButton(
              tooltip: 'Stop dictation',
              icon: AppIcons.micOff,
              backgroundColor: primary,
              iconColor: Colors.white,
              onPressed: onStop,
            ),
          ],
        ),
      ),
    );
  }
}

class _CircleIconButton extends StatelessWidget {
  const _CircleIconButton({
    required this.tooltip,
    required this.icon,
    required this.backgroundColor,
    required this.iconColor,
    this.onPressed,
  });

  final String tooltip;
  final String icon;
  final Color backgroundColor;
  final Color iconColor;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: backgroundColor,
      shape: const CircleBorder(),
      child: SizedBox(
        width: 48,
        height: 48,
        child: IconButton(
          tooltip: tooltip,
          onPressed: onPressed,
          padding: EdgeInsets.zero,
          constraints: const BoxConstraints(),
          icon: AppIcon(icon, color: iconColor, size: 24),
        ),
      ),
    );
  }
}

class _IshtarBubble extends StatelessWidget {
  const _IshtarBubble({required this.message, required this.isMine});

  final IshtarMessage message;
  final bool isMine;

  @override
  Widget build(BuildContext context) {
    switch (message.kind) {
      case 'image':
        return Align(
          alignment: isMine ? Alignment.centerRight : Alignment.centerLeft,
          child: _IshtarImageBubble(path: message.mediaPath ?? ''),
        );
      case 'audio':
        return Align(
          alignment: isMine ? Alignment.centerRight : Alignment.centerLeft,
          child: _IshtarAudioBubble(
            path: message.mediaPath ?? '',
            duration: message.mediaDuration ?? 0,
            isMine: isMine,
          ),
        );
      case 'file':
        return Align(
          alignment: isMine ? Alignment.centerRight : Alignment.centerLeft,
          child: _IshtarFileBubble(
            fileName: message.fileName ?? 'File',
            isMine: isMine,
          ),
        );
      default:
        if (!isMine) {
          return Container(
            width: double.infinity,
            margin: const EdgeInsets.only(bottom: 10),
            child: _AssistantMessageView(content: message.content),
          );
        }
        return Align(
          alignment: Alignment.centerRight,
          child: Container(
            margin: const EdgeInsets.only(bottom: 10),
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            constraints: const BoxConstraints(maxWidth: 300),
            decoration: BoxDecoration(
              color: Colors.black,
              borderRadius: BorderRadius.circular(16),
            ),
            child: Text(
              message.content,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 15,
                height: 1.35,
              ),
            ),
          ),
        );
    }
  }
}

class _IshtarFileBubble extends StatelessWidget {
  const _IshtarFileBubble({required this.fileName, required this.isMine});

  final String fileName;
  final bool isMine;

  @override
  Widget build(BuildContext context) {
    final textColor = isMine ? Colors.white : const Color(0xFF1A1A1A);
    final bubbleColor = isMine ? Colors.black : const Color(0xFFF2F2F2);
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      constraints: const BoxConstraints(maxWidth: 300),
      decoration: BoxDecoration(
        color: bubbleColor,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          AppIcon(AppIcons.file, color: textColor, size: 20),
          const SizedBox(width: 8),
          Flexible(
            child: Text(
              fileName,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(color: textColor, fontSize: 14),
            ),
          ),
        ],
      ),
    );
  }
}

/// Decoded image bytes cached by path, so scrolling a bubble back into view
/// renders instantly instead of flickering through the loading placeholder.
final Map<String, Uint8List> _imageBytesCache = {};

class _IshtarImageBubble extends StatefulWidget {
  const _IshtarImageBubble({required this.path});

  final String path;

  @override
  State<_IshtarImageBubble> createState() => _IshtarImageBubbleState();
}

class _IshtarImageBubbleState extends State<_IshtarImageBubble> {
  Uint8List? _bytes;
  bool _failed = false;

  @override
  void initState() {
    super.initState();
    _bytes = _imageBytesCache[widget.path];
    if (_bytes == null) {
      unawaited(_load());
    }
  }

  Future<void> _load() async {
    try {
      final bytes = await readMediaFile(widget.path);
      _imageBytesCache[widget.path] = bytes;
      if (mounted) setState(() => _bytes = bytes);
    } catch (_) {
      if (mounted) setState(() => _failed = true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final bytes = _bytes;
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(16),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 260),
          child: _failed
              ? const SizedBox(
                  width: 180,
                  height: 140,
                  child: Center(child: AppIcon(AppIcons.imageOff)),
                )
              : bytes == null
              ? const SizedBox(
                  width: 260,
                  height: 260,
                  child: Center(child: CircularProgressIndicator()),
                )
              : Image.memory(
                  bytes,
                  fit: BoxFit.cover,
                  filterQuality: FilterQuality.medium,
                ),
        ),
      ),
    );
  }
}

class _IshtarAudioBubble extends StatefulWidget {
  const _IshtarAudioBubble({
    required this.path,
    required this.duration,
    required this.isMine,
  });

  final String path;
  final double duration;
  final bool isMine;

  @override
  State<_IshtarAudioBubble> createState() => _IshtarAudioBubbleState();
}

class _IshtarAudioBubbleState extends State<_IshtarAudioBubble> {
  final _player = AudioPlayer();
  bool _isPlaying = false;
  StreamSubscription<void>? _completeSub;

  @override
  void initState() {
    super.initState();
    _completeSub = _player.onPlayerComplete.listen((_) {
      if (mounted) {
        setState(() => _isPlaying = false);
      }
    });
  }

  @override
  void dispose() {
    _completeSub?.cancel();
    unawaited(_player.dispose());
    super.dispose();
  }

  Future<void> _toggle() async {
    if (_isPlaying) {
      await _player.stop();
      if (mounted) {
        setState(() => _isPlaying = false);
      }
      return;
    }
    await _player.play(DeviceFileSource(widget.path));
    if (mounted) {
      setState(() => _isPlaying = true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final isMine = widget.isMine;
    final textColor = isMine ? Colors.white : const Color(0xFF1A1A1A);
    final bubbleColor = isMine ? Colors.black : const Color(0xFFF2F2F2);

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: bubbleColor,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          IconButton(
            tooltip: _isPlaying ? 'Pause' : 'Play',
            onPressed: _toggle,
            icon: AppIcon(
              _isPlaying ? AppIcons.pause : AppIcons.play,
              color: textColor,
            ),
          ),
          const SizedBox(width: 4),
          Text(
            _formatDuration(widget.duration),
            style: TextStyle(color: textColor),
          ),
        ],
      ),
    );
  }
}

String _formatDuration(double seconds) {
  final total = seconds.round();
  final minutes = total ~/ 60;
  final secs = total % 60;
  return minutes > 0
      ? '$minutes:${secs.toString().padLeft(2, '0')}'
      : '0:${secs.toString().padLeft(2, '0')}';
}

String _imageExtension(String fileName) {
  final extension = fileName.split('.').last.toLowerCase();
  return switch (extension) {
    'jpg' || 'jpeg' => 'jpg',
    'png' => 'png',
    'webp' => 'webp',
    'gif' => 'gif',
    _ => 'jpg',
  };
}

class _AiSettingsResult {
  const _AiSettingsResult({
    required this.genType,
    required this.aiType,
    required this.imageTag,
  });

  final GenType genType;
  final AiType aiType;
  final ImageTag imageTag;
}

class _AiSettingsSheet extends StatefulWidget {
  const _AiSettingsSheet({
    required this.initialGenType,
    required this.initialAiType,
    required this.initialImageTag,
  });

  final GenType initialGenType;
  final AiType initialAiType;
  final ImageTag initialImageTag;

  @override
  State<_AiSettingsSheet> createState() => _AiSettingsSheetState();
}

class _AiSettingsSheetState extends State<_AiSettingsSheet> {
  late GenType _genType = widget.initialGenType;
  late AiType _aiType = widget.initialAiType;
  late ImageTag _imageTag = widget.initialImageTag;

  @override
  Widget build(BuildContext context) {
    final isImage = _genType == GenType.image;

    final tagChips = isImage
        ? <Widget>[
            for (final tag in ImageTag.values.toList()
              ..sort(
                (a, b) => a.label
                    .toLowerCase()
                    .compareTo(b.label.toLowerCase()),
              ))
              _ChipTag(
                icon: tag.icon,
                label: tag.label,
                selected: tag == _imageTag,
                onTap: () => setState(() => _imageTag = tag),
              ),
          ]
        : <Widget>[
            for (final type in AiType.values.toList()
              ..sort(
                (a, b) => a.label
                    .toLowerCase()
                    .compareTo(b.label.toLowerCase()),
              ))
              _ChipTag(
                icon: type.icon,
                label: type.label,
                selected: type == _aiType,
                onTap: () => setState(() => _aiType = type),
              ),
          ];

    final description = isImage ? _imageTag.description : _aiType.description;

    return SafeArea(
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.sizeOf(context).height * 0.8,
        ),
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'AI settings',
                style: Theme.of(
                  context,
                ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800),
              ),
              const SizedBox(height: 2),
              const Text(
                'Choose how Ishtar responds.',
                style: TextStyle(color: Color(0xFF8E8E93)),
              ),
              const SizedBox(height: 16),
              const Text(
                'Types',
                style: TextStyle(
                  color: Color(0xFF8E8E93),
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 12),
              Wrap(
                spacing: 10,
                runSpacing: 10,
                children: [
                  _ChipTag(
                    icon: AppIcons.messageSquareText,
                    label: 'Text',
                    selected: !isImage,
                    onTap: () => setState(() => _genType = GenType.text),
                  ),
                  _ChipTag(
                    icon: AppIcons.image,
                    label: 'Image',
                    selected: isImage,
                    onTap: () => setState(() => _genType = GenType.image),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              const Text(
                'Tags',
                style: TextStyle(
                  color: Color(0xFF8E8E93),
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 12),
              Wrap(
                spacing: 10,
                runSpacing: 10,
                children: tagChips,
              ),
              const SizedBox(height: 16),
              Text(
                description,
                style: const TextStyle(color: Color(0xFF8E8E93), fontSize: 13),
              ),
              const SizedBox(height: 16),
              SizedBox(
                width: double.infinity,
                child: FilledButton(
                  onPressed: () => Navigator.of(context).pop(
                    _AiSettingsResult(
                      genType: _genType,
                      aiType: _aiType,
                      imageTag: _imageTag,
                    ),
                  ),
                  style: FilledButton.styleFrom(
                    shape: const StadiumBorder(),
                    minimumSize: const Size(0, 48),
                  ),
                  child: const Text(
                    'Done',
                    style: TextStyle(fontWeight: FontWeight.w700),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ChipTag extends StatelessWidget {
  const _ChipTag({
    required this.icon,
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String icon;
  final String label;
  final bool selected;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final background = selected ? Colors.black : const Color(0xFFF2F2F2);
    final foreground = selected ? Colors.white : const Color(0xFF1A1A1A);
    return Material(
      color: background,
      borderRadius: BorderRadius.circular(999),
      child: InkWell(
        borderRadius: BorderRadius.circular(999),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              AppIcon(icon, color: foreground, size: 16),
              const SizedBox(width: 8),
              Text(
                label,
                style: TextStyle(
                  color: foreground,
                  fontWeight: FontWeight.w400,
                  fontSize: 14,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

final RegExp _fenceOpen = RegExp(r'^[ \t]*```[ \t]*([\w+#.-]*)[ \t]*$');
final RegExp _fenceClose = RegExp(r'^[ \t]*```[ \t]*$');

/// A parsed chunk of an assistant reply: either prose or one fenced code
/// block.
class _MessageSegment {
  const _MessageSegment.text(String this.text)
      : language = null,
        code = null;

  const _MessageSegment.code(String this.language, String this.code)
      : text = null;

  final String? text;
  final String? language;
  final String? code;

  bool get isCode => code != null;
}

/// Splits an assistant reply into prose and ```fenced code blocks```.
List<_MessageSegment> _parseMessage(String content) {
  final segments = <_MessageSegment>[];
  final lines = content.split('\n');
  var i = 0;
  var textStart = 0;

  void flushText(int end) {
    if (end > textStart) {
      segments.add(
        _MessageSegment.text(lines.sublist(textStart, end).join('\n')),
      );
    }
  }

  while (i < lines.length) {
    final open = _fenceOpen.firstMatch(lines[i]);
    if (open == null) {
      i++;
      continue;
    }
    flushText(i);
    final language = (open.group(1) ?? '').trim();
    final codeStart = i + 1;
    var j = codeStart;
    while (j < lines.length && !_fenceClose.hasMatch(lines[j])) {
      j++;
    }
    segments.add(_MessageSegment.code(language, lines.sublist(codeStart, j).join('\n')));
    i = j + 1; // skip the closing fence (if present)
    textStart = i;
  }
  flushText(lines.length);
  return segments;
}

/// Renders an assistant reply, turning fenced code blocks into highlighted,
/// copyable boxes.
class _AssistantMessageView extends StatelessWidget {
  const _AssistantMessageView({required this.content});

  final String content;

  @override
  Widget build(BuildContext context) {
    final segments = _parseMessage(content);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (final segment in segments)
          if (segment.isCode)
            _CodeBlock(language: segment.language ?? '', code: segment.code ?? '')
          else
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Text(
                segment.text ?? '',
                style: const TextStyle(
                  color: Color(0xFF1A1A1A),
                  fontSize: 15,
                  height: 1.35,
                ),
              ),
            ),
      ],
    );
  }
}

/// A rounded, dark code block with a language label, a "Copy" action and a
/// horizontally scrollable, syntax-highlighted body.
class _CodeBlock extends StatefulWidget {
  const _CodeBlock({required this.language, required this.code});

  final String language;
  final String code;

  @override
  State<_CodeBlock> createState() => _CodeBlockState();
}

class _CodeBlockState extends State<_CodeBlock> {
  static const Color _background = Color(0xFFF6F6F6);
  static const Color _border = Color(0xFFE4E4E8);
  static const Color _muted = Color(0xFF8E8E93);
  static const Color _divider = Color(0xFFE4E4E8);

  bool _copied = false;

  Future<void> _copy() async {
    await Clipboard.setData(ClipboardData(text: widget.code));
    if (!mounted) return;
    setState(() => _copied = true);
    await Future<void>.delayed(const Duration(seconds: 2));
    if (mounted) setState(() => _copied = false);
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: 10),
      decoration: BoxDecoration(
        color: _background,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: _border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 6, 8, 6),
            child: Row(
              children: [
                Text(
                  _displayLabel(widget.language),
                  style: const TextStyle(
                    color: _muted,
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const Spacer(),
                InkWell(
                  onTap: _copy,
                  borderRadius: BorderRadius.circular(6),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 4,
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const AppIcon(AppIcons.copy, size: 13, color: _muted),
                        const SizedBox(width: 5),
                        Text(
                          _copied ? 'Copied' : 'Copy',
                          style: const TextStyle(color: _muted, fontSize: 12),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
          const Divider(height: 1, thickness: 1, color: _divider),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.fromLTRB(12, 10, 12, 12),
            child: _buildCode(),
          ),
        ],
      ),
    );
  }

  Widget _buildCode() {
    final tokens = tokenizeCode(widget.code, widget.language);
    return RichText(
      text: TextSpan(
        style: const TextStyle(
          color: Color(0xFF1A1A1A),
          fontSize: 13,
          height: 1.45,
        ),
        children: [
          for (final token in tokens)
            TextSpan(
              text: token.text,
              style: TextStyle(color: _codeColor(token.type)),
            ),
        ],
      ),
    );
  }
}

Color _codeColor(CodeTokenType type) {
  switch (type) {
    case CodeTokenType.keyword:
      return const Color(0xFFCF222E);
    case CodeTokenType.type:
      return const Color(0xFF953800);
    case CodeTokenType.function:
      return const Color(0xFF8250DF);
    case CodeTokenType.string:
      return const Color(0xFF0A3069);
    case CodeTokenType.comment:
      return const Color(0xFF6E7781);
    case CodeTokenType.number:
      return const Color(0xFF0550AE);
    case CodeTokenType.tag:
      return const Color(0xFF116329);
    case CodeTokenType.attribute:
      return const Color(0xFF953800);
    case CodeTokenType.plain:
      return const Color(0xFF1A1A1A);
  }
}

String _displayLabel(String language) {
  final lang = normalizeLanguage(language);
  const names = {
    'python': 'Python',
    'java': 'Java',
    'javascript': 'JavaScript',
    'typescript': 'TypeScript',
    'html': 'HTML',
    'css': 'CSS',
    'bash': 'Bash',
    'json': 'JSON',
    'yaml': 'YAML',
    'markdown': 'Markdown',
    'c': 'C',
    'cpp': 'C++',
    'csharp': 'C#',
    'kotlin': 'Kotlin',
    'swift': 'Swift',
    'dart': 'Dart',
    'go': 'Go',
    'rust': 'Rust',
    'php': 'PHP',
    'ruby': 'Ruby',
    'sql': 'SQL',
  };
  final name = names[lang];
  if (name != null) return name;
  if (lang.isEmpty || lang == 'plain') return 'Code';
  return lang[0].toUpperCase() + lang.substring(1);
}
