// IPTV-focused M3U / M3U8 parser.
//
// 1:1 port of apps/ios/another-iptv-player/Networking/M3UParser.swift.
// Architecture inspired by videojs/m3u8-parser: `classify` turns a line into a typed
// `M3ULine`, the main loop appends channels as a state machine. Targets channel-list
// M3U files, not HLS variant streams.
//
// Supported tags:
// - `#EXTM3U [x-tvg-url="..."]` (also `url-tvg`)
// - `#EXTINF:<duration> [tvg-id="..."] [tvg-name="..."] [tvg-logo="..."] [tvg-country="..."] [group-title="..."] [user-agent="..."],Display Name`
// - `#EXTVLCOPT:http-user-agent=...`
// - `#KODIPROP:inputstream.adaptive.stream_headers="User-Agent=..."` (also `#EXT-X-KODI-PROP:`)
// - `#EXTGRP:GroupName`
//
// Robustness:
// - Strips UTF-8 BOM, normalizes `\r\n` / `\r` / U+2028 / U+2029 newlines.
// - Tolerates commas inside attribute values (tvg-logo URLs) via a quote-aware split.
// - Re-joins newlines that leaked into attribute values (`joinExtinfContinuations`).
// - Splits EXTINF and URL glued on one line (`...,Namehttp://...`).
// - Improves playability with a URL percent-encoding fallback.
//
// Runtime constraints: pure functions, no DOM/Node APIs; regexes avoid lookbehind and
// unicode property escapes so the transpiled output runs on Chromium 56 (Tizen 3/4 TVs).

import type {
  M3UNoGroupSample,
  M3UParseDiagnostics,
  ParsedM3UChannel,
  ParsedM3UPlaylist,
} from "../models/m3u";

export type {
  M3UNoGroupSample,
  M3UParseDiagnostics,
  ParsedM3UChannel,
  ParsedM3UPlaylist,
} from "../models/m3u";

// MARK: - Errors

export type M3UParseErrorCode = "empty" | "noChannelsFound";

export class M3UParserError extends Error {
  readonly code: M3UParseErrorCode;

  constructor(code: M3UParseErrorCode) {
    super(
      code === "empty"
        ? "The M3U content is empty."
        : "No channels were found in the M3U content.",
    );
    this.name = "M3UParserError";
    this.code = code;
    // Keep `instanceof` working after transpilation to older targets.
    Object.setPrototypeOf(this, M3UParserError.prototype);
  }
}

// MARK: - Tag Prefixes

const TAG_EXTM3U = "#EXTM3U";
const TAG_EXTINF = "#EXTINF:";
const TAG_EXTVLCOPT = "#EXTVLCOPT:";
const TAG_KODIPROP = "#KODIPROP:";
const TAG_KODIPROP_ALT = "#EXT-X-KODI-PROP:";
const TAG_EXTGRP = "#EXTGRP:";

// MARK: - Public API

/** Synchronous parse. Prefer `parseM3UAsync` for very large files — this blocks the UI thread. */
export function parseM3U(rawText: string): ParsedM3UPlaylist {
  return parseInternal(rawText).playlist;
}

/** Synchronous parse + diagnostics. */
export function parseM3UWithDiagnostics(rawText: string): {
  playlist: ParsedM3UPlaylist;
  diagnostics: M3UParseDiagnostics;
} {
  return parseInternal(rawText);
}

/** Deferred parse — yields the current task before parsing so UI updates can flush first. */
export function parseM3UAsync(rawText: string): Promise<ParsedM3UPlaylist> {
  return deferred(() => parseM3U(rawText));
}

/** Deferred parse + diagnostics. */
export function parseM3UWithDiagnosticsAsync(rawText: string): Promise<{
  playlist: ParsedM3UPlaylist;
  diagnostics: M3UParseDiagnostics;
}> {
  return deferred(() => parseM3UWithDiagnostics(rawText));
}

function deferred<T>(work: () => T): Promise<T> {
  return new Promise<T>((resolve, reject) => {
    setTimeout(() => {
      try {
        resolve(work());
      } catch (error) {
        reject(error);
      }
    }, 0);
  });
}

