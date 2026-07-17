import 'package:flutter_prerender/flutter_prerender.dart';
import 'package:test/test.dart';

void main() {
  const guard = ParityGuard();

  test('identical text is not suspicious', () {
    final report = guard.compare(
      'Quintessential Ethiopian Yirgacheffe beans',
      'Quintessential Ethiopian Yirgacheffe beans',
    );
    expect(report.similarity, 1.0);
    expect(report.injectedWords, isEmpty);
    expect(report.isSuspicious, isFalse);
  });

  test('a subset of the source is not suspicious', () {
    final report = guard.compare(
      'Ethiopian Yirgacheffe beans roasted fresh weekly',
      'Ethiopian Yirgacheffe beans',
    );
    expect(report.injectedWords, isEmpty);
    expect(report.missingWords, isNotEmpty);
    expect(report.isSuspicious, isFalse);
  });

  test('injected crawler-only words are flagged as cloaking', () {
    final report = guard.compare(
      'Ethiopian Yirgacheffe beans',
      'Ethiopian Yirgacheffe beans cheap viagra casino discount',
    );
    expect(report.injectedWords, contains('viagra'));
    expect(report.injectedWords, contains('casino'));
    expect(report.isSuspicious, isTrue);
  });

  test('completely different content is flagged (cats vs dogs)', () {
    final report = guard.compare('cats purr softly', 'dogs bark loudly');
    expect(report.injectionRatio, 1.0);
    expect(report.isSuspicious, isTrue);
  });

  test('a small injection within tolerance is not flagged', () {
    const lenient = ParityGuard(threshold: 0.5);
    // One of four generated words is new -> 0.25 ratio, under the 0.5
    // tolerance implied by threshold 0.5.
    final report = lenient.compare(
      'alpha bravo charlie',
      'alpha bravo charlie delta',
    );
    expect(report.injectionRatio, closeTo(0.25, 0.001));
    expect(report.isSuspicious, isFalse);
  });

  test('comparison is case-insensitive', () {
    final report = guard.compare('Coffee Beans', 'coffee beans');
    expect(report.similarity, 1.0);
    expect(report.isSuspicious, isFalse);
  });

  test('two empty strings are treated as matching', () {
    final report = guard.compare('', '');
    expect(report.similarity, 1.0);
    expect(report.isSuspicious, isFalse);
  });
}
