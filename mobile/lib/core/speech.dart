import 'package:flutter_tts/flutter_tts.dart';

/// Device speech output. Free, offline-capable, and used for both the Live
/// text replies and the fallback chain.
class SpeechService {
  SpeechService();

  final FlutterTts _tts = FlutterTts();
  bool _ready = false;

  Future<void> _ensureReady() async {
    if (_ready) return;
    try {
      await _tts.setLanguage('ar-EG');
      await _tts.setSpeechRate(0.48);
      await _tts.setPitch(1.0);
      await _tts.awaitSpeakCompletion(false);
    } catch (_) {
      // A device without an Arabic TTS voice still shows the text reply.
    }
    _ready = true;
  }

  Future<void> speak(String text) async {
    if (text.trim().isEmpty) return;
    await _ensureReady();
    try {
      await stop();
      await _tts.speak(text);
    } catch (_) {
      // Never let a missing TTS engine break the voice flow.
    }
  }

  Future<void> stop() async {
    try {
      await _tts.stop();
    } catch (_) {}
  }

  Future<void> dispose() async {
    try {
      await _tts.stop();
    } catch (_) {}
  }
}
