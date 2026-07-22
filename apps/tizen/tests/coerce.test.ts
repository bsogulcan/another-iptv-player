/**
 * Coercion matrix for the flexible decode helpers, mirroring the Swift
 * `decodeFlexibleStringIfPresent` / `decodeFlexibleIntIfPresent` semantics
 * (apps/ios/another-iptv-player/Models/XtreamModels.swift).
 */

import { describe, expect, it } from "vitest";
import { asFloat, asInt, asString } from "../src/models/coerce";

describe("asString", () => {
  it("passes strings through untouched (no trimming)", () => {
    expect(asString("hello")).toBe("hello");
    expect(asString("")).toBe("");
    expect(asString("  spaced  ")).toBe("  spaced  ");
    expect(asString("123")).toBe("123");
  });

  it("stringifies integers", () => {
    expect(asString(123)).toBe("123");
    expect(asString(0)).toBe("0");
    expect(asString(-7)).toBe("-7");
  });

  it("stringifies doubles", () => {
    expect(asString(1.5)).toBe("1.5");
    expect(asString(-0.25)).toBe("-0.25");
    // JSON "8.0" parses to the integer 8, matching Swift's Int-first decode.
    expect(asString(JSON.parse("8.0"))).toBe("8");
  });

  it("returns undefined for anything else", () => {
    expect(asString(null)).toBeUndefined();
    expect(asString(undefined)).toBeUndefined();
    expect(asString(true)).toBeUndefined();
    expect(asString(false)).toBeUndefined();
    expect(asString({})).toBeUndefined();
    expect(asString({ value: "x" })).toBeUndefined();
    expect(asString([])).toBeUndefined();
    expect(asString(["1"])).toBeUndefined();
  });
});

describe("asInt", () => {
  it("returns integers as-is", () => {
    expect(asInt(42)).toBe(42);
    expect(asInt(0)).toBe(0);
    expect(asInt(-3)).toBe(-3);
  });

  it("truncates doubles toward zero (Swift Int(Double))", () => {
    expect(asInt(3.9)).toBe(3);
    expect(asInt(-3.9)).toBe(-3);
    expect(asInt(0.5)).toBe(0);
  });

  it("parses strict integer strings (Swift Int(String))", () => {
    expect(asInt("123")).toBe(123);
    expect(asInt("01")).toBe(1);
    expect(asInt("+5")).toBe(5);
    expect(asInt("-8")).toBe(-8);
    expect(asInt("0")).toBe(0);
  });

  it("rejects non-strict strings without falling through to the double branch", () => {
    expect(asInt("123.0")).toBeUndefined();
    expect(asInt(" 1")).toBeUndefined();
    expect(asInt("1 ")).toBeUndefined();
    expect(asInt("")).toBeUndefined();
    expect(asInt("abc")).toBeUndefined();
    expect(asInt("1e3")).toBeUndefined();
    expect(asInt("12abc")).toBeUndefined();
  });

  it("returns undefined for anything else", () => {
    expect(asInt(null)).toBeUndefined();
    expect(asInt(undefined)).toBeUndefined();
    expect(asInt(true)).toBeUndefined();
    expect(asInt(false)).toBeUndefined();
    expect(asInt({})).toBeUndefined();
    expect(asInt([])).toBeUndefined();
    expect(asInt([1])).toBeUndefined();
  });
});

describe("asFloat", () => {
  it("returns numbers as-is (int or double)", () => {
    expect(asFloat(4.5)).toBe(4.5);
    expect(asFloat(7)).toBe(7);
    expect(asFloat(0)).toBe(0);
    expect(asFloat(-2.25)).toBe(-2.25);
  });

  it("rejects numeric strings (strict Double decode)", () => {
    expect(asFloat("4.5")).toBeUndefined();
    expect(asFloat("7")).toBeUndefined();
  });

  it("returns undefined for anything else", () => {
    expect(asFloat(null)).toBeUndefined();
    expect(asFloat(undefined)).toBeUndefined();
    expect(asFloat(true)).toBeUndefined();
    expect(asFloat({})).toBeUndefined();
    expect(asFloat([])).toBeUndefined();
  });
});
