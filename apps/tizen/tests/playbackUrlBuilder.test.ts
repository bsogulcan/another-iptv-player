import { describe, expect, it } from "vitest";
import { PlaybackUrlBuilder } from "@/api/playbackUrlBuilder";

// Port of apps/ios/another-iptv-playerTests/PlaybackURLBuilderTests.swift.
// The Swift builder returns URL? — this port returns plain strings, so
// expectations compare against the same absoluteString values.

function builder(
  serverURL: string,
  username = "user",
  password = "pass",
): PlaybackUrlBuilder {
  return new PlaybackUrlBuilder({ serverURL, username, password });
}

describe("PlaybackURLBuilder", () => {
  // MARK: - liveURL

  it("liveURLBasicFormat", () => {
    const url = builder("http://srv.com").liveUrl(42);
    expect(url).toBe("http://srv.com/user/pass/42");
  });

  it("liveURLAppendsExtension", () => {
    const url = builder("http://srv.com").liveUrl(42, "ts");
    expect(url).toBe("http://srv.com/user/pass/42.ts");
  });

  it("liveURLIgnoresEmptyExtension", () => {
    const url = builder("http://srv.com").liveUrl(42, "");
    expect(url).toBe("http://srv.com/user/pass/42");
  });

  // MARK: - movieURL

  it("movieURLBasicFormat", () => {
    const url = builder("http://srv.com").movieUrl(99, "mkv");
    expect(url).toBe("http://srv.com/movie/user/pass/99.mkv");
  });

  it("movieURLDefaultsToMP4WhenExtensionNil", () => {
    const url = builder("http://srv.com").movieUrl(99, null);
    expect(url).toBe("http://srv.com/movie/user/pass/99.mp4");
  });

  // MARK: - seriesURL

  it("seriesURLBasicFormat", () => {
    const url = builder("http://srv.com").seriesUrl("abc123", "mp4");
    expect(url).toBe("http://srv.com/series/user/pass/abc123.mp4");
  });

  it("seriesURLDefaultsToMP4WhenExtensionNil", () => {
    const url = builder("http://srv.com").seriesUrl("ep1", null);
    expect(url).toBe("http://srv.com/series/user/pass/ep1.mp4");
  });

  // MARK: - Server URL sanitization

  it("prependsHTTPSchemeWhenMissing", () => {
    const url = builder("srv.com").liveUrl(1);
    expect(url).toBe("http://srv.com/user/pass/1");
  });

  it("preservesHTTPSScheme", () => {
    const url = builder("https://srv.com").liveUrl(1);
    expect(url).toBe("https://srv.com/user/pass/1");
  });

  it("stripsTrailingSlash", () => {
    const url = builder("http://srv.com/").liveUrl(1);
    expect(url).toBe("http://srv.com/user/pass/1");
  });

  it("stripsPlayerApiSuffixWithLeadingSlash", () => {
    const url = builder("http://srv.com/player_api.php").liveUrl(1);
    expect(url).toBe("http://srv.com/user/pass/1");
  });

  it("stripsPlayerApiSuffixWithoutLeadingSlash", () => {
    const url = builder("http://srv.com:8080player_api.php").liveUrl(1);
    expect(url).toBe("http://srv.com:8080/user/pass/1");
  });

  it("trimsLeadingAndTrailingWhitespace", () => {
    const url = builder("  http://srv.com  ").liveUrl(1);
    expect(url).toBe("http://srv.com/user/pass/1");
  });

  it("removesInternalSpaces", () => {
    const url = builder("http://srv .com").liveUrl(1);
    expect(url).toBe("http://srv.com/user/pass/1");
  });

  it("includesPortInBase", () => {
    const url = builder("http://srv.com:8080").liveUrl(1);
    expect(url).toBe("http://srv.com:8080/user/pass/1");
  });

  it("trimsCredentialWhitespace", () => {
    const url = builder("http://srv.com", "  u  ", " p ").liveUrl(1);
    expect(url).toBe("http://srv.com/u/p/1");
  });
});
