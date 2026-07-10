import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../services/audio_storage_service.dart';
import '../services/web_audio_player.dart';

class QuestionAudioButton extends StatefulWidget {
  const QuestionAudioButton({
    required this.audioPath,
    super.key,
  });

  final String audioPath;

  @override
  State<QuestionAudioButton> createState() => _QuestionAudioButtonState();
}

class _QuestionAudioButtonState extends State<QuestionAudioButton> {
  final WebAudioPlayer _player = WebAudioPlayer();

  bool _isLoading = false;

  bool _isNetworkAudio(String path) {
    final uri = Uri.tryParse(path);

    return uri != null && (uri.scheme == 'http' || uri.scheme == 'https');
  }

  String _normalizeAssetPath(String path) {
    var normalizedPath = path.replaceAll('\\', '/');

    while (normalizedPath.startsWith('/')) {
      normalizedPath = normalizedPath.substring(1);
    }

    if (normalizedPath.startsWith('assets/')) {
      return normalizedPath;
    }

    return 'assets/$normalizedPath';
  }

  String? _mimeTypeFromPath(String path) {
    final normalizedPath = path.toLowerCase().split('?').first;

    if (normalizedPath.endsWith('.mp3')) {
      return 'audio/mpeg';
    }

    if (normalizedPath.endsWith('.m4a')) {
      return 'audio/mp4';
    }

    if (normalizedPath.endsWith('.wav')) {
      return 'audio/wav';
    }

    if (normalizedPath.endsWith('.ogg')) {
      return 'audio/ogg';
    }

    if (normalizedPath.endsWith('.aac')) {
      return 'audio/aac';
    }

    if (normalizedPath.endsWith('.webm')) {
      return 'audio/webm';
    }

    return null;
  }

  Future<Uint8List> _loadAssetBytes(
    String assetPath,
  ) async {
    final byteData = await rootBundle.load(
      _normalizeAssetPath(assetPath),
    );

    return byteData.buffer.asUint8List(
      byteData.offsetInBytes,
      byteData.lengthInBytes,
    );
  }

  Future<void> _playAudio() async {
    if (_isLoading) {
      return;
    }

    setState(() {
      _isLoading = true;
    });

    try {
      final audioPath = widget.audioPath;
      final storageService = AudioStorageService.instance;

      if (storageService.isStoredAudioReference(audioPath)) {
        final storageKey = storageService.getStorageKeyFromReference(audioPath);

        final bytes = await storageService.loadAudio(storageKey);

        if (bytes == null || bytes.isEmpty) {
          throw StateError(
            '端末内に音声データが見つかりません。',
          );
        }

        await _player.playBytes(
          bytes,
          mimeType: _mimeTypeFromPath(storageKey),
        );
      } else if (_isNetworkAudio(audioPath)) {
        await _player.playUrl(audioPath);
      } else {
        final bytes = await _loadAssetBytes(audioPath);

        if (bytes.isEmpty) {
          throw StateError(
            '音声ファイルが空です。',
          );
        }

        await _player.playBytes(
          bytes,
          mimeType: _mimeTypeFromPath(audioPath),
        );
      }
    } catch (error) {
      if (!mounted) {
        return;
      }

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            '音声を再生できませんでした。\n$error',
          ),
        ),
      );
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  @override
  void dispose() {
    _player.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return OutlinedButton.icon(
      onPressed: _isLoading ? null : _playAudio,
      icon: _isLoading
          ? const SizedBox(
              width: 20,
              height: 20,
              child: CircularProgressIndicator(
                strokeWidth: 2,
              ),
            )
          : const Icon(Icons.volume_up),
      label: Text(
        _isLoading ? '読み込み中…' : '音声を再生',
      ),
    );
  }
}
