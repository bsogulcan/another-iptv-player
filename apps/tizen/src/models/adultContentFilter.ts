/**
 * Adult-content detection for categories and streams.
 *
 * Port of the iOS `AdultContentFilter` (Models/AdultContentFilter.swift).
 */

/** Minimal structural shape shared by live and VOD streams for adult checks. */
export interface AdultFlaggedStream {
  /** Xtream `is_adult` flag (1 = adult). */
  isAdult?: number | null;
  categoryId?: string | null;
}

/** Minimal structural category shape. */
export interface AdultCheckCategory {
  categoryId?: string | null;
  categoryName?: string | null;
}

// MARK: - Keywords

/**
 * Counted as adult content when it appears as a separate word in the category
 * name. (Case-insensitive, matched as a token surrounded by punctuation/spaces.)
 */
const ADULT_TOKENS = new Set<string>([
  "XXX",
  "ADULT",
  "ADULTS",
  "PORN",
  "PORNO",
  "EROTIC",
  "EROTICA",
  "HENTAI",
  "NUDE",
  "NUDITY",
  "SEX", // token check is enough to avoid false positives like "Essex"
  "NSFW",
  "EXPLICIT",
  "X-RATED",
  "HARDCORE",
  "SOFTCORE",
  "PLAYBOY",
]);

/** Counted as adult content when it appears anywhere in the category name. */
const ADULT_SUBSTRINGS: string[] = [
  "18+",
  "18 +",
  "XVIDEOS",
  "XHAMSTER",
  "PORNHUB",
];

// MARK: - Category Check

/**
 * Returns whether the given category name refers to adult content.
 *
 * Note: Swift splits on `CharacterSet.alphanumerics.inverted` (Unicode-aware).
 * This port treats any character outside ASCII [0-9A-Za-z] as a separator —
 * all adult tokens are ASCII, so matching behavior is equivalent for them.
 */
export function isAdultCategoryName(name: string): boolean {
  const upper = name.toUpperCase();

  // Split on non-alphanumeric characters, drop empty tokens
  const tokens = upper.split(/[^0-9A-Za-z]+/).filter((t) => t !== "");
  for (const token of tokens) {
    if (ADULT_TOKENS.has(token)) return true;
  }

  // Patterns containing special characters (like 18+) are checked as substrings
  for (const substring of ADULT_SUBSTRINGS) {
    if (upper.indexOf(substring) !== -1) return true;
  }
  return false;
}

// MARK: - Stream Checks

/**
 * Returns whether a live stream is adult content.
 * Filtered when the `is_adult: 1` flag is set or its category is an adult category.
 */
export function isAdultLiveStream(
  stream: AdultFlaggedStream,
  adultCategoryIds: Set<string>,
): boolean {
  if ((stream.isAdult ?? 0) === 1) return true;
  if (stream.categoryId != null && adultCategoryIds.has(stream.categoryId)) {
    return true;
  }
  return false;
}

/** Returns whether a movie (VOD) stream is adult content. */
export function isAdultVODStream(
  stream: AdultFlaggedStream,
  adultCategoryIds: Set<string>,
): boolean {
  if ((stream.isAdult ?? 0) === 1) return true;
  if (stream.categoryId != null && adultCategoryIds.has(stream.categoryId)) {
    return true;
  }
  return false;
}

// MARK: - Helpers

/** Extracts the IDs of adult categories from a category list. */
export function adultCategoryIds(
  categories: AdultCheckCategory[],
): Set<string> {
  const ids = new Set<string>();
  for (const cat of categories) {
    if (cat.categoryName == null || !isAdultCategoryName(cat.categoryName)) {
      continue;
    }
    if (cat.categoryId != null) ids.add(cat.categoryId);
  }
  return ids;
}
