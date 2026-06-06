import type { Locale } from "./config";
import en, { type Dictionary } from "./dictionaries/en";
import tr from "./dictionaries/tr";
import de from "./dictionaries/de";
import es from "./dictionaries/es";
import fr from "./dictionaries/fr";
import pt from "./dictionaries/pt";
import ru from "./dictionaries/ru";
import ar from "./dictionaries/ar";
import hi from "./dictionaries/hi";
import zh from "./dictionaries/zh";

const dictionaries: Record<Locale, Dictionary> = {
  en,
  tr,
  de,
  es,
  fr,
  pt,
  ru,
  ar,
  hi,
  zh,
};

export function getDictionary(locale: Locale): Dictionary {
  return dictionaries[locale] ?? en;
}

export type { Dictionary };
