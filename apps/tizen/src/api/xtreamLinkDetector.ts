/**
 * Detects Xtream-panel M3U links (`…/get.php?username=X&password=Y…`) and extracts
 * the credentials needed to connect through the Xtream Codes API instead.
 *
 * Many panels disable or block the `get.php` M3U download endpoint while keeping
 * `player_api.php` fully functional, so connecting via the API both sidesteps those
 * blocks and unlocks the richer experience (VOD/series metadata, EPG).
 *
 * Port of the iOS `XtreamLinkDetector` (Networking/XtreamLinkDetector.swift).
 */

export interface XtreamCredentials {
  /** Panel base URL (scheme + host + optional port + optional path prefix before `get.php`). */
  serverURL: string;
  username: string;
  password: string;
}

const GET_PHP_SUFFIX = "/get.php";

interface QueryItem {
  name: string;
  value: string;
}

/**
 * Parses the raw query string ourselves instead of using URLSearchParams:
 * URLSearchParams decodes "+" as a space, while Swift's URLComponents keeps
 * it literal — and credentials may legitimately contain "+".
 */
function parseQueryItems(search: string): QueryItem[] {
  const query = search.charAt(0) === "?" ? search.slice(1) : search;
  if (query === "") return [];
  const items: QueryItem[] = [];
  for (const part of query.split("&")) {
    if (part === "") continue;
    const eq = part.indexOf("=");
    const rawName = eq === -1 ? part : part.slice(0, eq);
    const rawValue = eq === -1 ? "" : part.slice(eq + 1);
    items.push({ name: safeDecode(rawName), value: safeDecode(rawValue) });
  }
  return items;
}

function safeDecode(component: string): string {
  try {
    return decodeURIComponent(component);
  } catch {
    return component;
  }
}

function firstNonEmptyValue(name: string, items: QueryItem[]): string | null {
  for (const item of items) {
    if (item.name.toLowerCase() === name && item.value !== "") {
      return item.value;
    }
  }
  return null;
}

/** Returns credentials when the URL is an Xtream-style `get.php` link, `null` otherwise. */
export function detectXtreamLink(urlString: string): XtreamCredentials | null {
  const trimmed = urlString.trim();

  let url: URL;
  try {
    url = new URL(trimmed);
  } catch {
    return null;
  }

  const scheme = url.protocol.toLowerCase();
  if (scheme !== "http:" && scheme !== "https:") return null;
  if (url.hostname === "") return null;
  if (!url.pathname.toLowerCase().endsWith(GET_PHP_SUFFIX)) return null;

  const items = parseQueryItems(url.search);
  const username = firstNonEmptyValue("username", items);
  const password = firstNonEmptyValue("password", items);
  if (username === null || password === null) return null;

  // Keep any path prefix (e.g. http://host/panel/get.php → http://host/panel).
  const pathPrefix = url.pathname.slice(
    0,
    url.pathname.length - GET_PHP_SUFFIX.length,
  );
  const portSuffix = url.port !== "" ? ":" + url.port : "";
  const serverURL = scheme + "//" + url.hostname + portSuffix + pathPrefix;

  return { serverURL, username, password };
}
