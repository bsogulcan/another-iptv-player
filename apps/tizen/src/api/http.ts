/**
 * HTTP helpers for the Xtream client, targeting Tizen 4.0 (Chromium M56):
 * no AbortController there, so timeouts are implemented with Promise.race.
 */

export type XtreamErrorKind =
  | "invalid_url"
  | "network"
  | "timeout"
  | "unauthenticated"
  | "decoding"
  | "server";

/** Typed error mirroring the iOS `XtreamError` enum. */
export class XtreamApiError extends Error {
  readonly kind: XtreamErrorKind;
  /** HTTP status code, present for kind === "server". */
  readonly status?: number;

  constructor(kind: XtreamErrorKind, message: string, status?: number) {
    super(message);
    this.name = "XtreamApiError";
    this.kind = kind;
    if (status !== undefined) {
      this.status = status;
    }
  }
}

/**
 * Normalizes a user-entered server URL the same way the iOS client's
 * `getBaseURLComponents` does:
 * - trims surrounding whitespace,
 * - prepends "http://" when no scheme is given,
 * - strips a trailing "/",
 * - appends "/player_api.php" unless the URL already ends with it,
 * - removes any internal spaces.
 */
export function normalizeXtreamBaseURL(serverURL: string): string {
  let base = serverURL.trim();

  const lower = base.toLowerCase();
  if (lower.indexOf("http://") !== 0 && lower.indexOf("https://") !== 0) {
    base = "http://" + base;
  }

  if (base.charAt(base.length - 1) === "/") {
    base = base.slice(0, -1);
  }

  const endsWithApi =
    base.toLowerCase().slice(-"player_api.php".length) === "player_api.php";
  if (!endsWithApi) {
    base += "/player_api.php";
  }

  // Remove spaces inside the URL just in case.
  return base.replace(/ /g, "");
}

export const DEFAULT_TIMEOUT_MS = 15000;

/**
 * On the TV the packaged app is CORS-exempt via config.xml `<access>`, but the
 * desktop dev server is not — cross-origin panel requests are routed through
 * the Vite dev middleware (see devProxy in vite.config.ts). Production builds
 * always hit the target URL directly.
 */
export function transportURL(url: string): string {
  if (import.meta.env.DEV && typeof window !== "undefined") {
    return `/__proxy?url=${encodeURIComponent(url)}`;
  }
  return url;
}

/**
 * `fetch` with a timeout via Promise.race. AbortController does not exist on
 * Chromium 56, so the underlying request is not cancelled — the losing fetch
 * is simply ignored once the timeout rejection wins the race.
 */
export function fetchWithTimeout(
  url: string,
  timeoutMs: number = DEFAULT_TIMEOUT_MS,
): Promise<Response> {
  let timer: ReturnType<typeof setTimeout> | undefined;

  const timeout = new Promise<never>((_, reject) => {
    timer = setTimeout(() => {
      reject(
        new XtreamApiError(
          "timeout",
          `Request timed out after ${timeoutMs} ms: ${url}`,
        ),
      );
    }, timeoutMs);
  });

  const request = fetch(transportURL(url)).then(
    (response) => {
      clearTimeout(timer);
      return response;
    },
    (error: unknown) => {
      clearTimeout(timer);
      throw new XtreamApiError(
        "network",
        `Network error for ${url}: ${describeError(error)}`,
      );
    },
  );

  return Promise.race([request, timeout]);
}

/**
 * `fetchWithTimeout` with exactly one retry, and only on network-level
 * failures (fetch rejection or timeout). HTTP status errors are not raised
 * here at all — a response with any status code resolves and is never
 * retried; callers decide what non-2xx means.
 */
export async function fetchWithRetry(
  url: string,
  timeoutMs: number = DEFAULT_TIMEOUT_MS,
): Promise<Response> {
  try {
    return await fetchWithTimeout(url, timeoutMs);
  } catch {
    return await fetchWithTimeout(url, timeoutMs);
  }
}

function describeError(error: unknown): string {
  if (error instanceof Error) {
    return error.message;
  }
  return String(error);
}
