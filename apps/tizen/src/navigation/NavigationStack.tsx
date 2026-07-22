import { create } from "zustand";
import { getCurrentFocusKey } from "@noriginmedia/norigin-spatial-navigation";
import { CatalogKind, PlaylistRecord } from "../data/records";
import { PlayableItem } from "../models/playable";

// Array-of-screens navigation (no URL router). Screens below the top stay
// mounted (see ScreenLayer); push records the current focus key so pop can
// return the user to the exact control they left.

export type ScreenDescriptor =
  | { name: "playlists" }
  | { name: "addPlaylist"; editId?: string }
  // Pre-release diagnostics (phase 0/1 TV verification); removed at release.
  | { name: "toolchain" }
  | { name: "spike" }
  | { name: "dashboard"; playlist: PlaylistRecord }
  | {
      name: "categoryGrid";
      playlist: PlaylistRecord;
      kind: CatalogKind | "m3uGroup";
      categoryId: string;
      title: string;
    }
  | { name: "movieDetail"; playlist: PlaylistRecord; vodId: number }
  | { name: "seriesDetail"; playlist: PlaylistRecord; seriesId: number }
  | {
      name: "player";
      playlist: PlaylistRecord;
      items: PlayableItem[];
      startIndex: number;
    };

export interface StackEntry {
  screen: ScreenDescriptor;
  /** Focus key captured when this screen was covered by a push. */
  savedFocus?: string;
}

interface NavigationState {
  stack: StackEntry[];
  /** Focus key to restore after a pop (consumed by App). */
  pendingFocusRestore: string | null;
  push(screen: ScreenDescriptor): void;
  pop(): void;
  replace(screen: ScreenDescriptor): void;
  /** Replace the whole stack, bottom to top (e.g. cold-start seeding
   *  [playlists, dashboard] so Back pops to a live playlist list). */
  reset(...screens: ScreenDescriptor[]): void;
  consumeFocusRestore(): void;
}

export const useNavigation = create<NavigationState>((set) => ({
  stack: [{ screen: { name: "playlists" } }],
  pendingFocusRestore: null,
  push: (screen) =>
    set((s) => {
      const stack = s.stack.slice();
      const top = stack[stack.length - 1];
      stack[stack.length - 1] = {
        ...top,
        savedFocus: getCurrentFocusKey() ?? undefined,
      };
      return { stack: [...stack, { screen }], pendingFocusRestore: null };
    }),
  pop: () =>
    set((s) => {
      if (s.stack.length <= 1) return s;
      const stack = s.stack.slice(0, -1);
      return {
        stack,
        pendingFocusRestore: stack[stack.length - 1].savedFocus ?? null,
      };
    }),
  replace: (screen) =>
    set((s) => ({
      stack: [...s.stack.slice(0, -1), { screen }],
      pendingFocusRestore: null,
    })),
  reset: (...screens) =>
    set({
      stack: screens.map((screen) => ({ screen })),
      pendingFocusRestore: null,
    }),
  consumeFocusRestore: () => set({ pendingFocusRestore: null }),
}));

export function topScreen(stack: StackEntry[]): ScreenDescriptor {
  return stack[stack.length - 1].screen;
}
