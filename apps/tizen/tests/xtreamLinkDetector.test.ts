import { describe, expect, it } from "vitest";
import { detectXtreamLink } from "@/api/xtreamLinkDetector";

// Port of apps/ios/another-iptv-playerTests/XtreamLinkDetectorTests.swift.

describe("XtreamLinkDetector", () => {
  // MARK: - Matches

  it("standardGetPhpLink", () => {
    const creds = detectXtreamLink(
      "http://example.com/get.php?username=user&password=pass&type=m3u_plus&output=ts",
    );
    expect(creds).toEqual({
      serverURL: "http://example.com",
      username: "user",
      password: "pass",
    });
  });

  it("httpsWithPort", () => {
    const creds = detectXtreamLink(
      "https://panel.example.com:8443/get.php?username=u&password=p",
    );
    expect(creds).toEqual({
      serverURL: "https://panel.example.com:8443",
      username: "u",
      password: "p",
    });
  });

  it("pathPrefixIsKept", () => {
    const creds = detectXtreamLink(
      "http://example.com/panel/get.php?username=u&password=p",
    );
    expect(creds?.serverURL).toBe("http://example.com/panel");
  });

  it("surroundingWhitespaceIsTrimmed", () => {
    const creds = detectXtreamLink(
      "  http://example.com/get.php?username=u&password=p \n",
    );
    expect(creds).not.toBeNull();
  });

  it("uppercasePathAndParamNames", () => {
    const creds = detectXtreamLink(
      "http://example.com/GET.PHP?USERNAME=u&PASSWORD=p",
    );
    expect(creds).toEqual({
      serverURL: "http://example.com",
      username: "u",
      password: "p",
    });
  });

  it("percentEncodedCredentialsAreDecoded", () => {
    const creds = detectXtreamLink(
      "http://example.com/get.php?username=a%40b&password=p%26q",
    );
    expect(creds?.username).toBe("a@b");
    expect(creds?.password).toBe("p&q");
  });

  // MARK: - Non-matches

  it("plainM3UURLDoesNotMatch", () => {
    expect(detectXtreamLink("http://example.com/playlist.m3u8")).toBeNull();
  });

  it("missingPasswordDoesNotMatch", () => {
    expect(detectXtreamLink("http://example.com/get.php?username=u")).toBeNull();
  });

  it("emptyCredentialsDoNotMatch", () => {
    expect(
      detectXtreamLink("http://example.com/get.php?username=&password="),
    ).toBeNull();
  });

  it("getPhpAsQueryValueDoesNotMatch", () => {
    expect(
      detectXtreamLink(
        "http://example.com/list.m3u?src=get.php&username=u&password=p",
      ),
    ).toBeNull();
  });

  it("getPhpPrefixedFileDoesNotMatch", () => {
    // endsWith("/get.php") must not match e.g. "forget.php".
    expect(
      detectXtreamLink("http://example.com/forget.php?username=u&password=p"),
    ).toBeNull();
  });

  it("nonHTTPSchemeDoesNotMatch", () => {
    expect(detectXtreamLink("file:///get.php?username=u&password=p")).toBeNull();
    expect(
      detectXtreamLink("rtsp://example.com/get.php?username=u&password=p"),
    ).toBeNull();
  });

  it("garbageDoesNotMatch", () => {
    expect(detectXtreamLink("")).toBeNull();
    expect(detectXtreamLink("not a url")).toBeNull();
  });
});
