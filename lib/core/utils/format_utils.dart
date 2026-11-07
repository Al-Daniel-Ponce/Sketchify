import 'package:intl/intl.dart';

final DateFormat _dateFormat = DateFormat('d MMM yyyy, h:mm a');

String formatBytes(int bytes) {
  if (bytes < 1024) return '$bytes B';
  final kb = bytes / 1024;
  if (kb < 1024) return '${kb.toStringAsFixed(kb < 10 ? 1 : 0)} KB';
  final mb = kb / 1024;
  if (mb < 1024) return '${mb.toStringAsFixed(mb < 10 ? 1 : 0)} MB';
  final gb = mb / 1024;
  return '${gb.toStringAsFixed(1)} GB';
}

String formatDate(DateTime date) => _dateFormat.format(date.toLocal());

String formatShortDate(DateTime date) {
  final now = DateTime.now();
  final local = date.toLocal();
  final sameDay =
      now.year == local.year &&
      now.month == local.month &&
      now.day == local.day;
  if (sameDay) return 'Today, ${DateFormat('h:mm a').format(local)}';
  return _dateFormat.format(local);
}

String formatCount(int value, String singular, [String? plural]) {
  return '$value ${value == 1 ? singular : (plural ?? '${singular}s')}';
}
