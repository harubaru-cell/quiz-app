import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/material.dart';

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
  final AudioPlayer _player = AudioPlayer();

  bool _isLoading = false;

  bool _isNetworkAudio(String path) {
    final uri = Uri.tryParse(path);

    return uri != null && (uri.scheme == 'http' || uri.scheme == 'https');
  }

  String _normalizeAssetPath(String path) {
    final normalizedPath = path.replaceAll('\\', '/');

    if (normalizedPath.startsWith('assets/')) {
      return normalizedPath.substring('assets/'.length);
    }

    return normalizedPath;
  }

  Future<void> _playAudio() async {
    if (_isLoading) {
      return;
    }

    setState(() {
      _isLoading = true;
    });

    try {
      await _player.stop();

      final Source source;

      if (_isNetworkAudio(widget.audioPath)) {
        source = UrlSource(widget.audioPath);
      } else {
        source = AssetSource(
          _normalizeAssetPath(widget.audioPath),
        );
      }

      await _player.play(source);
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
