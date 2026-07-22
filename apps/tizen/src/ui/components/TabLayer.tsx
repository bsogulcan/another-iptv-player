import { createContext, ReactNode, useContext } from "react";
import {
  FocusContext,
  useFocusable,
} from "@noriginmedia/norigin-spatial-navigation";

// ScreenLayer's pattern one level down: visited dashboard tabs stay MOUNTED
// while hidden (scroll, reveal and focus memory survive tab switches); only
// the active tab is displayed and focusable. Hidden layers' containers are
// focusable:false, which keeps their children out of spatial-navigation
// candidate sets entirely.

const ActiveTabContext = createContext(true);

/** Whether the enclosing tab layer is the visible tab. Defaults to true so
 *  components used outside a TabLayer behave as always-active. Global key
 *  handlers in tab content MUST gate on this (in addition to screen-active). */
export function useTabActive(): boolean {
  return useContext(ActiveTabContext);
}

export function TabLayer({
  active,
  children,
}: {
  active: boolean;
  children: ReactNode;
}) {
  const { ref, focusKey } = useFocusable({
    trackChildren: true,
    saveLastFocusedChild: true,
    focusable: active,
  });

  return (
    <FocusContext.Provider value={focusKey}>
      <ActiveTabContext.Provider value={active}>
        <div
          ref={ref}
          className="tab-layer"
          style={{ display: active ? "flex" : "none" }}
        >
          {children}
        </div>
      </ActiveTabContext.Provider>
    </FocusContext.Provider>
  );
}
