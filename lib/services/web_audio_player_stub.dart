import 'dart:typed_data';

class WebAudioPlayer {
  Future<void> playBytes(
    Uint8List bytes, {
    String? mimeType,
  }) async {
    throw UnsupportedError(
      'この環境ではブラウザ音声を再生できません。',
    );
  }

  Future<void> playUrl(String url) async {
    throw UnsupportedError(
      'この環境ではブラウザ音声を再生できません。',
    );
  }

  Future<void> stop() async {}

  void dispose() {}
}
