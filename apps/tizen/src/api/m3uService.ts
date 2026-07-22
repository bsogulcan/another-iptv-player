import { fetchWithRetry, XtreamApiError } from "./http";

// Remote M3U download with the same encoding fallback chain as the iOS
// M3UService: UTF-8 (strict) → ISO-Latin-1 → UTF-16LE.

export async function downloadM3U(url: string): Promise<string> {
  const response = await fetchWithRetry(url);
  if (!response.ok) {
    throw new XtreamApiError(
      "server",
      `M3U download failed with HTTP ${response.status}`,
      response.status,
    );
  }
  const buffer = await response.arrayBuffer();
  return decodeM3U(buffer);
}

export function decodeM3U(buffer: ArrayBuffer): string {
  try {
    return new TextDecoder("utf-8", { fatal: true }).decode(buffer);
  } catch {
    // fall through
  }
  try {
    return new TextDecoder("iso-8859-1").decode(buffer);
  } catch {
    // fall through
  }
  return new TextDecoder("utf-16le").decode(buffer);
}
