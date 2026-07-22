// Port of apps/ios/another-iptv-playerTests/M3UParserTests.swift — same case names,
// same inputs, same expected values. Substantial samples live in shared/fixtures/m3u
// (the "@fixtures" Vitest alias points at shared/fixtures); byte-sensitive inputs
// (UTF-8 BOM, \r / \u2028 / \u2029 separators) stay inline as JS strings so editors
// and git cannot normalize them.

import { readFileSync } from "node:fs";
import { join } from "node:path";
import { fileURLToPath } from "node:url";
import { describe, expect, it } from "vitest";

import {
  M3UParser,
  M3UParserError,
  type M3UParseErrorCode,
} from "../src/api/m3uParser";

// node:fs cannot resolve Vite aliases at runtime, so the "@fixtures" directory is
// reached via import.meta.url instead — it resolves to the same shared/fixtures dir.
const FIXTURES_DIR = fileURLToPath(
  new URL("../../../shared/fixtures/m3u", import.meta.url),
);

function fixture(name: string): string {
  return readFileSync(join(FIXTURES_DIR, name), "utf-8");
}

function expectParserError(input: string, code: M3UParseErrorCode): void {
  let caught: unknown = null;
  try {
    M3UParser.parse(input);
  } catch (error) {
    caught = error;
  }
  expect(caught).toBeInstanceOf(M3UParserError);
  expect((caught as M3UParserError).code).toBe(code);
}

