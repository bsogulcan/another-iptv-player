import { beforeEach, describe, expect, it, vi } from "vitest";
import { PlaylistRecord } from "@/data/records";

// The store only needs getCurrentFocusKey from norigin; mocking it keeps the
// DOM-touching library out of the node test environment.
const mocks = vi.hoisted(() => ({
  getCurrentFocusKey: vi.fn<() => string | null>(() => null),
}));

vi.mock("@noriginmedia/norigin-spatial-navigation", () => ({
  getCurrentFocusKey: mocks.getCurrentFocusKey,
}));

import { topScreen, useNavigation } from "@/navigation/NavigationStack";

const playlist: PlaylistRecord = {
  id: "p1",
  name: "Test",
  type: "xtream",
  serverURL: "http://example.com",
  username: "u",
  password: "p",
  filterAdultContent: false,
  createdAt: 0,
};

beforeEach(() => {
  mocks.getCurrentFocusKey.mockReset();
  mocks.getCurrentFocusKey.mockReturnValue(null);
  useNavigation.setState({
    stack: [{ screen: { name: "playlists" } }],
    pendingFocusRestore: null,
  });
});

describe("navigation stack", () => {
  it("starts with the playlist list as the only screen", () => {
    const { stack } = useNavigation.getState();
    expect(stack).toHaveLength(1);
    expect(topScreen(stack).name).toBe("playlists");
  });

  it("push captures the covered screen's focus key", () => {
    mocks.getCurrentFocusKey.mockReturnValue("row-3");
    useNavigation.getState().push({ name: "dashboard", playlist });
    const { stack } = useNavigation.getState();
    expect(stack).toHaveLength(2);
    expect(stack[0].savedFocus).toBe("row-3");
    expect(stack[1].savedFocus).toBeUndefined();
    expect(topScreen(stack).name).toBe("dashboard");
  });

  it("push without a current focus leaves savedFocus undefined", () => {
    useNavigation.getState().push({ name: "addPlaylist" });
    expect(useNavigation.getState().stack[0].savedFocus).toBeUndefined();
  });

  it("pop exposes the revealed screen's saved focus for restoration", () => {
    mocks.getCurrentFocusKey.mockReturnValue("card-42");
    useNavigation.getState().push({ name: "dashboard", playlist });
    useNavigation.getState().pop();
    const state = useNavigation.getState();
    expect(state.stack).toHaveLength(1);
    expect(state.pendingFocusRestore).toBe("card-42");
    state.consumeFocusRestore();
    expect(useNavigation.getState().pendingFocusRestore).toBeNull();
  });

  it("pop at the root is a no-op", () => {
    useNavigation.getState().pop();
    const { stack } = useNavigation.getState();
    expect(stack).toHaveLength(1);
    expect(topScreen(stack).name).toBe("playlists");
  });

  it("replace swaps the top screen and keeps the rest", () => {
    useNavigation.getState().push({ name: "addPlaylist" });
    useNavigation.getState().replace({ name: "dashboard", playlist });
    const { stack, pendingFocusRestore } = useNavigation.getState();
    expect(stack).toHaveLength(2);
    expect(stack[0].screen.name).toBe("playlists");
    expect(topScreen(stack).name).toBe("dashboard");
    expect(pendingFocusRestore).toBeNull();
  });

  it("reset seeds a multi-screen stack bottom to top", () => {
    // Cold start: playlist list below the auto-opened dashboard, so Back
    // pops to a live list instead of rebuilding it.
    useNavigation
      .getState()
      .reset({ name: "playlists" }, { name: "dashboard", playlist });
    const { stack } = useNavigation.getState();
    expect(stack).toHaveLength(2);
    expect(stack[0].screen.name).toBe("playlists");
    expect(topScreen(stack).name).toBe("dashboard");
    expect(stack.every((entry) => entry.savedFocus === undefined)).toBe(true);
  });

  it("reset clears any pending focus restore", () => {
    mocks.getCurrentFocusKey.mockReturnValue("x");
    useNavigation.getState().push({ name: "addPlaylist" });
    useNavigation.getState().pop();
    expect(useNavigation.getState().pendingFocusRestore).toBe("x");
    useNavigation.getState().reset({ name: "playlists" });
    expect(useNavigation.getState().pendingFocusRestore).toBeNull();
  });
});
