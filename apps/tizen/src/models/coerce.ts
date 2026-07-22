/**
 * Type-coercion helpers mirroring the iOS decoders in
 * apps/ios/another-iptv-player/Models/XtreamModels.swift
 * (`decodeFlexibleStringIfPresent` / `decodeFlexibleIntIfPresent`).
 *
 * Xtream panels are wildly inconsistent about JSON value types: the same
 * field may arrive as a string, an int, or a double depending on the panel.
 * These helpers accept `unknown` (raw JSON.parse output) and normalize.
 */

/** Matches Swift's `Int(String)`: optional sign, digits only, no spaces, no decimals. */
const STRICT_INT_RE = /^[+-]?[0-9]+$/;

/**
 * string | int | double -> string, anything else -> undefined.
 *
 * Mirrors `decodeFlexibleStringIfPresent`: strings pass through untouched
 * (no trimming), numbers are stringified. Integral numbers stringify without
 * a fractional part ("8", not "8.0") because Swift's JSONDecoder decodes
 * `8.0` as Int 8 before the Double branch is reached.
 */
export function asString(value: unknown): string | undefined {
  if (typeof value === "string") {
    return value;
  }
  if (typeof value === "number" && isFinite(value)) {
    return String(value);
  }
  return undefined;
}

/**
 * int | numeric-string | double -> int, anything else -> undefined.
 *
 * Mirrors `decodeFlexibleIntIfPresent`:
 * - integral numbers are returned as-is;
 * - non-integral numbers are truncated toward zero (Swift `Int(Double)`);
 * - strings are parsed with Swift `Int(String)` strictness: `"01"` -> 1,
 *   `"+5"` -> 5, but `"123.0"`, `" 1"`, `""`, `"1e3"` -> undefined. A string
 *   that fails to parse returns undefined immediately (no double fallback),
 *   exactly like the Swift `return Int(stringValue)` branch.
 */
export function asInt(value: unknown): number | undefined {
  if (typeof value === "number" && isFinite(value)) {
    return Math.trunc(value);
  }
  if (typeof value === "string") {
    if (!STRICT_INT_RE.test(value)) {
      return undefined;
    }
    return parseInt(value, 10);
  }
  return undefined;
}

/**
 * double | int -> number, anything else -> undefined.
 *
 * Mirrors the strict `try? decodeIfPresent(Double.self, ...)` used for
 * `rating_5based` / `vote_average`: numeric strings are NOT accepted.
 */
export function asFloat(value: unknown): number | undefined {
  if (typeof value === "number" && isFinite(value)) {
    return value;
  }
  return undefined;
}
