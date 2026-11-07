import 'dart:math';

/// Time-ordered, collision-resistant id used for file names and gallery items.
String newId() {
  final timestamp = DateTime.now().microsecondsSinceEpoch.toRadixString(36);
  final suffix = _random.nextInt(1 << 32).toRadixString(36).padLeft(7, '0');
  return '$timestamp-$suffix';
}

final Random _random = Random();
