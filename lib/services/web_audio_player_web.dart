import 'dart:js_interop';
import 'dart:typed_data';

import 'package:web/web.dart' as web;

class WebAudioPlayer {
  web.HTMLAudioElement? _audioElement;
  String? _objectUrl;

  Future<void> playBytes(
    Uint8List bytes, {
    String? mimeType,
  }) async {
    await stop();

    if (bytes.isEmpty) {
      throw const FormatException(
        '音声データが空です。',
      );
    }

    final blob = web.Blob(
      [bytes.toJS].toJS,
      web.BlobPropertyBag(
        type: mimeType ?? 'application/octet-stream',
      ),
    );

    final objectUrl = web.URL.createObjectURL(blob);

    _objectUrl = objectUrl;

    try {
      await _playSource(objectUrl);
    } catch (_) {
      _releaseObjectUrl();
      rethrow;
    }
  }

  Future<void> playUrl(String url) async {
    await stop();

    if (url.trim().isEmpty) {
      throw const FormatException(
        '音声URLが空です。',
      );
    }

    await _playSource(url);
  }

  Future<void> _playSource(String source) async {
    final audioElement = web.HTMLAudioElement()
      ..src = source
      ..preload = 'auto';

    _audioElement = audioElement;

    await audioElement.play().toDart;
  }

  Future<void> stop() async {
    final audioElement = _audioElement;

    if (audioElement != null) {
      audioElement.pause();
      audioElement.removeAttribute('src');
      audioElement.load();
    }

    _audioElement = null;

    _releaseObjectUrl();
  }

  void _releaseObjectUrl() {
    final objectUrl = _objectUrl;

    if (objectUrl != null) {
      web.URL.revokeObjectURL(objectUrl);
    }

    _objectUrl = null;
  }

  void dispose() {
    final audioElement = _audioElement;

    if (audioElement != null) {
      audioElement.pause();
      audioElement.removeAttribute('src');
      audioElement.load();
    }

    _audioElement = null;

    _releaseObjectUrl();
  }
}
