// Session memory for per-tab search text, keyed by playlist+tab. Tab switches
// keep queries alive via component state (tabs stay mounted, see TabLayer);
// this map only bridges the dashboard unmounting entirely (exiting to the
// playlist list and re-entering the same playlist).
const memory = new Map<string, string>();

export function getTabQuery(playlistId: string, tabId: string): string {
  return memory.get(`${playlistId}:${tabId}`) ?? "";
}

export function setTabQuery(
  playlistId: string,
  tabId: string,
  value: string,
): void {
  memory.set(`${playlistId}:${tabId}`, value);
}
