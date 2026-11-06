import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:prism_pour/features/audio/audio_backend.dart';

/// A decoded 16-bit PCM WAV.
class Wav {
  Wav(this.channels, this.rate, this.bits, this.samples);
  final int channels, rate, bits;
  final List<int> samples;
  double get seconds => samples.length / channels / rate;
  int get peak => samples.fold(0, (m, s) => s.abs() > m ? s.abs() : m);
}

Wav readWav(File f) {
  final b = f.readAsBytesSync();
  final d = ByteData.sublistView(b);
  String tag(int o) => String.fromCharCodes(b.sublist(o, o + 4));
  expect(tag(0), 'RIFF');
  expect(tag(8), 'WAVE');
  var o = 12;
  int? channels, rate, bits;
  List<int>? samples;
  while (o + 8 <= b.length) {
    final id = tag(o);
    final size = d.getUint32(o + 4, Endian.little);
    if (id == 'fmt ') {
      expect(d.getUint16(o + 8, Endian.little), 1, reason: 'PCM');
      channels = d.getUint16(o + 10, Endian.little);
      rate = d.getUint32(o + 12, Endian.little);
      bits = d.getUint16(o + 22, Endian.little);
    } else if (id == 'data') {
      samples = [
        for (var i = 0; i < size; i += 2) d.getInt16(o + 8 + i, Endian.little),
      ];
    }
    o += 8 + size + (size.isOdd ? 1 : 0);
  }
  return Wav(channels!, rate!, bits!, samples!);
}

File asset(String path) => File('assets/$path');

void main() {
  group('bundled audio', () {
    test('every sound the game plays exists and is declared in pubspec', () {
      final pubspec = File('pubspec.yaml').readAsStringSync();
      expect(pubspec, contains('assets/audio/'));
      for (final e in SoundEffect.values) {
        expect(asset(e.asset).existsSync(), isTrue, reason: e.asset);
      }
      expect(asset(kMusicAsset).existsSync(), isTrue);
    });

    test('there are no stray audio files nothing refers to', () {
      final used = {
        for (final e in SoundEffect.values) e.asset.split('/').last,
        kMusicAsset.split('/').last,
      };
      final onDisk = Directory('assets/audio')
          .listSync()
          .whereType<File>()
          .map((f) => f.uri.pathSegments.last)
          .where((n) => n.endsWith('.wav'))
          .toSet();
      expect(onDisk, used);
    });

    test('files are small, mono 16-bit PCM', () {
      for (final path in [
        for (final e in SoundEffect.values) e.asset,
        kMusicAsset,
      ]) {
        final f = asset(path);
        final w = readWav(f);
        expect(w.channels, 1, reason: path);
        expect(w.bits, 16, reason: path);
        expect(w.rate, inInclusiveRange(16000, 48000), reason: path);
        expect(f.lengthSync(), lessThan(2 * 1024 * 1024), reason: path);
      }
    });

    test('effects are short, audible and never clip', () {
      for (final e in SoundEffect.values) {
        final w = readWav(asset(e.asset));
        expect(w.seconds, inInclusiveRange(0.1, 3.0), reason: e.asset);
        expect(w.peak, greaterThan(32767 * 0.3), reason: '${e.asset} audible');
        expect(w.peak, lessThan(32767 * 0.95), reason: '${e.asset} no clip');
      }
    });

    test('effects start and end quietly, so they do not click', () {
      for (final e in SoundEffect.values) {
        final w = readWav(asset(e.asset));
        final first = w.samples.first.abs();
        final last = w.samples.last.abs();
        expect(first, lessThan(32767 * 0.05), reason: '${e.asset} start');
        expect(last, lessThan(32767 * 0.02), reason: '${e.asset} end');
      }
    });

    test('the music is a long, quiet, seamless loop', () {
      final w = readWav(asset(kMusicAsset));
      expect(w.seconds, greaterThanOrEqualTo(20));
      expect(w.peak, lessThan(32767 * 0.7), reason: 'sits under the effects');
      // The loop point: the last sample flows into the first with a step no
      // bigger than the ordinary sample-to-sample movement.
      final s = w.samples;
      var maxStep = 0;
      for (var i = 1; i < s.length; i++) {
        final d = (s[i] - s[i - 1]).abs();
        if (d > maxStep) maxStep = d;
      }
      final seam = (s.first - s.last).abs();
      expect(seam, lessThanOrEqualTo(maxStep * 2 + 50));
    });

    test('the licence note says the audio is original', () {
      final readme = File('assets/audio/README.md').readAsStringSync();
      expect(readme.toLowerCase(), contains('original'));
      expect(readme, contains('generate_audio.py'));
      expect(File('tool/generate_audio.py').existsSync(), isTrue);
    });

    test('every effect has a distinct file and a sensible pool', () {
      final files = SoundEffect.values.map((e) => e.asset).toSet();
      expect(files, hasLength(SoundEffect.values.length));
      for (final e in SoundEffect.values) {
        expect(e.poolSize, inInclusiveRange(1, 4));
        expect(e.volume, inInclusiveRange(0.1, 1.0));
      }
      expect(kMusicVolume, lessThan(0.6));
    });
  });
}
