import { useEffect } from "react";
import {
  FocusContext,
  useFocusable,
} from "@noriginmedia/norigin-spatial-navigation";

export interface TabDescriptor {
  id: string;
  label: string;
}

export function tabFocusKey(id: string): string {
  return `dashboard-tab-${id}`;
}

function TabButton({
  tab,
  active,
  onSelect,
}: {
  tab: TabDescriptor;
  active: boolean;
  onSelect: (id: string, source: "focus" | "enter") => void;
}) {
  const { ref, focused } = useFocusable({
    focusKey: tabFocusKey(tab.id),
    onEnterPress: () => onSelect(tab.id, "enter"),
    // Selecting on focus (not just Enter) matches TV dashboard conventions.
    // The source lets the dashboard defer mounting a fresh tab while focus
    // is merely passing through on its way to another one.
    onFocus: () => onSelect(tab.id, "focus"),
  });
  const classes = ["tab-button"];
  if (active) classes.push("active");
  if (focused) classes.push("focused");
  return (
    <div ref={ref} className={classes.join(" ")}>
      {tab.label}
    </div>
  );
}

export function TabBar({
  tabs,
  activeId,
  onSelect,
  focusKey,
  onFocusedChange,
}: {
  tabs: TabDescriptor[];
  activeId: string;
  onSelect: (id: string, source: "focus" | "enter") => void;
  /** Stable key so screens can setFocus() the tab bar (e.g. on Back). */
  focusKey?: string;
  /** Reports whether any tab currently holds focus. */
  onFocusedChange?: (hasFocus: boolean) => void;
}) {
  // preferredChildFocusKey: when the bar (re)gains focus with no remembered
  // child — e.g. the dashboard remounts after popping a pushed screen — land
  // on the ACTIVE tab, not the leftmost one (which would also clobber the
  // persisted selection via select-on-focus).
  const { ref, focusKey: contextKey, hasFocusedChild } = useFocusable({
    trackChildren: true,
    saveLastFocusedChild: true,
    focusKey,
    preferredChildFocusKey: tabFocusKey(activeId),
  });

  useEffect(() => {
    onFocusedChange?.(hasFocusedChild);
  }, [hasFocusedChild, onFocusedChange]);

  return (
    <FocusContext.Provider value={contextKey}>
      <nav ref={ref} className="tab-bar">
        {tabs.map((tab) => (
          <TabButton
            key={tab.id}
            tab={tab}
            active={tab.id === activeId}
            onSelect={onSelect}
          />
        ))}
      </nav>
    </FocusContext.Provider>
  );
}
