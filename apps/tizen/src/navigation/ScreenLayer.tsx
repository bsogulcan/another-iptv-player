import { createContext, ReactNode, useContext } from "react";
import {
  FocusContext,
  useFocusable,
} from "@noriginmedia/norigin-spatial-navigation";

// Stack screens stay MOUNTED while covered (state, DOM and focus memory
// survive push/pop); only the top layer is displayed and focusable. Hidden
// layers' containers are focusable:false, which keeps their children out of
// spatial-navigation candidate sets entirely.

const ActiveScreenContext = createContext(true);

/** Whether the enclosing navigation layer is the visible top screen. Global
 *  key handlers and back interceptors in screens MUST gate on this. */
export function useScreenActive(): boolean {
  return useContext(ActiveScreenContext);
}

export function ScreenLayer({
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
      <ActiveScreenContext.Provider value={active}>
        <div
          ref={ref}
          className="screen-layer"
          style={{ display: active ? "flex" : "none" }}
        >
          {children}
        </div>
      </ActiveScreenContext.Provider>
    </FocusContext.Provider>
  );
}
