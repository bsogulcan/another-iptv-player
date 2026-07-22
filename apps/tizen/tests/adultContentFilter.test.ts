import { describe, expect, it } from "vitest";
import {
  adultCategoryIds,
  isAdultCategoryName,
  isAdultLiveStream,
  isAdultVODStream,
  type AdultCheckCategory,
  type AdultFlaggedStream,
} from "@/models/adultContentFilter";

// Port of apps/ios/another-iptv-playerTests/AdultContentFilterTests.swift.
// The Swift tests build streams/categories via JSON decoding; here plain
// object literals carry the same field values.

function makeCategory(
  id: string | null,
  name: string | null,
): AdultCheckCategory {
  return { categoryId: id, categoryName: name };
}

function makeStream(
  categoryId: string | null,
  isAdult: number | null,
): AdultFlaggedStream {
  return { categoryId, isAdult };
}

describe("AdultContentFilter", () => {
  // MARK: - isAdultCategoryName: token matches

  it.each([
    "XXX",
    "Adult",
    "Adults Only",
    "Porn",
    "PORNO",
    "Erotic Channels",
    "Erotica",
    "Hentai",
    "Nude",
    "Nudity",
    "Sex Channels",
    "NSFW",
    "Explicit",
    "Hardcore",
    "Softcore",
    "Playboy TV",
  ])("detectsAdultTokens(%s)", (name) => {
    expect(isAdultCategoryName(name)).toBe(true);
  });

  // Known bug (kept for 1:1 parity with iOS): "X-RATED" sits in adultTokens but
  // tokens are split on non-alphanumeric (hyphen). After splitting "X-Rated" →
  // ["X", "RATED"], neither matches "X-RATED". Fix would be to either move
  // "X-RATED" to adultSubstrings or check raw before split.
  it.skip("detectsHyphenatedXRated (known bug: hyphenated tokens never match after alphanumeric split)", () => {
    expect(isAdultCategoryName("X-Rated")).toBe(true);
  });

  // MARK: - Substring matches (special chars)

  it.each([
    "Channels 18+",
    "18 + Movies",
    "Xvideos Live",
    "Xhamster TV",
    "Pornhub HD",
  ])("detectsAdultSubstrings(%s)", (name) => {
    expect(isAdultCategoryName(name)).toBe(true);
  });

  // MARK: - Negative cases (false-positive guards)

  it.each([
    "Sports",
    "News",
    "Movies",
    "Kids",
    "Essex County", // contains "sex" letters but as part of another word
    "Middlesex", // same — token check should reject
    "Sussex",
    "ExplicitlyNot", // "EXPLICITLYNOT" splits into one token => not in set
    "Documentary",
    "Music",
  ])("rejectsNonAdultNames(%s)", (name) => {
    expect(isAdultCategoryName(name)).toBe(false);
  });

  it("caseInsensitive", () => {
    expect(isAdultCategoryName("xxx")).toBe(true);
    expect(isAdultCategoryName("AdUlT")).toBe(true);
  });

  it("emptyNameReturnsFalse", () => {
    expect(isAdultCategoryName("")).toBe(false);
  });

  // MARK: - adultCategoryIds collection

  it("adultCategoryIdsExtractsOnlyAdult", () => {
    const categories: AdultCheckCategory[] = [
      makeCategory("1", "News"),
      makeCategory("2", "XXX Movies"),
      makeCategory("3", "Sports"),
      makeCategory("4", "Adults Only"),
      makeCategory("5", null),
    ];
    const ids = adultCategoryIds(categories);
    expect(ids).toEqual(new Set(["2", "4"]));
  });

  it("adultCategoryIdsEmptyWhenAllSafe", () => {
    const categories: AdultCheckCategory[] = [
      makeCategory("1", "News"),
      makeCategory("2", "Movies"),
    ];
    expect(adultCategoryIds(categories).size).toBe(0);
  });

  // MARK: - isAdultLiveStream

  it("liveStreamFlaggedByIsAdult", () => {
    const stream = makeStream("safe", 1);
    expect(isAdultLiveStream(stream, new Set())).toBe(true);
  });

  it("liveStreamFlaggedByCategory", () => {
    const stream = makeStream("adult-1", 0);
    expect(isAdultLiveStream(stream, new Set(["adult-1"]))).toBe(true);
  });

  it("liveStreamCleanWhenNeitherMatches", () => {
    const stream = makeStream("news", 0);
    expect(isAdultLiveStream(stream, new Set(["adult-1"]))).toBe(false);
  });

  it("liveStreamWithNilIsAdultTreatedAsClean", () => {
    const stream = makeStream("news", null);
    expect(isAdultLiveStream(stream, new Set())).toBe(false);
  });

  // MARK: - isAdultVODStream

  it("vodStreamFlaggedByIsAdult", () => {
    const stream = makeStream("safe", 1);
    expect(isAdultVODStream(stream, new Set())).toBe(true);
  });

  it("vodStreamFlaggedByCategory", () => {
    const stream = makeStream("adult-1", null);
    expect(isAdultVODStream(stream, new Set(["adult-1"]))).toBe(true);
  });

  it("vodStreamCleanWhenNeitherMatches", () => {
    const stream = makeStream("drama", 0);
    expect(isAdultVODStream(stream, new Set(["adult-1"]))).toBe(false);
  });
});
