/// The twelve Western (tropical) zodiac signs, each mapped to its Lucide
/// `zodiac-*` SVG asset.
enum ZodiacSign {
  aries('zodiac-aries', 'Aries'),
  taurus('zodiac-taurus', 'Taurus'),
  gemini('zodiac-gemini', 'Gemini'),
  cancer('zodiac-cancer', 'Cancer'),
  leo('zodiac-leo', 'Leo'),
  virgo('zodiac-virgo', 'Virgo'),
  libra('zodiac-libra', 'Libra'),
  scorpio('zodiac-scorpio', 'Scorpio'),
  sagittarius('zodiac-sagittarius', 'Sagittarius'),
  capricorn('zodiac-capricorn', 'Capricorn'),
  aquarius('zodiac-aquarius', 'Aquarius'),
  pisces('zodiac-pisces', 'Pisces');

  const ZodiacSign(this.icon, this.label);

  /// Kebab-case asset name under `svg/`.
  final String icon;
  final String label;

  static ZodiacSign? fromName(String? name) {
    if (name == null || name.isEmpty) return null;
    for (final sign in values) {
      if (sign.name == name) return sign;
    }
    return null;
  }
}

/// Returns the tropical zodiac sign for [date], or null when it cannot be
/// determined.
ZodiacSign? zodiacFromDate(DateTime date) {
  final m = date.month;
  final d = date.day;
  // (startMonth, startDay, endMonth, endDay, sign). Capricorn wraps the year.
  const ranges = <(int, int, int, int, ZodiacSign)>[
    (3, 21, 4, 19, ZodiacSign.aries),
    (4, 20, 5, 20, ZodiacSign.taurus),
    (5, 21, 6, 20, ZodiacSign.gemini),
    (6, 21, 7, 22, ZodiacSign.cancer),
    (7, 23, 8, 22, ZodiacSign.leo),
    (8, 23, 9, 22, ZodiacSign.virgo),
    (9, 23, 10, 22, ZodiacSign.libra),
    (10, 23, 11, 21, ZodiacSign.scorpio),
    (11, 22, 12, 21, ZodiacSign.sagittarius),
    (12, 22, 1, 19, ZodiacSign.capricorn),
    (1, 20, 2, 18, ZodiacSign.aquarius),
    (2, 19, 3, 20, ZodiacSign.pisces),
  ];

  for (final (sm, sd, em, ed, sign) in ranges) {
    final afterStart = m > sm || (m == sm && d >= sd);
    final beforeEnd = m < em || (m == em && d <= ed);
    if (sm <= em) {
      if (afterStart && beforeEnd) return sign;
    } else {
      if (afterStart || beforeEnd) return sign;
    }
  }
  return null;
}

/// Parses an ISO `YYYY-MM-DD` birthday and returns its zodiac sign.
ZodiacSign? zodiacFromIso(String? iso) {
  if (iso == null || iso.isEmpty) return null;
  final date = DateTime.tryParse(iso);
  return date == null ? null : zodiacFromDate(date);
}
