import 'package:intl/intl.dart';

class TimeUtils {
  /// Converts a stored "HH:mm" (24hr) string into "h:mm a" (e.g. "9:10 PM").
  /// Returns "--:--" if the value is null/unparseable, since we never
  /// fabricate a time the source data didn't actually contain.
  static String formatDisplay(String? hhmm) {
    if (hhmm == null || hhmm.isEmpty) return '--:--';
    final parts = hhmm.split(':');
    if (parts.length != 2) return '--:--';
    final h = int.tryParse(parts[0]);
    final m = int.tryParse(parts[1]);
    if (h == null || m == null) return '--:--';
    final dt = DateTime(2000, 1, 1, h, m);
    return DateFormat('h:mm a').format(dt);
  }

  /// Rough duration text between two "HH:mm" times, handling overnight
  /// routes (arrival time earlier than departure means it lands next day).
  static String? durationBetween(String? dep, String? arr) {
    if (dep == null || arr == null) return null;
    final d = _toMinutes(dep);
    var a = _toMinutes(arr);
    if (d == null || a == null) return null;
    if (a < d) a += 24 * 60;
    final diff = a - d;
    final hrs = diff ~/ 60;
    final mins = diff % 60;
    if (hrs == 0) return '${mins}m';
    if (mins == 0) return '${hrs}h';
    return '${hrs}h ${mins}m';
  }

  static int? _toMinutes(String hhmm) {
    final parts = hhmm.split(':');
    if (parts.length != 2) return null;
    final h = int.tryParse(parts[0]);
    final m = int.tryParse(parts[1]);
    if (h == null || m == null) return null;
    return h * 60 + m;
  }
}
