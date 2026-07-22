import { KeyboardEvent, useEffect, useRef } from "react";
import { useFocusable } from "@noriginmedia/norigin-spatial-navigation";

/**
 * TV-friendly text input: a real <input> element (so the Tizen IME opens),
 * driven by spatial navigation. Left/Right stay inside the input for caret
 * movement; Up/Down/Enter bubble to spatial navigation / form handling.
 */
export function TextField({
  label,
  value,
  onChange,
  type = "text",
  placeholder,
}: {
  label: string;
  value: string;
  onChange: (value: string) => void;
  type?: "text" | "password" | "url";
  placeholder?: string;
}) {
  const inputRef = useRef<HTMLInputElement>(null);
  const { ref, focused } = useFocusable();

  useEffect(() => {
    if (focused) {
      inputRef.current?.focus();
    } else {
      inputRef.current?.blur();
    }
  }, [focused]);

  const onKeyDown = (event: KeyboardEvent<HTMLInputElement>) => {
    // Keep caret keys local while editing; let Up/Down/Enter/Back bubble so
    // spatial navigation moves between fields.
    if (event.keyCode === 37 || event.keyCode === 39) {
      event.stopPropagation();
    }
  };

  return (
    <label ref={ref} className={`text-field${focused ? " focused" : ""}`}>
      <span className="text-field-label">{label}</span>
      <input
        ref={inputRef}
        type={type}
        value={value}
        placeholder={placeholder}
        onChange={(e) => onChange(e.target.value)}
        onKeyDown={onKeyDown}
        autoComplete="off"
        autoCorrect="off"
        autoCapitalize="off"
        spellCheck={false}
      />
    </label>
  );
}

/** Focusable toggle row (checkbox equivalent). */
export function ToggleField({
  label,
  value,
  onChange,
}: {
  label: string;
  value: boolean;
  onChange: (value: boolean) => void;
}) {
  const { ref, focused } = useFocusable({
    onEnterPress: () => onChange(!value),
  });
  return (
    <div ref={ref} className={`toggle-field${focused ? " focused" : ""}`}>
      <span>{label}</span>
      <span className={`toggle-pill${value ? " on" : ""}`}>
        {value ? "ON" : "OFF"}
      </span>
    </div>
  );
}

/** Focusable action button. */
export function Button({
  label,
  onSelect,
  primary,
}: {
  label: string;
  onSelect: () => void;
  primary?: boolean;
}) {
  const { ref, focused } = useFocusable({ onEnterPress: onSelect });
  const classes = ["button"];
  if (primary) classes.push("primary");
  if (focused) classes.push("focused");
  return (
    <div ref={ref} className={classes.join(" ")}>
      {label}
    </div>
  );
}
