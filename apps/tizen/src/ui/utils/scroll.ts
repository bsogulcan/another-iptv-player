/**
 * Vertically centers an element inside its scrollable ancestor WITHOUT using
 * scrollIntoView: that would also scroll the window itself, which breaks the
 * scaled dev canvas (horizontal document shift) and can nudge the TV viewport.
 *
 * All scroll containers used with this are position: relative, so a child's
 * offsetTop is measured from the container itself. (The old version also
 * subtracted container.offsetTop — wrong once the container is positioned:
 * the target went negative and the list never scrolled.)
 */
export function centerInContainer(
  el: HTMLElement,
  containerSelector: string,
): void {
  const container = el.closest<HTMLElement>(containerSelector);
  if (!container) return;
  const target = el.offsetTop - (container.clientHeight - el.offsetHeight) / 2;
  container.scrollTop = Math.max(target, 0);
}
