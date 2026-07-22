import { ReactNode, useEffect } from "react";
import {
  FocusContext,
  setFocus,
  useFocusable,
} from "@noriginmedia/norigin-spatial-navigation";
import { registerBackInterceptor } from "../../navigation/backHandler";

/**
 * Focus-trapping overlay. Grabs focus on mount, consumes Back to dismiss
 * (unless `blocking`), and hands focus back to the screen on unmount.
 */
export function Modal({
  children,
  onDismiss,
  blocking = false,
}: {
  children: ReactNode;
  /** Called when Back is pressed. Ignored while `blocking`. */
  onDismiss?: () => void;
  /** Progress modals: Back does not dismiss but is still consumed. */
  blocking?: boolean;
}) {
  const { ref, focusKey, focusSelf } = useFocusable({
    trackChildren: true,
    isFocusBoundary: true,
  });

  useEffect(() => {
    focusSelf();
    return registerBackInterceptor(() => {
      if (!blocking) onDismiss?.();
      return true;
    });
  }, [focusSelf, onDismiss, blocking]);

  return (
    <FocusContext.Provider value={focusKey}>
      <div className="modal-backdrop">
        <div ref={ref} className="modal-panel">
          {children}
        </div>
      </div>
    </FocusContext.Provider>
  );
}

/** Restores focus to a spatial-navigation key. */
export function restoreFocus(focusKey: string): void {
  setFocus(focusKey);
}
