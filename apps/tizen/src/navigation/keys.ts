import { isTizen } from "../env/platform";

// Samsung TV remote key codes. Arrows/Enter are standard DOM codes handled by
// spatial navigation; the rest arrive only after tizen.tvinputdevice.registerKey.
export const KEY = {
  Enter: 13,
  Escape: 27, // desktop dev only, mapped to Back
  Left: 37,
  Up: 38,
  Right: 39,
  Down: 40,
  Back: 10009,
  MediaPlayPause: 10252,
  MediaPlay: 415,
  MediaPause: 19,
  MediaStop: 413,
  MediaRewind: 412,
  MediaFastForward: 417,
  Red: 403,
  Green: 404,
  Yellow: 405,
  Blue: 406,
  ChannelUp: 427,
  ChannelDown: 428,
} as const;

const REGISTERED_KEY_NAMES = [
  "MediaPlayPause",
  "MediaPlay",
  "MediaPause",
  "MediaStop",
  "MediaRewind",
  "MediaFastForward",
  "ColorF0Red",
  "ColorF1Green",
  "ColorF2Yellow",
  "ColorF3Blue",
  "ChannelUp",
  "ChannelDown",
];

export function registerTVKeys(): void {
  if (!isTizen()) return;
  for (const name of REGISTERED_KEY_NAMES) {
    try {
      window.tizen!.tvinputdevice.registerKey(name);
    } catch (err) {
      console.warn(`[keys] registerKey(${name}) failed`, err);
    }
  }
}

/**
 * Normalizes a keydown to an app key code. Desktop dev mappings:
 * Escape → Back, r → Red, g → Green, y → Yellow, b → Blue, space → PlayPause.
 */
export function normalizeKeyCode(event: KeyboardEvent): number {
  if (isTizen()) return event.keyCode;
  // Don't remap letters while typing in an input field.
  const editing =
    event.target instanceof HTMLElement && event.target.tagName === "INPUT";
  if (event.keyCode === KEY.Escape) return KEY.Back;
  if (!editing) {
    if (event.keyCode === 82) return KEY.Red; // r
    if (event.keyCode === 71) return KEY.Green; // g
    if (event.keyCode === 89) return KEY.Yellow; // y
    if (event.keyCode === 66) return KEY.Blue; // b
    if (event.keyCode === 32) return KEY.MediaPlayPause; // space
    if (event.keyCode === 33) return KEY.ChannelUp; // PageUp
    if (event.keyCode === 34) return KEY.ChannelDown; // PageDown
  }
  return event.keyCode;
}
