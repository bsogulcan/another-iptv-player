import { useEffect, useState } from "react";
import { subscribeLanguage } from "./index";

/** Bumps on language change; key the root component with it to re-render. */
export function useLanguageVersion(): number {
  const [version, setVersion] = useState(0);
  useEffect(
    () => subscribeLanguage(() => setVersion((n) => n + 1)),
    [],
  );
  return version;
}
