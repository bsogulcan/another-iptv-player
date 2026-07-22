import { useEffect, useRef, useState } from "react";
import { useScreenActive } from "../../navigation/ScreenLayer";
import { useTabActive } from "./TabLayer";
import { useCachedImage } from "../../services/imageCache";

// Lazy poster loader for TV memory budgets: the real src is only assigned
// when the element approaches the viewport (IntersectionObserver, Chrome 51+)
// and is released again once it drifts far off-screen. The URL resolves
// through the two-tier image cache (memory + IndexedDB blobs).
//
// Covered layers are the exception: a display:none screen OR hidden tab
// reports "not intersecting" too, but releasing there would rebuild every
// poster on return (looks like a full page reload). While the layer is
// inactive the loaded state is frozen; releases only happen from real
// scrolling.

const observed = new WeakMap<Element, (visible: boolean) => void>();
let sharedObserver: IntersectionObserver | null = null;

function observer(): IntersectionObserver {
  if (!sharedObserver) {
    sharedObserver = new IntersectionObserver(
      (entries) => {
        for (const entry of entries) {
          observed.get(entry.target)?.(entry.isIntersecting);
        }
      },
      { rootMargin: "600px" },
    );
  }
  return sharedObserver;
}

export function PosterImage({
  src,
  alt,
  className,
}: {
  src?: string;
  alt: string;
  className?: string;
}) {
  const ref = useRef<HTMLDivElement>(null);
  const [visible, setVisible] = useState(false);
  const screenActive = useScreenActive();
  const tabActive = useTabActive();
  const layerActive = screenActive && tabActive;
  const layerActiveRef = useRef(layerActive);
  layerActiveRef.current = layerActive;

  useEffect(() => {
    const el = ref.current;
    if (!el) return;
    observed.set(el, (isVisible: boolean) => {
      // Never RELEASE while the layer is covered; becoming visible is
      // always accepted.
      if (!isVisible && !layerActiveRef.current) return;
      setVisible(isVisible);
    });
    observer().observe(el);
    return () => {
      observed.delete(el);
      observer().unobserve(el);
    };
  }, []);

  const resolved = useCachedImage(src, visible);
  // Fade the artwork in once decoded — hard pops read as "instant loading".
  const [loaded, setLoaded] = useState(false);
  const imgRef = useRef<HTMLImageElement>(null);
  const showImage = visible && !!resolved;
  useEffect(() => {
    // Already-cached images can complete before React's onLoad listener sees
    // the event (e.g. remounting after Back) — without this check they would
    // sit at opacity 0 forever.
    const img = imgRef.current;
    setLoaded(!!img && img.complete && img.naturalWidth > 0);
  }, [resolved, showImage]);

  return (
    <div ref={ref} className={`poster-image ${className ?? ""}`}>
      {showImage ? (
        <img
          ref={imgRef}
          src={resolved}
          alt={alt}
          loading="lazy"
          className={loaded ? "loaded" : undefined}
          onLoad={() => setLoaded(true)}
          onError={hideBrokenImage}
        />
      ) : (
        <div className="poster-fallback">{alt.slice(0, 2).toUpperCase()}</div>
      )}
    </div>
  );
}

function hideBrokenImage(event: { currentTarget: HTMLImageElement }): void {
  event.currentTarget.style.visibility = "hidden";
}
