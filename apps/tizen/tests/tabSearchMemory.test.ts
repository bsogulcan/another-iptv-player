import { describe, expect, it } from "vitest";
import { getTabQuery, setTabQuery } from "@/ui/state/tabSearchMemory";

// Module-level session memory: distinct playlist ids per test keep the
// shared map from leaking state between cases.

describe("tabSearchMemory", () => {
  it("returns an empty string for unknown keys", () => {
    expect(getTabQuery("none", "live")).toBe("");
  });

  it("stores queries per playlist and tab", () => {
    setTabQuery("a", "live", "news");
    setTabQuery("a", "vod", "action");
    setTabQuery("b", "live", "sports");
    expect(getTabQuery("a", "live")).toBe("news");
    expect(getTabQuery("a", "vod")).toBe("action");
    expect(getTabQuery("b", "live")).toBe("sports");
  });

  it("overwrites an existing query", () => {
    setTabQuery("c", "series", "old");
    setTabQuery("c", "series", "new");
    expect(getTabQuery("c", "series")).toBe("new");
  });

  it("keeps an empty string once cleared", () => {
    setTabQuery("d", "browse", "channels");
    setTabQuery("d", "browse", "");
    expect(getTabQuery("d", "browse")).toBe("");
  });
});
