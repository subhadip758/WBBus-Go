/// Lightweight text matching used by the bus search — no external
/// dependency needed. Supports:
///  - case-insensitive matching
///  - partial / substring matching
///  - basic typo tolerance via Levenshtein distance on whole words
class TextMatch {
  /// Returns true if [needle] reasonably matches [haystack]:
  /// either as a direct substring, or as a close-enough typo of a word in it.
  static bool fuzzyContains(String haystack, String needle) {
    final h = haystack.toLowerCase().trim();
    final n = needle.toLowerCase().trim();
    if (n.isEmpty) return true;
    if (h.contains(n)) return true;

    // Typo tolerance: compare needle against each word/token in haystack.
    final words = h.split(RegExp(r'[\s,()]+')).where((w) => w.isNotEmpty);
    final maxAllowedDistance = n.length <= 4 ? 1 : 2;
    for (final w in words) {
      if (_levenshtein(w, n) <= maxAllowedDistance) return true;
      // also check prefix distance for longer place names typed partially
      if (w.length >= n.length &&
          _levenshtein(w.substring(0, n.length), n) <= maxAllowedDistance) {
        return true;
      }
    }
    return false;
  }

  static int _levenshtein(String a, String b) {
    if (a == b) return 0;
    if (a.isEmpty) return b.length;
    if (b.isEmpty) return a.length;

    final List<List<int>> dp =
        List.generate(a.length + 1, (_) => List.filled(b.length + 1, 0));

    for (var i = 0; i <= a.length; i++) dp[i][0] = i;
    for (var j = 0; j <= b.length; j++) dp[0][j] = j;

    for (var i = 1; i <= a.length; i++) {
      for (var j = 1; j <= b.length; j++) {
        final cost = a[i - 1] == b[j - 1] ? 0 : 1;
        dp[i][j] = [
          dp[i - 1][j] + 1,
          dp[i][j - 1] + 1,
          dp[i - 1][j - 1] + cost,
        ].reduce((v, e) => v < e ? v : e);
      }
    }
    return dp[a.length][b.length];
  }
}
