import { describe, expect, it } from "vitest";
import { sanitizeSubtitleText } from "@/player/subtitleText";

describe("sanitizeSubtitleText", () => {
  it("converts <br> variants to newlines", () => {
    expect(sanitizeSubtitleText("İlk satır<br>İkinci satır")).toBe(
      "İlk satır\nİkinci satır",
    );
    expect(sanitizeSubtitleText("a<br/>b<br />c<BR>d")).toBe("a\nb\nc\nd");
  });

  it("strips styling tags but keeps their text", () => {
    expect(sanitizeSubtitleText("<i>italik</i> ve <b>kalın</b>")).toBe(
      "italik ve kalın",
    );
    expect(
      sanitizeSubtitleText('<font color="#ffff00">sarı yazı</font>'),
    ).toBe("sarı yazı");
  });

  it("decodes common entities and trims", () => {
    expect(sanitizeSubtitleText("  Tom &amp; Jerry&nbsp;&quot;bölüm&quot; ")).toBe(
      'Tom & Jerry "bölüm"',
    );
    expect(sanitizeSubtitleText("5 &lt; 6 &gt; 4")).toBe("5 < 6 > 4");
  });

  it("passes plain text through unchanged", () => {
    expect(sanitizeSubtitleText("Normal altyazı satırı")).toBe(
      "Normal altyazı satırı",
    );
  });
});
