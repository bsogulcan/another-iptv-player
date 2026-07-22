/**
 * AVPlay's onsubtitlechange delivers raw cue payloads: SRT/WebVTT line breaks
 * arrive as literal "<br>" and styling tags (<i>, <font ...>) come through
 * verbatim. Convert breaks to newlines, strip the rest, decode entities.
 */
export function sanitizeSubtitleText(raw: string): string {
  return raw
    .replace(/<br\s*\/?\s*>/gi, "\n")
    .replace(/<[^>]*>/g, "")
    // ASS/SSA override blocks like {\an8} (position) or {\i1} (italics).
    .replace(/\{\\[^}]*\}/g, "")
    .replace(/&amp;/gi, "&")
    .replace(/&lt;/gi, "<")
    .replace(/&gt;/gi, ">")
    .replace(/&nbsp;/gi, " ")
    .replace(/&#39;|&apos;/gi, "'")
    .replace(/&quot;/gi, '"')
    .trim();
}
