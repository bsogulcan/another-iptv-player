/**
 * Locale/diacritic-insensitive text search and relevance sorting for catalog
 * items (live streams, VOD, series).
 *
 * Port of the iOS `CatalogTextSearch` (Models/CatalogTextSearch.swift), which
 * mirrors the GRDB `localized_*` SQL functions.
 *
 * Normalization pipeline (same order as Swift):
 *   1. lowercase with the Turkish locale (dotted I becomes "i", ASCII "I"
 *      becomes dotless i),
 *   2. fold diacritics (NFD decomposition + strip combining marks — s-cedilla
 *      becomes "s"),
 *   3. drop punctuation/whitespace, keeping only alphanumeric characters.
 *
 * Chromium 56 notes: no regex lookbehind or \p{} escapes are used. Combining
 * marks are stripped via the U+0300–U+036F block, which covers Latin
 * diacritics. If `toLocaleLowerCase("tr-TR")` ignores its locale argument on
 * old engines, dotted capital I still lowercases to "i" + U+0307, and the
 * mark-stripping step removes the combining dot — so the İ → i mapping holds
 * either way.
 */

const TR_LOCALE = "tr-TR";

/** Combining diacritical marks (produced by NFD decomposition). */
const COMBINING_MARKS = new RegExp("[\\u0300-\\u036f]", "g");

/**
 * Characters treated as non-alphanumeric and removed during normalization.
 * Swift uses Unicode-aware `CharacterSet.alphanumerics.inverted`; without
 * \p{} escapes this port strips ASCII punctuation/controls, Latin-1
 * punctuation/symbols, general punctuation and symbol blocks, and CJK/full-
 * width punctuation. Unicode letters and digits outside these ranges are kept.
 */
const NON_ALPHANUMERIC = new RegExp(
  "[" +
    "\\u0000-\\u002f\\u003a-\\u0040\\u005b-\\u0060\\u007b-\\u00bf" + // ASCII + Latin-1 punctuation/symbols
    "\\u00d7\\u00f7" + // multiplication / division signs
    "\\u2000-\\u2bff" + // general punctuation, arrows, math and misc symbols
    "\\u3000-\\u303f" + // CJK symbols and punctuation
    "\\ufe30-\\ufe4f" + // CJK compatibility forms
    "\\uff01-\\uff0f\\uff1a-\\uff20\\uff3b-\\uff40\\uff5b-\\uff65" + // full-width punctuation
    "]",
  "g",
);

// Search rescans the whole catalog on every committed keystroke, and the
// relevance sort used to re-normalize both operands per comparison — cache
// normalized strings by raw input. Epoch reset over LRU bookkeeping: names
// repeat across keystrokes, so the cache refills in one scan and stays hot.
const NORMALIZE_CACHE_MAX = 50_000;
let normalizeCache = new Map<string, string>();

function normalize(s: string): string {
  const cached = normalizeCache.get(s);
  if (cached !== undefined) return cached;
  const lowercase = s.toLocaleLowerCase(TR_LOCALE);
  const folded = lowercase.normalize("NFD").replace(COMBINING_MARKS, "");
  const result = folded.replace(NON_ALPHANUMERIC, "");
  if (normalizeCache.size >= NORMALIZE_CACHE_MAX) normalizeCache = new Map();
  normalizeCache.set(s, result);
  return result;
}

/**
 * Compiles the query once (lowercase/split/normalize) and returns a predicate
 * for per-item tests — `matches` re-derived the query words for every catalog
 * item, tens of thousands of times per keystroke on big playlists.
 */
export function makeMatcher(search: string): (text: string) => boolean {
  const rawWords = search
    .toLocaleLowerCase(TR_LOCALE)
    .split(/\s+/)
    .filter((w) => w !== "");
  if (rawWords.length === 0) return () => true;
  const words = rawWords.map(normalize);
  // Swift's String.contains("") is false; JS indexOf("") is 0 — match Swift:
  // a query word that normalizes away (e.g. "-") can never match.
  if (words.some((word) => word === "")) return () => false;
  return (text: string): boolean => {
    const normalizedText = normalize(text);
    for (const word of words) {
      if (normalizedText.indexOf(word) === -1) return false;
    }
    return true;
  };
}

export function matches(search: string, text: string): boolean {
  return makeMatcher(search)(text);
}

export function equals(search: string, text: string): boolean {
  return normalize(text) === normalize(search);
}

export function startsWith(search: string, text: string): boolean {
  return normalize(text).indexOf(normalize(search)) === 0;
}

/** Minimal structural shape of a sortable, named catalog entry. */
export interface NamedCatalogItem {
  name: string;
  sortIndex: number;
}

/** Mirrors Swift's `localizedCaseInsensitiveCompare` tie-breaker. */
function caseInsensitiveCompare(n1: string, n2: string): number {
  return n1.localeCompare(n2, undefined, { sensitivity: "accent" });
}

function sortByRelevance<T>(
  items: readonly T[],
  search: string,
  entry: (item: T) => NamedCatalogItem,
): T[] {
  const trimmed = search.trim();
  if (trimmed === "") {
    const sorted = items.slice();
    sorted.sort((a, b) => entry(a).sortIndex - entry(b).sortIndex);
    return sorted;
  }
  // Decorate-sort-undecorate: exact/prefix flags are computed once per item
  // instead of re-deriving them (with their normalizations) inside an
  // O(n log n) comparator.
  const query = normalize(trimmed);
  const decorated = items.map((item) => {
    const name = entry(item).name;
    const normalized = normalize(name);
    return {
      item,
      name,
      exact: normalized === query,
      prefix: normalized.indexOf(query) === 0,
    };
  });
  decorated.sort((a, b) => {
    if (a.exact !== b.exact) return a.exact ? -1 : 1;
    if (a.prefix !== b.prefix) return a.prefix ? -1 : 1;
    return caseInsensitiveCompare(a.name, b.name);
  });
  return decorated.map((d) => d.item);
}

export function sortLiveByRelevance<T extends { stream: NamedCatalogItem }>(
  items: readonly T[],
  search: string,
): T[] {
  return sortByRelevance(items, search, (item) => item.stream);
}

export function sortVODByRelevance<T extends { stream: NamedCatalogItem }>(
  items: readonly T[],
  search: string,
): T[] {
  return sortByRelevance(items, search, (item) => item.stream);
}

export function sortSeriesByRelevance<T extends { series: NamedCatalogItem }>(
  items: readonly T[],
  search: string,
): T[] {
  return sortByRelevance(items, search, (item) => item.series);
}