describe("M3UParser", () => {
  // MARK: - Errors

  it("emptyStringThrows", () => {
    expectParserError("", "empty");
  });

  it("whitespaceOnlyThrows", () => {
    expectParserError("   \n\t  \n", "empty");
  });

  it("headerWithoutChannelsThrows", () => {
    expectParserError("#EXTM3U\n# just a comment\n", "noChannelsFound");
  });

  // MARK: - Basics

  it("basicSingleChannel", () => {
    const m3u = ["#EXTM3U", "#EXTINF:-1,Channel One", "http://example.com/stream1"].join(
      "\n",
    );
    const result = M3UParser.parse(m3u);
    expect(result.channels.length).toBe(1);
    expect(result.channels[0].name).toBe("Channel One");
    expect(result.channels[0].url).toBe("http://example.com/stream1");
  });

  it("multipleChannels", () => {
    const result = M3UParser.parse(fixture("basic.m3u"));
    expect(result.channels.length).toBe(3);
    expect(result.channels.map((ch) => ch.name)).toEqual(["A", "B", "C"]);
  });

  // MARK: - BOM & newline normalization

  it("stripsUTF8BOM", () => {
    const m3u = "\uFEFF#EXTM3U\n#EXTINF:-1,X\nhttp://x.com\n";
    const result = M3UParser.parse(m3u);
    expect(result.channels.length).toBe(1);
    expect(result.channels[0].name).toBe("X");
  });

  it.each(["\r\n", "\r", "\u2028", "\u2029"])(
    "normalizesNewlines %j",
    (separator) => {
      const m3u = ["#EXTM3U", "#EXTINF:-1,X", "http://x.com"].join(separator);
      const result = M3UParser.parse(m3u);
      expect(result.channels.length).toBe(1);
      expect(result.channels[0].url).toBe("http://x.com");
    },
  );

  // MARK: - EPG URL

  it("extractsEpgURLFromHeader", () => {
    const result = M3UParser.parse(fixture("header-epg-url.m3u"));
    expect(result.epgURL).toBe("https://epg.example.com/epg.xml");
  });

  it("extractsEpgURLFromUrlTvgAlias", () => {
    const m3u = [
      '#EXTM3U url-tvg="https://alt.example.com/guide.xml"',
      "#EXTINF:-1,X",
      "http://x.com",
    ].join("\n");
    const result = M3UParser.parse(m3u);
    expect(result.epgURL).toBe("https://alt.example.com/guide.xml");
  });

  // MARK: - Attributes

  it("parsesAllStandardAttributes", () => {
    const result = M3UParser.parse(fixture("attributes.m3u"));
    const ch = result.channels[0];
    expect(ch).toBeDefined();
    expect(ch.tvgId).toBe("ch.1");
    expect(ch.tvgName).toBe("One");
    expect(ch.tvgLogo).toBe("http://l.com/1.png");
    expect(ch.tvgCountry).toBe("TR");
    expect(ch.groupTitle).toBe("News");
  });

  it("handlesCommasInsideQuotedAttributes", () => {
    const m3u = [
      "#EXTM3U",
      '#EXTINF:-1 tvg-logo="http://cdn.com/img.png?a=1,b=2" group-title="Sports",Channel',
      "http://example.com/1",
    ].join("\n");
    const result = M3UParser.parse(m3u);
    const ch = result.channels[0];
    expect(ch).toBeDefined();
    expect(ch.tvgLogo).toBe("http://cdn.com/img.png?a=1,b=2");
    expect(ch.groupTitle).toBe("Sports");
    expect(ch.name).toBe("Channel");
  });

  it("userAgentInExtinfAttribute", () => {
    const m3u = [
      "#EXTM3U",
      '#EXTINF:-1 user-agent="MyPlayer/1.0",Channel',
      "http://example.com/1",
    ].join("\n");
    const result = M3UParser.parse(m3u);
    expect(result.channels[0].userAgent).toBe("MyPlayer/1.0");
  });

  // MARK: - EXTVLCOPT / KODIPROP

  it("extvlcoptUserAgentAppliesToChannel", () => {
    const result = M3UParser.parse(fixture("vlcopt.m3u"));
    expect(result.channels[0].userAgent).toBe("VLCPlayer/3.0");
  });

  it("kodiPropStreamHeadersUserAgent", () => {
    const result = M3UParser.parse(fixture("kodiprop.m3u"));
    expect(result.channels[0].userAgent).toBe("KodiUA/2.0");
  });

  it("kodiPropAltPrefix", () => {
    const result = M3UParser.parse(fixture("kodiprop-alt.m3u"));
    expect(result.channels[0].userAgent).toBe("AltUA");
  });

  it("extinfUserAgentTakesPrecedenceOverExtvlcopt", () => {
    const m3u = [
      "#EXTM3U",
      '#EXTINF:-1 user-agent="ExtinfUA",Channel',
      "#EXTVLCOPT:http-user-agent=VLCPlayer/3.0",
      "http://example.com/1",
    ].join("\n");
    const result = M3UParser.parse(m3u);
    expect(result.channels[0].userAgent).toBe("ExtinfUA");
  });

  // MARK: - EXTGRP

  it("extgrpOverridesEmptyGroupTitle", () => {
    const result = M3UParser.parse(fixture("extgrp.m3u"));
    expect(result.channels[0].groupTitle).toBe("Movies");
  });

  it("extgrpDoesNotOverwriteAttributeGroupTitle", () => {
    const m3u = [
      "#EXTM3U",
      '#EXTINF:-1 group-title="Sports",Channel',
      "#EXTGRP:Movies",
      "http://example.com/1",
    ].join("\n");
    const result = M3UParser.parse(m3u);
    expect(result.channels[0].groupTitle).toBe("Sports");
  });

  // MARK: - Embedded URL in EXTINF

  it("embeddedHTTPSURLInExtinfLine", () => {
    const m3u = ["#EXTM3U", "#EXTINF:-1,Channelhttps://example.com/stream"].join("\n");
    const result = M3UParser.parse(m3u);
    const ch = result.channels[0];
    expect(ch).toBeDefined();
    expect(ch.name).toBe("Channel");
    expect(ch.url).toBe("https://example.com/stream");
  });

  it("embeddedRTMPURLInExtinfLine", () => {
    const m3u = ["#EXTM3U", "#EXTINF:-1,Channelrtmp://example.com/live"].join("\n");
    const result = M3UParser.parse(m3u);
    expect(result.channels[0].url).toBe("rtmp://example.com/live");
  });

  // MARK: - Name fallback

  it("nameFallbackUsesTvgNameWhenDisplayEmpty", () => {
    const m3u = [
      "#EXTM3U",
      '#EXTINF:-1 tvg-name="From TVG",',
      "http://example.com/file.ts",
    ].join("\n");
    const result = M3UParser.parse(m3u);
    expect(result.channels[0].name).toBe("From TVG");
  });

  it("nameFallbackUsesLastPathComponent", () => {
    const m3u = ["#EXTM3U", "#EXTINF:-1,", "http://example.com/folder/movie.mp4"].join(
      "\n",
    );
    const result = M3UParser.parse(m3u);
    expect(result.channels[0].name).toBe("movie.mp4");
  });

  it("nameFallbackUsesHostWhenPathEmpty", () => {
    const m3u = ["#EXTM3U", "#EXTINF:-1,", "http://example.com"].join("\n");
    const result = M3UParser.parse(m3u);
    expect(result.channels[0].name).toBe("example.com");
  });

  // MARK: - Continuation join (odd-quote)

  it("joinsExtinfContinuationWhenAttributeContainsNewline", () => {
    const result = M3UParser.parse(fixture("continuation.m3u"));
    const ch = result.channels[0];
    expect(ch).toBeDefined();
    expect(ch.url).toBe("http://server/movie.mp4");
    expect(ch.groupTitle).toBe("Movies");
    expect(ch.tvgLogo).toBe("http://l/x.png");
  });

  // MARK: - Diagnostics

  it("diagnosticsCountLines", () => {
    const { diagnostics: diag } = M3UParser.parseWithDiagnostics(
      fixture("diagnostics.m3u"),
    );
    expect(diag.extm3uLines).toBe(1);
    expect(diag.extinfLines).toBe(2);
    expect(diag.uriLines).toBe(2);
    expect(diag.extgrpLines).toBe(1);
    expect(diag.channelCount).toBe(2);
  });

  it("diagnosticsCountsOrphanURI", () => {
    const m3u = [
      "#EXTM3U",
      "http://orphan.com",
      "#EXTINF:-1,Real",
      "http://real.com",
    ].join("\n");
    const { diagnostics: diag } = M3UParser.parseWithDiagnostics(m3u);
    expect(diag.orphanURIs).toBe(1);
    expect(diag.channelCount).toBe(1);
  });

  // MARK: - Async API

  it("asyncParseMatchesSync", async () => {
    const m3u = ["#EXTM3U", "#EXTINF:-1,A", "http://a.com"].join("\n");
    const sync = M3UParser.parse(m3u);
    const asyncResult = await M3UParser.parseAsync(m3u);
    expect(sync).toEqual(asyncResult);
  });

  // MARK: - sanitizedURL

  it("sanitizedURLAcceptsValidURL", () => {
    expect(M3UParser.sanitizedURL("http://example.com/path")).not.toBeNull();
  });

  it("sanitizedURLReturnsNilForEmpty", () => {
    expect(M3UParser.sanitizedURL("")).toBeNull();
    expect(M3UParser.sanitizedURL("   ")).toBeNull();
  });

  it("sanitizedURLEncodesSpaces", () => {
    const url = M3UParser.sanitizedURL("http://example.com/with space");
    expect(url).not.toBeNull();
    expect(url?.includes("%20")).toBe(true);
  });

  it("sanitizedURLTrimsWhitespace", () => {
    expect(M3UParser.sanitizedURL("  http://example.com  ")).toBe(
      "http://example.com",
    );
  });
});
