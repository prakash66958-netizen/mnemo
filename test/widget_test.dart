// Basic smoke test for the classifier + promise detector. The UI is skipped
// here because it depends on native Isar / notifications which aren't set up
// in the plain test environment.

import 'package:flutter_test/flutter_test.dart';
import 'package:mnemo/core/category.dart';
import 'package:mnemo/services/classifier_service.dart';
import 'package:mnemo/services/promise_detector.dart';

void main() {
  test('classifier tags shopping-like text', () {
    final c = ClassifierService.instance.classify('buy milk and bread');
    expect(c, MemoryCategory.shopping);
  });

  test('promise detector flags Hinglish "bhej dunga"', () {
    final d = PromiseDetector.instance.detect('Kal morning bhej dunga');
    expect(d.hasPromise, true);
  });

  test('promise detector parses "tomorrow 5pm"', () {
    final d = PromiseDetector.instance
        .detect("I'll call you tomorrow at 5pm");
    expect(d.hasPromise, true);
    expect(d.suggestedTime, isNotNull);
  });
}
