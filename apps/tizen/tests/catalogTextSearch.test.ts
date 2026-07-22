import { describe, expect, it } from "vitest";
import {
  equals,
  matches,
  sortLiveByRelevance,
  sortSeriesByRelevance,
  sortVODByRelevance,
  startsWith,
} from "@/models/catalogTextSearch";

// Port of apps/ios/another-iptv-playerTests/CatalogTextSearchTests.swift.
// The Swift helpers build DB record structs; here minimal structural object
// literals carry the same name/sortIndex values.

function makeLiveWithCat(name: string, sortIndex = 0) {
  return { stream: { name, sortIndex }, categoryName: "Cat" };
}

function makeVODWithCat(name: string, sortIndex = 0) {
  return { stream: { name, sortIndex }, categoryName: "Cat" };
}

function makeSeriesWithCat(name: string, sortIndex = 0) {
  return { series: { name, sortIndex }, categoryName: "Cat" };
}

describe("CatalogTextSearch", () => {
  // MARK: - matches

  it("matchesIsCaseInsensitive", () => {
    expect(matches("news", "MORNING NEWS")).toBe(true);
    expect(matches("NEWS", "morning news")).toBe(true);
  });

  it("matchesIsDiacriticInsensitive", () => {
    // "İstanbul" lower-folded with Turkish locale becomes "istanbul"
    expect(matches("istanbul", "İSTANBUL HABER")).toBe(true);
    expect(matches("sehir", "Şehir TV")).toBe(true);
    expect(matches("video", "VİDEO PLUS")).toBe(true);
  });

  it("matchesIgnoresPunctuationAndSpaces", () => {
    // Non-alphanumeric characters are stripped on both sides.
    expect(matches("world news", "World-News HD")).toBe(true);
    expect(matches("fox.tv", "FOX TV")).toBe(true);
  });

  it("matchesAllWordsRequired", () => {
    expect(matches("sports tv", "Sports HD TV")).toBe(true);
    expect(matches("sports zone", "Sports HD TV")).toBe(false);
  });

  it("emptySearchAlwaysMatches", () => {
    expect(matches("", "anything")).toBe(true);
    expect(matches("   ", "anything")).toBe(true);
  });

  it("nonMatchingReturnsFalse", () => {
    expect(matches("sports", "News Channel")).toBe(false);
  });

  // MARK: - equals

  it("equalsIgnoresPunctuationAndDiacritics", () => {
    expect(equals("fox tv", "FOX-TV")).toBe(true);
    expect(equals("istanbul", "İstanbul")).toBe(true);
  });

  it("equalsReturnsFalseForDifferentText", () => {
    expect(equals("abc", "abcd")).toBe(false);
  });

  // MARK: - startsWith

  it("startsWithPrefixMatch", () => {
    expect(startsWith("spo", "Sports HD")).toBe(true);
    expect(startsWith("fox", "FOX TV")).toBe(true);
  });

  it("startsWithDoesNotMatchInfix", () => {
    expect(startsWith("tv", "Sports TV")).toBe(false);
  });

  // MARK: - sortLiveByRelevance

  it("sortLiveEmptySearchRespectsSortIndex", () => {
    const items = [
      makeLiveWithCat("Zeta", 2),
      makeLiveWithCat("Alpha", 0),
      makeLiveWithCat("Beta", 1),
    ];
    const sorted = sortLiveByRelevance(items, "");
    expect(sorted.map((i) => i.stream.name)).toEqual([
      "Alpha",
      "Beta",
      "Zeta",
    ]);
  });

  it("sortLivePrioritizesExactMatch", () => {
    const items = [
      makeLiveWithCat("Sports News"),
      makeLiveWithCat("Sports"),
      makeLiveWithCat("Sports Plus"),
    ];
    const sorted = sortLiveByRelevance(items, "sports");
    expect(sorted[0]?.stream.name).toBe("Sports");
  });

  it("sortLivePrioritizesPrefixOverInfix", () => {
    const items = [
      makeLiveWithCat("Today Sports"),
      makeLiveWithCat("Sports Tonight"),
    ];
    const sorted = sortLiveByRelevance(items, "sports");
    expect(sorted[0]?.stream.name).toBe("Sports Tonight");
  });

  // MARK: - sortVODByRelevance

  it("sortVODPrioritizesExactMatch", () => {
    const items = [
      makeVODWithCat("Echoes of Tomorrow"),
      makeVODWithCat("Echo"),
      makeVODWithCat("Echo Chamber"),
    ];
    const sorted = sortVODByRelevance(items, "echo");
    expect(sorted[0]?.stream.name).toBe("Echo");
  });

  // MARK: - sortSeriesByRelevance

  it("sortSeriesEmptySearchFollowsSortIndex", () => {
    const items = [makeSeriesWithCat("B", 5), makeSeriesWithCat("A", 1)];
    const sorted = sortSeriesByRelevance(items, "");
    expect(sorted.map((i) => i.series.name)).toEqual(["A", "B"]);
  });
});
