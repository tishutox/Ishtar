import 'dart:async';

import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:file_picker/file_picker.dart';
import 'package:image_picker/image_picker.dart';
import 'package:lumii_quest/core/icons/app_icons.dart';
import 'package:lumii_quest/features/fern/data/fern_repository.dart';
import 'package:lumii_quest/features/fern/data/local_llm_service.dart';
import 'package:lumii_quest/features/fern/data/media_file_io.dart';
import 'package:path_provider/path_provider.dart';
import 'package:record/record.dart';

const Color fernLilac = Color(0xFF8B5CF6);
const Color fernNsfwRed = Color(0xFFE53935);

/// Local-only chat with Fern, the built-in AI assistant.
///
/// Messages are stored on-device (not in the database) and replies come from
/// the Ollama cloud API.
class FernPage extends StatefulWidget {
  const FernPage({
    super.key,
    required this.conversation,
    required this.onChanged,
    required this.onToggleSidebar,
    required this.onNewChat,
  });

  final FernConversation conversation;
  final ValueChanged<FernConversation> onChanged;
  final VoidCallback onToggleSidebar;
  final VoidCallback onNewChat;

  @override
  State<FernPage> createState() => _FernPageState();
}

class _FernPageState extends State<FernPage> {
  final _repository = FernRepository();
  final _controller = TextEditingController();
  final _scrollController = ScrollController();
  final _recorder = AudioRecorder();
  late List<FernMessage> _messages;
  bool _sending = false;
  bool _generating = false;
  bool _abortRequested = false;
  bool _downloadingModel = false;
  bool _isDownloaded = false;
  bool _isRecording = false;
  bool _showAttachMenu = false;
  final List<double> _amplitudes = [];
  StreamSubscription<Amplitude>? _amplitudeSub;
  DateTime? _recordingStartedAt;
  final _inputAreaKey = GlobalKey();
  double _inputAreaHeight = 0;

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
    unawaited(_refreshDownloadedState());
  }

  @override
  void dispose() {
    _controller.removeListener(_handleTextChanged);
    _controller.dispose();
    _scrollController.dispose();
    _amplitudeSub?.cancel();
    unawaited(_recorder.dispose());
    super.dispose();
  }

  void _scrollToBottom() {
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
    widget.onChanged(
      widget.conversation.copyWith(
        title: title,
        messages: List.of(_messages),
        updatedAt: DateTime.now(),
      ),
    );
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

  Future<void> _refreshDownloadedState() async {
    final downloaded = await LocalLlmService.instance.isDownloaded();
    if (mounted) setState(() => _isDownloaded = downloaded);
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
        setState(() {
          _isDownloaded = true;
          if (ok) service.useLocal = true;
        });
        if (!ok) _showSnack('Could not load the local model.');
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

    final history = List<FernMessage>.of(_messages);
    setState(() {
      _messages = [
        ..._messages,
        FernMessage(role: 'user', content: text, sentAt: DateTime.now()),
      ];
      _sending = true;
      _generating = true;
    });
    _abortRequested = false;
    _scrollToBottom();

    String? reply;
    Object? error;
    try {
      reply = await _repository.sendMessage(history, text);
    } catch (e) {
      error = e;
    }

    if (!mounted) return;
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
          FernMessage(
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
        FernMessage(
          role: 'assistant',
          content: reply!,
          sentAt: DateTime.now(),
        ),
      ];
    });
    _scrollToBottom();

    if (shouldTitle) {
      final title = await _repository.generateTitle(text);
      if (mounted && title.isNotEmpty) {
        _persist(title: title);
        setState(() => _sending = false);
        return;
      }
    }

    _persist();
    setState(() => _sending = false);
  }

  void _cancelGeneration() {
    if (!_generating) return;
    _abortRequested = true;
    _repository.cancelActiveRequest();
  }

  Future<String> _mediaDir() async {
    final docs = await getApplicationDocumentsDirectory();
    return '${docs.path}/fern_media';
  }

  Future<void> _sendImages() async {
    if (_sending || _isRecording) return;
    final images = await ImagePicker().pickMultiImage(
      maxWidth: 1600,
      imageQuality: 85,
    );
    if (images.isEmpty || !mounted) return;
    await _sendPickedImages(images);
  }

  Future<void> _takePhoto() async {
    if (_sending || _isRecording) return;
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
      final messages = <FernMessage>[];
      for (final image in images) {
        final extension = _imageExtension(image.name);
        final dest =
            '$dir/fern_${DateTime.now().microsecondsSinceEpoch}.$extension';
        final bytes = await image.readAsBytes();
        await writeMediaFile(dest, bytes);
        messages.add(
          FernMessage(
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
    if (_sending || _isRecording) return;
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
      final dest = '$dir/fern_${DateTime.now().microsecondsSinceEpoch}_$name';
      final bytes = await readMediaFile(path);
      await writeMediaFile(dest, bytes);
      setState(() {
        _messages = [
          ..._messages,
          FernMessage(
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

  Future<void> _toggleRecording() async {
    if (_isRecording) {
      await _cancelRecording();
    } else {
      await _startRecording();
    }
  }

  Future<void> _startRecording() async {
    if (_sending) return;
    final hasPermission = await _recorder.hasPermission();
    if (!hasPermission) {
      _showSnack('Microphone permission is required to record.');
      return;
    }
    final isAndroid = defaultTargetPlatform == TargetPlatform.android;
    final encoder = isAndroid ? AudioEncoder.aacLc : AudioEncoder.wav;
    final extension = isAndroid ? 'm4a' : 'wav';
    final dir = await getTemporaryDirectory();
    final path =
        '${dir.path}/lumii_voice_${DateTime.now().millisecondsSinceEpoch}.$extension';
    try {
      await _recorder.start(RecordConfig(encoder: encoder), path: path);
    } catch (error) {
      _showSnack('Recording could not start: $error');
      return;
    }
    _amplitudes.clear();
    _amplitudeSub?.cancel();
    _amplitudeSub = _recorder
        .onAmplitudeChanged(const Duration(milliseconds: 120))
        .listen((amplitude) {
          if (mounted) {
            setState(() => _amplitudes.add(amplitude.current));
          }
        });
    if (mounted) {
      setState(() {
        _isRecording = true;
        _recordingStartedAt = DateTime.now();
        _showAttachMenu = false;
      });
    }
  }

  Future<void> _cancelRecording() async {
    _amplitudeSub?.cancel();
    _amplitudeSub = null;
    await _recorder.cancel();
    if (mounted) {
      setState(() {
        _isRecording = false;
        _amplitudes.clear();
        _recordingStartedAt = null;
      });
    }
  }

  Future<void> _finishRecording() async {
    _amplitudeSub?.cancel();
    _amplitudeSub = null;
    final path = await _recorder.stop();
    if (!mounted) return;
    final duration = _recordingStartedAt == null
        ? 0.0
        : DateTime.now().difference(_recordingStartedAt!).inMilliseconds /
              1000.0;
    setState(() {
      _isRecording = false;
      _amplitudes.clear();
      _recordingStartedAt = null;
    });
    if (path == null) return;
    setState(() => _sending = true);
    try {
      final dir = await _mediaDir();
      final extension = _audioExtension(path);
      final dest =
          '$dir/fern_${DateTime.now().microsecondsSinceEpoch}.$extension';
      final bytes = await readMediaFile(path);
      await writeMediaFile(dest, bytes);
      setState(() {
        _messages = [
          ..._messages,
          FernMessage(
            role: 'user',
            content: '',
            sentAt: DateTime.now(),
            kind: 'audio',
            mediaPath: dest,
            mediaDuration: duration,
          ),
        ];
      });
      _persist();
      _scrollToBottom();
      await _acknowledgeMedia('audio');
    } catch (error) {
      _showSnack('Voice message could not be sent: $error');
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  Future<void> _acknowledgeMedia(String kind) async {
    final reply = switch (kind) {
      'audio' =>
        "I can only read text, so I can't hear voice messages. Send me a text and I'll answer.",
      'file' =>
        "I can only read text, so I can't open files. Tell me what it says.",
      _ =>
        "I can only read text, so I can't see images. Tell me what it says.",
    };
    setState(() {
      _messages = [
        ..._messages,
        FernMessage(role: 'assistant', content: reply, sentAt: DateTime.now()),
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
            tooltip: useLocal
                ? 'Deactivate NSFW (cloud)'
                : 'Activate NSFW (local)',
            onPressed: _toggleLocalModel,
            style: useLocal
                ? IconButton.styleFrom(
                    backgroundColor: fernNsfwRed.withValues(alpha: 0.18),
                  )
                : null,
            icon: _downloadingModel
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: fernNsfwRed,
                    ),
                  )
                : AppIcon(
                    _isDownloaded ? AppIcons.ban : AppIcons.arrowBigDownDash,
                    color: useLocal ? fernNsfwRed : null,
                  ),
          ),
          IconButton(
            tooltip: 'New chat',
            onPressed: widget.onNewChat,
            icon: const AppIcon(AppIcons.messageCirclePlus),
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
                          return _FernBubble(
                            message: _messages[index],
                            isMine: _messages[index].role == 'user',
                          );
                        },
                      ),
              ),
              KeyedSubtree(
                key: _inputAreaKey,
                child: SafeArea(
                  top: false,
                  child: _buildInputBar(),
                ),
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
      if (_isRecording) {
        return _RecordingInputBar(
          amplitudes: _amplitudes,
          onCancel: _cancelRecording,
          onFinish: _finishRecording,
        );
      }
      return _FernMediaInputBar(
        controller: _controller,
        isSending: _sending,
        isGenerating: _generating,
        showAttachMenu: _showAttachMenu,
        onSend: _send,
        onCancel: _cancelGeneration,
        onToggleAttachMenu: _toggleAttachMenu,
        onToggleRecording: _toggleRecording,
      );
    }
    return _FernTextInputBar(
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
            const AppIcon(AppIcons.bot, size: 42, color: fernLilac),
            const SizedBox(height: 12),
            Text(
              'Say hi to Fern',
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.w800,
              ),
            ),
            const SizedBox(height: 6),
            const Text(
              'Fern is a local AI assistant. Your conversation stays on this '
              'device and is gone when you log out or uninstall the app.',
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }
}

class _FernMediaInputBar extends StatelessWidget {
  const _FernMediaInputBar({
    required this.controller,
    required this.isSending,
    required this.isGenerating,
    required this.showAttachMenu,
    required this.onSend,
    required this.onCancel,
    required this.onToggleAttachMenu,
    required this.onToggleRecording,
  });

  final TextEditingController controller;
  final bool isSending;
  final bool isGenerating;
  final bool showAttachMenu;
  final Future<void> Function() onSend;
  final VoidCallback onCancel;
  final VoidCallback onToggleAttachMenu;
  final Future<void> Function() onToggleRecording;

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
                enabled: !isSending,
                textInputAction: TextInputAction.send,
                onSubmitted: (_) => onSend(),
                decoration: const InputDecoration(
                  hintText: 'Message Fern',
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
            if (hasText)
              _CircleIconButton(
                tooltip: 'Send',
                icon: isSending ? AppIcons.loaderCircle : AppIcons.sendHorizontal,
                backgroundColor: primary,
                iconColor: Colors.white,
                onPressed: isSending ? null : onSend,
              )
            else ...[
              IconButton(
                tooltip: 'Voice message',
                onPressed: isSending ? null : onToggleRecording,
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(
                  minWidth: 44,
                  minHeight: 44,
                ),
                icon: AppIcon(AppIcons.mic, color: primary),
              ),
              AnimatedRotation(
                turns: (isGenerating || showAttachMenu) ? 0.125 : 0,
                duration: const Duration(milliseconds: 200),
                child: _CircleIconButton(
                  tooltip: isGenerating ? 'Stop' : 'Attach',
                  icon: AppIcons.circlePlus,
                  backgroundColor: primary,
                  iconColor: Colors.white,
                  onPressed: isGenerating
                      ? onCancel
                      : (isSending ? null : onToggleAttachMenu),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _FernTextInputBar extends StatelessWidget {
  const _FernTextInputBar({
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
              textInputAction: TextInputAction.send,
              onSubmitted: (_) => onSend(),
              decoration: InputDecoration(
                hintText: 'Message Fern',
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

class _RecordingInputBar extends StatelessWidget {
  const _RecordingInputBar({
    required this.amplitudes,
    required this.onCancel,
    required this.onFinish,
  });

  final List<double> amplitudes;
  final VoidCallback onCancel;
  final VoidCallback onFinish;

  @override
  Widget build(BuildContext context) {
    final primary = Theme.of(context).colorScheme.primary;
    final error = Theme.of(context).colorScheme.error;
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
            _CircleIconButton(
              tooltip: 'Cancel recording',
              icon: AppIcons.trash,
              backgroundColor: error.withValues(alpha: 0.16),
              iconColor: error,
              onPressed: onCancel,
            ),
            const SizedBox(width: 8),
            Expanded(child: _RecordingWaveform(amplitudes: amplitudes)),
            const SizedBox(width: 8),
            _CircleIconButton(
              tooltip: 'Send voice message',
              icon: AppIcons.sendHorizontal,
              backgroundColor: primary,
              iconColor: Colors.white,
              onPressed: onFinish,
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

class _RecordingWaveform extends StatelessWidget {
  const _RecordingWaveform({required this.amplitudes});

  final List<double> amplitudes;

  @override
  Widget build(BuildContext context) {
    final primary = Theme.of(context).colorScheme.primary;
    final samples = amplitudes.isEmpty
        ? List<double>.filled(28, 0.25)
        : amplitudes.length > 40
        ? amplitudes.sublist(amplitudes.length - 40)
        : amplitudes;

    return Container(
      height: 48,
      padding: const EdgeInsets.symmetric(horizontal: 12),
      alignment: Alignment.centerLeft,
      child: ClipRect(
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            for (var i = 0; i < samples.length; i++) ...[
              if (i > 0) const SizedBox(width: 3),
              Container(
                width: 3,
                height: 6 + _normalizeAmplitude(samples[i]) * 36,
                decoration: BoxDecoration(
                  color: primary,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _FernBubble extends StatelessWidget {
  const _FernBubble({required this.message, required this.isMine});

  final FernMessage message;
  final bool isMine;

  @override
  Widget build(BuildContext context) {
    switch (message.kind) {
      case 'image':
        return Align(
          alignment: isMine ? Alignment.centerRight : Alignment.centerLeft,
          child: _FernImageBubble(path: message.mediaPath ?? ''),
        );
      case 'audio':
        return Align(
          alignment: isMine ? Alignment.centerRight : Alignment.centerLeft,
          child: _FernAudioBubble(
            path: message.mediaPath ?? '',
            duration: message.mediaDuration ?? 0,
            isMine: isMine,
          ),
        );
      case 'file':
        return Align(
          alignment: isMine ? Alignment.centerRight : Alignment.centerLeft,
          child: _FernFileBubble(
            fileName: message.fileName ?? 'File',
            isMine: isMine,
          ),
        );
      default:
        return Align(
          alignment: isMine ? Alignment.centerRight : Alignment.centerLeft,
          child: Container(
            margin: const EdgeInsets.only(bottom: 10),
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            constraints: const BoxConstraints(maxWidth: 300),
            decoration: BoxDecoration(
              color: isMine ? Colors.black : const Color(0xFFF2F2F2),
              borderRadius: BorderRadius.circular(16),
            ),
            child: Text(
              message.content,
              style: TextStyle(
                color: isMine ? Colors.white : const Color(0xFF1A1A1A),
                fontSize: 15,
                height: 1.35,
              ),
            ),
          ),
        );
    }
  }
}

class _FernFileBubble extends StatelessWidget {
  const _FernFileBubble({required this.fileName, required this.isMine});

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

class _FernImageBubble extends StatelessWidget {
  const _FernImageBubble({required this.path});

  final String path;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(16),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 260),
          child: FutureBuilder<Uint8List>(
            future: readMediaFile(path),
            builder: (context, snapshot) {
              if (snapshot.hasError) {
                return const SizedBox(
                  width: 180,
                  height: 140,
                  child: Center(child: AppIcon(AppIcons.imageOff)),
                );
              }
              if (!snapshot.hasData) {
                return const SizedBox(
                  width: 180,
                  height: 140,
                  child: Center(child: CircularProgressIndicator()),
                );
              }
              return Image.memory(
                snapshot.data!,
                fit: BoxFit.cover,
                filterQuality: FilterQuality.medium,
              );
            },
          ),
        ),
      ),
    );
  }
}

class _FernAudioBubble extends StatefulWidget {
  const _FernAudioBubble({
    required this.path,
    required this.duration,
    required this.isMine,
  });

  final String path;
  final double duration;
  final bool isMine;

  @override
  State<_FernAudioBubble> createState() => _FernAudioBubbleState();
}

class _FernAudioBubbleState extends State<_FernAudioBubble> {
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

String _audioExtension(String path) {
  final extension = path.split('.').last.toLowerCase();
  return extension.isEmpty ? 'm4a' : extension;
}

double _normalizeAmplitude(double db) {
  return ((db + 60) / 60).clamp(0.06, 1.0);
}
