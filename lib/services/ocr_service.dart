import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';

/// On-device OCR wrapper using Google ML Kit.
///
/// Runs fully offline once the ML Kit model is present on the device. We lazy-
/// init the recognizer and close it when explicitly requested by the caller.
class OcrService {
  OcrService._();
  static final OcrService instance = OcrService._();

  TextRecognizer? _recognizer;

  TextRecognizer _get() =>
      _recognizer ??= TextRecognizer(script: TextRecognitionScript.latin);

  /// Extracts text from the image at [path]. Returns an empty string if no
  /// text was found (or the model failed).
  Future<String> extractText(String path) async {
    try {
      final input = InputImage.fromFilePath(path);
      final result = await _get().processImage(input);
      return result.text.trim();
    } catch (_) {
      return '';
    }
  }

  Future<void> dispose() async {
    await _recognizer?.close();
    _recognizer = null;
  }
}
