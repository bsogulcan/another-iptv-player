import { KeyboardEvent, useEffect, useRef } from "react";
import { useFocusable } from "@noriginmedia/norigin-spatial-navigation";

/**
 * Header search field scoped to the active dashboard tab. TV pattern: moving
 * focus onto the pill never opens the IME (earlier UX feedback — the keyboard
 * must not pop while just passing through); Enter starts editing, Up/Down
 * leave it, IME Done (Enter) closes it.
 */
export function SearchPill({
  value,
  placeholder,
  onChange,
}: {
  value: string;
  placeholder: string;
  onChange: (value: string) => void;
}) {
  const inputRef = useRef<HTMLInputElement>(null);
  const { ref, focused } = useFocusable({
    onEnterPress: () => inputRef.current?.focus(),
  });

  useEffect(() => {
    if (!focused) inputRef.current?.blur();
  }, [focused]);

  const onKeyDown = (event: KeyboardEvent<HTMLInputElement>) => {
    // Only fires while editing (input DOM-focused). Keep caret keys local;
    // Enter = IME Done → stop editing (propagating would re-open the IME).
    if (event.keyCode === 37 || event.keyCode === 39) {
      event.stopPropagation();
    }
    if (event.keyCode === 13) {
      event.stopPropagation();
      inputRef.current?.blur();
    }
  };

  return (
    <div ref={ref} className={`search-pill${focused ? " focused" : ""}`}>
      <span className="search-pill-icon">⌕</span>
      <input
        ref={inputRef}
        type="text"
        value={value}
        placeholder={placeholder}
        onChange={(e) => onChange(e.target.value)}
        onKeyDown={onKeyDown}
        autoComplete="off"
        autoCorrect="off"
        autoCapitalize="off"
        spellCheck={false}
      />
    </div>
  );
}
