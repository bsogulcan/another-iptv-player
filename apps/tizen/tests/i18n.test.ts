import { readFileSync, readdirSync } from "node:fs";
import { join } from "node:path";
import { fileURLToPath } from "node:url";
import { describe, expect, it } from "vitest";

const localesDir = fileURLToPath(
  new URL("../src/i18n/locales", import.meta.url),
);

function loadCatalog(file: string): Record<string, string> {
  return JSON.parse(readFileSync(join(localesDir, file), "utf8"));
}

describe("locale catalogs", () => {
  const files = readdirSync(localesDir).filter((f) => f.endsWith(".json"));

  it("has all 10 locales", () => {
    expect(files.sort()).toEqual([
      "ar.json",
      "de.json",
      "en.json",
      "es.json",
      "fr.json",
      "hi.json",
      "pt.json",
      "ru.json",
      "tr.json",
      "zh.json",
    ]);
  });

  it("every locale shares the exact en key set", () => {
    const enKeys = Object.keys(loadCatalog("en.json")).sort();
    expect(enKeys.length).toBeGreaterThan(300);
    for (const file of files) {
      const keys = Object.keys(loadCatalog(file)).sort();
      expect(keys, `${file} key set differs from en`).toEqual(enKeys);
    }
  });

  it("placeholders were converted from printf style", () => {
    for (const file of files) {
      const catalog = loadCatalog(file);
      for (const [key, value] of Object.entries(catalog)) {
        expect(value, `${file}:${key} still has printf placeholder`).not.toMatch(
          /%[@di]/,
        );
      }
    }
  });

  it("placeholder indices are consistent with en", () => {
    const en = loadCatalog("en.json");
    const placeholderSet = (value: string) =>
      new Set(Array.from(value.matchAll(/\{(\d+)\}/g), (m) => m[1]));
    for (const file of files) {
      const catalog = loadCatalog(file);
      for (const [key, value] of Object.entries(catalog)) {
        const enSet = placeholderSet(en[key] ?? "");
        expect(
          placeholderSet(value),
          `${file}:${key} placeholder mismatch vs en`,
        ).toEqual(enSet);
      }
    }
  });
});

describe("t()", () => {
  it("falls back en → key and substitutes placeholders", async () => {
    const { t, setLanguage } = await import("@/i18n/index");
    setLanguage("en");
    expect(t("this.key.does.not.exist")).toBe("this.key.does.not.exist");

    const en = loadCatalog("en.json");
    const formatKey = Object.keys(en).find((k) => en[k].includes("{0}"));
    expect(formatKey, "no format key found in en catalog").toBeDefined();
    const rendered = t(formatKey!, 42);
    expect(rendered).toContain("42");
    expect(rendered).not.toContain("{0}");
  });
});
