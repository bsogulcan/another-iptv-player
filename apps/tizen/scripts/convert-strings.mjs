// Converts the iOS Localizable.strings catalogs into JSON dictionaries for the
// Tizen app. printf-style placeholders (%@, %d, %1$@, ...) become {0}, {1}, ...
// Usage: node scripts/convert-strings.mjs
import { readdirSync, readFileSync, mkdirSync, writeFileSync } from "node:fs";
import { dirname, join, resolve } from "node:path";
import { fileURLToPath } from "node:url";

const here = dirname(fileURLToPath(import.meta.url));
const iosLocalizationDir = resolve(
  here,
  "../../ios/another-iptv-player/Localization",
);
const outDir = resolve(here, "../src/i18n/locales");

function unescapeStringsValue(raw) {
  return raw
    .replace(/\\n/g, "\n")
    .replace(/\\t/g, "\t")
    .replace(/\\"/g, '"')
    .replace(/\\\\/g, "\\");
}

function convertPlaceholders(value) {
  let auto = 0;
  // %% is a literal percent; %1$@ is positional; %@ %d %i %ld %lld %.1f are sequential.
  return value.replace(
    /%%|%(\d+)\$[@a-zA-Z]|%[.0-9]*[@dioufgxXeEsc]|%l{1,2}[diu]/g,
    (match, positional) => {
      if (match === "%%") return "%";
      if (positional !== undefined) return `{${Number(positional) - 1}}`;
      return `{${auto++}}`;
    },
  );
}

function parseStringsFile(path) {
  const content = readFileSync(path, "utf8").replace(/^﻿/, "");
  const entries = {};
  const lineRe = /"((?:[^"\\]|\\.)*)"\s*=\s*"((?:[^"\\]|\\.)*)"\s*;/g;
  let match;
  while ((match = lineRe.exec(content)) !== null) {
    const key = unescapeStringsValue(match[1]);
    entries[key] = convertPlaceholders(unescapeStringsValue(match[2]));
  }
  return entries;
}

const locales = readdirSync(iosLocalizationDir)
  .filter((name) => name.endsWith(".lproj"))
  .map((name) => name.replace(".lproj", ""));

if (locales.length === 0) {
  console.error(`No .lproj directories found in ${iosLocalizationDir}`);
  process.exit(1);
}

mkdirSync(outDir, { recursive: true });

const catalogs = {};
for (const locale of locales) {
  const stringsPath = join(
    iosLocalizationDir,
    `${locale}.lproj`,
    "Localizable.strings",
  );
  catalogs[locale] = parseStringsFile(stringsPath);
  const outPath = join(outDir, `${locale}.json`);
  writeFileSync(outPath, `${JSON.stringify(catalogs[locale], null, 2)}\n`);
  console.log(`${locale}: ${Object.keys(catalogs[locale]).length} keys → ${outPath}`);
}

// Warn about locales missing keys that exist in English.
const enKeys = new Set(Object.keys(catalogs.en ?? {}));
for (const locale of locales) {
  if (locale === "en") continue;
  const missing = [...enKeys].filter((k) => !(k in catalogs[locale]));
  if (missing.length > 0) {
    console.warn(`WARN ${locale}: ${missing.length} keys missing vs en:`);
    for (const key of missing.slice(0, 10)) console.warn(`  - ${key}`);
  }
}