// Characters Foundation's URL(string:) accepts: RFC 3986 unreserved + reserved + "%".
// Mirrors Swift's `urlQueryAllowed` unioned with ":/?#[]@!$&'()*+,;=%".
const VALID_URL_STRING = /^[A-Za-z0-9\-._~:\/?#\[\]@!$&'()*+,;=%]+$/;
const VALID_URL_CHAR = /^[A-Za-z0-9\-._~:\/?#\[\]@!$&'()*+,;=%]$/;

/**
 * Sanitizes a URL string. Returns the trimmed string as-is when it is already a valid
 * URL; otherwise percent-encodes unencoded characters (spaces, UTF-8, ...) as a
 * fallback. Returns null when no usable URL can be produced.
 *
 * Port note: the Swift original returns `URL?`; here the sanitized string is returned
 * instead (`url.absoluteString` equivalent).
 */
export function sanitizedURL(raw: string): string | null {
  const trimmed = raw.trim();
  if (trimmed === "") return null;
  if (VALID_URL_STRING.test(trimmed)) return trimmed;
  const encoded = percentEncodeInvalidCharacters(trimmed);
  if (VALID_URL_STRING.test(encoded)) return encoded;
  return null;
}

function percentEncodeInvalidCharacters(s: string): string {
  let out = "";
  // Iterate by code points so surrogate pairs are encoded as full UTF-8 sequences.
  for (const ch of s) {
    out += VALID_URL_CHAR.test(ch) ? ch : encodeURIComponent(ch);
  }
  return out;
}

/** Namespace-style facade mirroring the Swift `enum M3UParser` static API. */
export const M3UParser = {
  parse: parseM3U,
  parseWithDiagnostics: parseM3UWithDiagnostics,
  parseAsync: parseM3UAsync,
  parseWithDiagnosticsAsync: parseM3UWithDiagnosticsAsync,
  sanitizedURL,
};

/** Human-readable diagnostics summary (port of Swift `ParseDiagnostics.debugSummary`). */
export function m3uDiagnosticsSummary(diag: M3UParseDiagnostics): string {
  return [
    "M3U Parse Diagnostics",
    "---",
    `Line count:            ${diag.totalLines}`,
    `#EXTM3U:               ${diag.extm3uLines}`,
    `#EXTINF:               ${diag.extinfLines}`,
    `URI lines:             ${diag.uriLines}`,
    `#EXTVLCOPT:            ${diag.vlcOptLines}`,
    `#KODIPROP:             ${diag.kodiPropLines}`,
    `#EXTGRP:               ${diag.extgrpLines}`,
    `Comment/unknown:       ${diag.commentLines}`,
    `Orphan URIs (skipped): ${diag.orphanURIs}`,
    `Lost pending EXTINF:   ${diag.lostPendingChannels}`,
    "---",
    `Total channels:        ${diag.channelCount}`,
    `Without group-title:   ${diag.noGroupCount}`,
    `Name fallback used:    ${diag.noNameFallbackCount}`,
  ].join("\n");
}

// MARK: - Core

function emptyDiagnostics(): M3UParseDiagnostics {
  return {
    totalLines: 0,
    extm3uLines: 0,
    extinfLines: 0,
    uriLines: 0,
    commentLines: 0,
    vlcOptLines: 0,
    kodiPropLines: 0,
    extgrpLines: 0,
    orphanURIs: 0,
    lostPendingChannels: 0,
    channelCount: 0,
    noGroupCount: 0,
    noNameFallbackCount: 0,
    sampleNoGroup: [],
  };
}

function parseInternal(rawText: string): {
  playlist: ParsedM3UPlaylist;
  diagnostics: M3UParseDiagnostics;
} {
  let text = rawText;
  if (text.charCodeAt(0) === 0xfeff) text = text.slice(1);

  if (text.trim() === "") {
    throw new M3UParserError("empty");
  }

  // Newline normalization: ASCII + Unicode line/paragraph separators.
  const normalized = text
    .replace(/\r\n/g, "\n")
    .replace(/\r/g, "\n")
    .replace(/\u2028/g, "\n")
    .replace(/\u2029/g, "\n");

  // Re-join newlines that leaked into attribute values.
  const logicalLines = joinExtinfContinuations(normalized.split("\n"));

  const state = createParserState();
  const diag = emptyDiagnostics();

  for (const rawLine of logicalLines) {
    const line = rawLine.trim();
    if (line === "") continue;
    diag.totalLines += 1;

    processLine(line, state, diag);
  }

  if (state.channels.length === 0) {
    throw new M3UParserError("noChannelsFound");
  }

  diag.channelCount = state.channels.length;
  diag.noGroupCount = state.channels.filter(
    (ch) => (ch.groupTitle ?? "").trim() === "",
  ).length;

  const playlist: ParsedM3UPlaylist = {
    channels: state.channels,
    epgURL: state.epgURL,
  };
  return { playlist, diagnostics: diag };
}

/** Extracted from the main loop; processes a single line and updates state. */
function processLine(
  line: string,
  state: ParserState,
  diag: M3UParseDiagnostics,
): void {
  const classified = classify(line);
  switch (classified.kind) {
    case "comment":
      diag.commentLines += 1;
      break;

    case "extm3u": {
      diag.extm3uLines += 1;
      state.epgURL =
        classified.attributes["x-tvg-url"] ?? classified.attributes["url-tvg"];
      break;
    }

    case "extinf": {
      diag.extinfLines += 1;
      if (state.pendingChannel !== null) diag.lostPendingChannels += 1;

      const ch = channelFrom(classified.attributes, classified.title);
      if (ch.userAgent === undefined && state.pendingUserAgent !== null) {
        ch.userAgent = state.pendingUserAgent;
      }
      if ((ch.groupTitle ?? "") === "" && state.pendingGroupOverride !== null) {
        ch.groupTitle = state.pendingGroupOverride;
      }

      const embedded = classified.embeddedURL;
      if (embedded !== null && embedded !== "") {
        // EXTINF and URL glued together — append the channel immediately.
        ch.url = embedded;
        const wasEmpty = ch.name.trim() === "";
        applyNameFallback(ch, embedded, state.channels.length);
        if (wasEmpty) diag.noNameFallbackCount += 1;
        collectNoGroupSample(diag, ch, line);
        state.channels.push(ch);
        resetPending(state);
      } else {
        state.pendingChannel = ch;
        state.pendingUserAgent = null;
        state.pendingGroupOverride = null;
        state.pendingRawExtinf = line;
      }
      break;
    }

    case "extvlcopt": {
      diag.vlcOptLines += 1;
      if (classified.key.toLowerCase() === "http-user-agent") {
        assignUserAgent(state, classified.value);
      }
      break;
    }

    case "kodiProp": {
      diag.kodiPropLines += 1;
      if (classified.key.toLowerCase().endsWith("stream_headers")) {
        const ua = parseHeaderString(classified.value, "user-agent");
        if (ua !== null) assignUserAgent(state, ua);
      }
      break;
    }

    case "extgrp": {
      diag.extgrpLines += 1;
      assignGroup(state, classified.group);
      break;
    }

    case "uri": {
      diag.uriLines += 1;
      const ch = state.pendingChannel;
      if (ch === null) {
        diag.orphanURIs += 1;
        return;
      }
      ch.url = classified.url;
      if (ch.userAgent === undefined && state.pendingUserAgent !== null) {
        ch.userAgent = state.pendingUserAgent;
      }
      const wasEmpty = ch.name.trim() === "";
      applyNameFallback(ch, classified.url, state.channels.length);
      if (wasEmpty) diag.noNameFallbackCount += 1;
      collectNoGroupSample(diag, ch, state.pendingRawExtinf ?? "(no pending extinf)");
      state.channels.push(ch);
      resetPending(state);
      break;
    }
  }
}

// MARK: - Parser State

interface ParserState {
  channels: ParsedM3UChannel[];
  epgURL: string | undefined;
  pendingChannel: ParsedM3UChannel | null;
  pendingUserAgent: string | null;
  pendingGroupOverride: string | null;
  pendingRawExtinf: string | null;
}

function createParserState(): ParserState {
  return {
    channels: [],
    epgURL: undefined,
    pendingChannel: null,
    pendingUserAgent: null,
    pendingGroupOverride: null,
    pendingRawExtinf: null,
  };
}

function resetPending(state: ParserState): void {
  state.pendingChannel = null;
  state.pendingUserAgent = null;
  state.pendingGroupOverride = null;
  state.pendingRawExtinf = null;
}

/** For EXTVLCOPT/KODIPROP appearing AFTER an EXTINF: write onto pendingChannel first, otherwise park it. */
function assignUserAgent(state: ParserState, ua: string): void {
  if (state.pendingChannel !== null) {
    if (state.pendingChannel.userAgent === undefined) {
      state.pendingChannel.userAgent = ua;
    }
  } else {
    state.pendingUserAgent = ua;
  }
}

function assignGroup(state: ParserState, group: string): void {
  if (state.pendingChannel !== null) {
    if ((state.pendingChannel.groupTitle ?? "") === "") {
      state.pendingChannel.groupTitle = group;
    }
  } else {
    state.pendingGroupOverride = group;
  }
}

// MARK: - Line Classification

type M3ULine =
  | { kind: "comment" }
  | { kind: "extm3u"; attributes: Record<string, string> }
  | {
      kind: "extinf";
      duration: number | null;
      attributes: Record<string, string>;
      title: string;
      embeddedURL: string | null;
    }
  | { kind: "extvlcopt"; key: string; value: string }
  | { kind: "kodiProp"; key: string; value: string }
  | { kind: "extgrp"; group: string }
  | { kind: "uri"; url: string };

function classify(line: string): M3ULine {
  // URL line: anything not starting with `#` (http, https, rtmp, rtsp, udp, relative path, ...).
  if (!line.startsWith("#")) return { kind: "uri", url: line };

  if (line.startsWith(TAG_EXTM3U)) {
    return { kind: "extm3u", attributes: parseAttributes(line) };
  }
  if (line.startsWith(TAG_EXTINF)) {
    return parseExtinf(line);
  }
  if (line.startsWith(TAG_EXTVLCOPT)) {
    const kv = splitKeyValue(line.slice(TAG_EXTVLCOPT.length));
    return { kind: "extvlcopt", key: kv.key, value: kv.value };
  }
  if (line.startsWith(TAG_KODIPROP)) {
    const kv = splitKeyValue(line.slice(TAG_KODIPROP.length));
    return { kind: "kodiProp", key: kv.key, value: kv.value };
  }
  if (line.startsWith(TAG_KODIPROP_ALT)) {
    const kv = splitKeyValue(line.slice(TAG_KODIPROP_ALT.length));
    return { kind: "kodiProp", key: kv.key, value: kv.value };
  }
  if (line.startsWith(TAG_EXTGRP)) {
    const group = line.slice(TAG_EXTGRP.length).trim();
    return { kind: "extgrp", group };
  }
  return { kind: "comment" };
}

const EMBEDDED_URL_REGEX = /https?:\/\/|rtmps?:\/\/|rtsps?:\/\//;

function parseExtinf(line: string): M3ULine {
  // `#EXTINF:<duration>[ attrs],<Display Name>`
  // Commas can also appear inside attribute values (tvg-logo URLs) — split quote-aware.
  const body = line.slice(TAG_EXTINF.length);
  const { header, name: rawTitle } = splitHeaderAndName(body);

  const duration = parseDuration(header);
  const attrs = parseAttributes(header);

  // In broken M3U files the title and URL can be glued onto the same line.
  let title = rawTitle;
  let embedded: string | null = null;
  const match = EMBEDDED_URL_REGEX.exec(rawTitle);
  if (match !== null) {
    title = rawTitle.slice(0, match.index).trim();
    embedded = rawTitle.slice(match.index).trim();
  }

  return { kind: "extinf", duration, attributes: attrs, title, embeddedURL: embedded };
}

/** First space-separated token of the header parsed as a number (Swift: `Double(first)`). */
function parseDuration(header: string): number | null {
  let start = 0;
  while (start < header.length && header[start] === " ") start += 1;
  const rest = header.slice(start);
  const space = rest.indexOf(" ");
  const first = space === -1 ? rest : rest.slice(0, space);
  if (first === "") return null;
  const value = Number(first);
  return Number.isNaN(value) ? null : value;
}

// MARK: - Continuation Join

/**
 * If an EXTINF line has an unbalanced quote (a real newline leaked into an attribute
 * value), joins the following physical lines until the quotes balance out.
 *
 *     #EXTINF:-1 tvg-name="NL - Venom - 2018
 *     " tvg-logo="..." group-title="...",NL - Venom - 2018
 *     http://server/movie.mp4
 *
 * The first two lines are logically a single EXTINF. Joining stops when a new
 * `#EXTINF:` is seen.
 */
function joinExtinfContinuations(lines: string[]): string[] {
  const result: string[] = [];
  let i = 0;
  const n = lines.length;
  while (i < n) {
    const raw = lines[i];
    const trimmed = raw.trim();
    if (!(trimmed.startsWith(TAG_EXTINF) && hasOddQuoteCount(trimmed))) {
      result.push(raw);
      i += 1;
      continue;
    }
    let buffer = raw;
    let j = i + 1;
    const limit = Math.min(n, i + 10); // safety cap — at most 10 physical lines per EXTINF
    while (j < limit) {
      const nextTrimmed = lines[j].trim();
      if (nextTrimmed.startsWith(TAG_EXTINF)) break; // new entry — stop joining
      buffer += lines[j];
      j += 1;
      if (!hasOddQuoteCount(buffer)) break;
    }
    result.push(buffer);
    i = j;
  }
  return result;
}

function hasOddQuoteCount(s: string): boolean {
  let count = 0;
  for (let i = 0; i < s.length; i++) {
    if (s[i] === '"') count += 1;
  }
  return count % 2 === 1;
}

// MARK: - Attribute Parsing

/**
 * `key="value"` (quoted) OR `key=value` (unquoted, up to whitespace/comma).
 * Extended from videojs' attribute pattern: supports both HLS (comma-separated) and
 * IPTV (space-separated) styles. No lookbehind — must run on Chromium 56.
 */
function parseAttributes(text: string): Record<string, string> {
  const regex = /([^=\s,"]+)=(?:"([^"]*)"|([^\s,"]+))/g;
  const out: Record<string, string> = {};
  let match: RegExpExecArray | null;
  while ((match = regex.exec(text)) !== null) {
    const key = match[1].toLowerCase();
    let value: string;
    if (match[2] !== undefined) {
      value = match[2];
    } else if (match[3] !== undefined) {
      value = match[3];
    } else {
      value = "";
    }
    out[key] = value;
  }
  return out;
}

/** Splits `body` at the first comma outside quotes. Header (attributes) + Name (display). */
function splitHeaderAndName(body: string): { header: string; name: string } {
  let inQuotes = false;
  let splitIndex = -1;
  for (let i = 0; i < body.length; i++) {
    const c = body[i];
    if (c === '"') {
      inQuotes = !inQuotes;
    } else if (c === "," && !inQuotes) {
      splitIndex = i;
      break;
    }
  }
  if (splitIndex === -1) {
    return { header: body, name: "" };
  }
  return {
    header: body.slice(0, splitIndex),
    name: body.slice(splitIndex + 1).trim(),
  };
}

/** `foo=bar` → ("foo", "bar"). Without `=`: key = trimmed text, empty value. Strips surrounding quotes from the value. */
function splitKeyValue(s: string): { key: string; value: string } {
  const eq = s.indexOf("=");
  if (eq === -1) {
    return { key: s.trim(), value: "" };
  }
  const key = s.slice(0, eq).trim();
  let value = s.slice(eq + 1).trim();
  if (value.length >= 2 && value.startsWith('"') && value.endsWith('"')) {
    value = value.slice(1, -1);
  }
  return { key, value };
}

/**
 * KODIPROP stream_headers formats: `User-Agent=Foo&Referer=Bar` or `User-Agent: Foo\nReferer: Bar`.
 * Looks up the given key; decodes URL-encoding when present.
 */
function parseHeaderString(raw: string, keyed: string): string | null {
  const lowerKey = keyed.toLowerCase();
  const normalized = raw.replace(/\r\n/g, "\n");
  const parts = normalized.split(/[&\n]/).filter((p) => p !== "");
  for (const part of parts) {
    const eqValue = matchPair(part, "=", lowerKey);
    if (eqValue !== null) {
      return removePercentEncoding(eqValue);
    }
    const colonValue = matchPair(part, ":", lowerKey);
    if (colonValue !== null) {
      return colonValue.trim();
    }
  }
  return null;
}

function matchPair(part: string, separator: string, key: string): string | null {
  const idx = part.indexOf(separator);
  if (idx === -1) return null;
  const before = part.slice(0, idx);
  const after = part.slice(idx + 1);
  // Swift's split(maxSplits:1) omits empty subsequences — require both pieces non-empty.
  if (before === "" || after === "") return null;
  if (before.trim().toLowerCase() !== key) return null;
  return after;
}

function removePercentEncoding(s: string): string {
  try {
    return decodeURIComponent(s);
  } catch {
    // Swift: `removingPercentEncoding ?? v` — fall back to the raw value on malformed input.
    return s;
  }
}

// MARK: - Channel Assembly

function channelFrom(attrs: Record<string, string>, title: string): ParsedM3UChannel {
  return {
    name: title,
    url: "",
    tvgId: attrs["tvg-id"],
    tvgName: attrs["tvg-name"],
    tvgLogo: attrs["tvg-logo"],
    tvgCountry: attrs["tvg-country"],
    groupTitle: attrs["group-title"],
    userAgent: attrs["user-agent"],
  };
}

/** Name fallback chain: display-name → tvg-name → URL last path component → host → "Kanal N". */
function applyNameFallback(
  channel: ParsedM3UChannel,
  urlString: string,
  channelsCount: number,
): void {
  if (channel.name.trim() !== "") return;
  const tvg = channel.tvgName?.trim();
  if (tvg !== undefined && tvg !== "") {
    channel.name = tvg;
    return;
  }
  const sanitized = sanitizedURL(urlString);
  if (sanitized !== null) {
    const parts = extractURLParts(sanitized);
    if (parts.lastPathComponent !== "" && parts.lastPathComponent !== "/") {
      channel.name = parts.lastPathComponent;
      return;
    }
    if (parts.host !== null && parts.host !== "") {
      channel.name = parts.host;
      return;
    }
  }
  channel.name = `Kanal ${channelsCount + 1}`;
}

function collectNoGroupSample(
  diag: M3UParseDiagnostics,
  channel: ParsedM3UChannel,
  rawExtinf: string,
): void {
  if (diag.sampleNoGroup.length >= 20) return;
  const hasGroup = (channel.groupTitle ?? "").trim() !== "";
  if (hasGroup) return;
  const sample: M3UNoGroupSample = {
    rawExtinf,
    name: channel.name,
    url: channel.url,
  };
  diag.sampleNoGroup.push(sample);
}

// MARK: - URL Component Extraction

// Manual URL splitting instead of WHATWG `new URL(...)`: Chromium 56 mishandles
// non-special schemes (rtmp/rtsp), and Foundation's `URL.path` for "http://host"
// is "" while WHATWG normalizes it to "/". This mirrors Foundation's behavior.
function extractURLParts(urlString: string): {
  lastPathComponent: string;
  host: string | null;
} {
  const schemeMatch = /^[A-Za-z][A-Za-z0-9+.\-]*:\/\//.exec(urlString);
  if (schemeMatch !== null) {
    const rest = urlString.slice(schemeMatch[0].length);
    const authorityEnd = findFirstOf(rest, "/?#");
    const authority = authorityEnd === -1 ? rest : rest.slice(0, authorityEnd);
    let path = "";
    if (authorityEnd !== -1 && rest[authorityEnd] === "/") {
      const afterAuthority = rest.slice(authorityEnd);
      const queryStart = findFirstOf(afterAuthority, "?#");
      path = queryStart === -1 ? afterAuthority : afterAuthority.slice(0, queryStart);
    }
    return { lastPathComponent: lastComponentOfPath(path), host: hostOfAuthority(authority) };
  }
  // No scheme — treat as a relative URL (host is nil in Foundation as well).
  const queryStart = findFirstOf(urlString, "?#");
  const path = queryStart === -1 ? urlString : urlString.slice(0, queryStart);
  return { lastPathComponent: lastComponentOfPath(path), host: null };
}

function hostOfAuthority(authority: string): string | null {
  const at = authority.lastIndexOf("@");
  let host = at >= 0 ? authority.slice(at + 1) : authority;
  if (host.startsWith("[")) {
    // IPv6 literal — keep brackets, drop any port after "]".
    const close = host.indexOf("]");
    if (close >= 0) host = host.slice(0, close + 1);
  } else {
    const colon = host.indexOf(":");
    if (colon >= 0) host = host.slice(0, colon);
  }
  return host !== "" ? host : null;
}

/** Foundation-like `lastPathComponent`: "" for empty path, "/" for root, trailing slashes ignored. */
function lastComponentOfPath(path: string): string {
  if (path === "") return "";
  if (path === "/") return "/";
  let end = path.length;
  while (end > 0 && path[end - 1] === "/") end -= 1;
  if (end === 0) return "/";
  const start = path.lastIndexOf("/", end - 1) + 1;
  const component = path.slice(start, end);
  // Foundation's `path` is percent-decoded; decode when well-formed.
  try {
    return decodeURIComponent(component);
  } catch {
    return component;
  }
}

function findFirstOf(s: string, chars: string): number {
  for (let i = 0; i < s.length; i++) {
    if (chars.indexOf(s[i]) !== -1) return i;
  }
  return -1;
}
