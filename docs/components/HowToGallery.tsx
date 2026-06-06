"use client";

import {
  useCallback,
  useEffect,
  useRef,
  useState,
  type PointerEvent as RPointerEvent,
} from "react";
import { AnimatePresence, motion } from "motion/react";

function Arrow({
  dir,
  onClick,
  disabled,
  className = "",
}: {
  dir: "prev" | "next";
  onClick: () => void;
  disabled?: boolean;
  className?: string;
}) {
  return (
    <button
      type="button"
      aria-label={dir === "prev" ? "Previous" : "Next"}
      onClick={(e) => {
        e.stopPropagation();
        onClick();
      }}
      disabled={disabled}
      className={`grid h-10 w-10 shrink-0 place-items-center rounded-full border border-line bg-ink-2/80 text-mist backdrop-blur transition-all hover:border-acid hover:text-acid ${className}`}
    >
      <svg
        viewBox="0 0 24 24"
        className={`h-5 w-5 ${dir === "next" ? "rotate-180" : ""}`}
        fill="none"
        stroke="currentColor"
        strokeWidth={2}
        strokeLinecap="round"
        strokeLinejoin="round"
      >
        <path d="M15 18l-6-6 6-6" />
      </svg>
    </button>
  );
}

/** A screenshot that auto-sizes to its orientation and opens the lightbox on click. */
function Shot({
  src,
  alt,
  onOpen,
}: {
  src: string;
  alt: string;
  onOpen: () => void;
}) {
  const [wide, setWide] = useState(false);
  const imgRef = useRef<HTMLImageElement>(null);

  // onLoad doesn't fire for images already cached/complete at mount — check here.
  useEffect(() => {
    const img = imgRef.current;
    if (img && img.complete && img.naturalWidth > 0) {
      setWide(img.naturalWidth > img.naturalHeight);
    }
  }, []);

  return (
    <button
      type="button"
      onClick={onOpen}
      className={`group relative shrink-0 overflow-hidden rounded-[1.75rem] border border-line bg-ink-3 shadow-[0_18px_44px_-22px_var(--phone-shadow)] transition-all duration-300 hover:-translate-y-1 hover:border-acid/40 ${
        wide
          ? "h-[192px] w-[417px] sm:h-[226px] sm:w-[491px]"
          : "h-[340px] w-[157px] sm:h-[400px] sm:w-[184px]"
      }`}
    >
      {/* eslint-disable-next-line @next/next/no-img-element */}
      <img
        ref={imgRef}
        src={src}
        alt={alt}
        loading="lazy"
        draggable={false}
        onLoad={(e) =>
          setWide(e.currentTarget.naturalWidth > e.currentTarget.naturalHeight)
        }
        className="h-full w-full object-cover"
      />
      <span className="pointer-events-none absolute inset-0 flex items-center justify-center bg-ink/30 opacity-0 transition-opacity duration-300 group-hover:opacity-100">
        <span className="grid h-10 w-10 place-items-center rounded-full bg-acid text-ink">
          <svg
            viewBox="0 0 24 24"
            className="h-4 w-4"
            fill="none"
            stroke="currentColor"
            strokeWidth={2.2}
            strokeLinecap="round"
            strokeLinejoin="round"
          >
            <path d="M15 3h6v6M9 21H3v-6M21 3l-7 7M3 21l7-7" />
          </svg>
        </span>
      </span>
    </button>
  );
}

export function HowToGallery({
  images,
  alt,
}: {
  images: string[];
  alt: string;
}) {
  const trackRef = useRef<HTMLDivElement>(null);
  const [canPrev, setCanPrev] = useState(false);
  const [canNext, setCanNext] = useState(true);
  const [active, setActive] = useState<number | null>(null);

  const update = useCallback(() => {
    const el = trackRef.current;
    if (!el) return;
    setCanPrev(el.scrollLeft > 8);
    setCanNext(el.scrollLeft < el.scrollWidth - el.clientWidth - 8);
  }, []);

  useEffect(() => {
    const id = requestAnimationFrame(update);
    return () => cancelAnimationFrame(id);
  }, [update]);

  const scrollByPage = (dir: 1 | -1) => {
    const el = trackRef.current;
    if (!el) return;
    el.scrollBy({ left: dir * el.clientWidth * 0.8, behavior: "smooth" });
  };

  // Mouse drag-to-scroll with momentum (touch already scrolls natively).
  const drag = useRef({
    active: false,
    startX: 0,
    startScroll: 0,
    moved: false,
    lastX: 0,
    vx: 0,
  });
  const raf = useRef<number | null>(null);

  const cancelMomentum = useCallback(() => {
    if (raf.current !== null) cancelAnimationFrame(raf.current);
    raf.current = null;
  }, []);

  const onPointerDown = (e: RPointerEvent<HTMLDivElement>) => {
    if (e.pointerType !== "mouse") return;
    const el = trackRef.current;
    if (!el) return;
    cancelMomentum();
    drag.current = {
      active: true,
      startX: e.clientX,
      startScroll: el.scrollLeft,
      moved: false,
      lastX: e.clientX,
      vx: 0,
    };
  };

  const onPointerMove = (e: RPointerEvent<HTMLDivElement>) => {
    if (!drag.current.active) return;
    const el = trackRef.current;
    if (!el) return;
    const dx = e.clientX - drag.current.startX;
    if (Math.abs(dx) > 4) drag.current.moved = true;
    drag.current.vx = e.clientX - drag.current.lastX;
    drag.current.lastX = e.clientX;
    el.scrollLeft = drag.current.startScroll - dx;
  };

  const endDrag = () => {
    if (!drag.current.active) return;
    drag.current.active = false;
    const el = trackRef.current;
    let v = drag.current.vx;
    if (!el || Math.abs(v) < 1.5) return;
    const tick = () => {
      v *= 0.92;
      el.scrollLeft -= v;
      raf.current = Math.abs(v) > 0.4 ? requestAnimationFrame(tick) : null;
    };
    raf.current = requestAnimationFrame(tick);
  };

  useEffect(() => cancelMomentum, [cancelMomentum]);

  const openAt = (i: number) => {
    if (drag.current.moved) return; // a drag just ended — don't open the lightbox
    setActive(i);
  };

  const close = useCallback(() => setActive(null), []);
  const step = useCallback(
    (d: number) =>
      setActive((cur) =>
        cur === null ? cur : (cur + d + images.length) % images.length
      ),
    [images.length]
  );

  useEffect(() => {
    if (active === null) return;
    const onKey = (e: KeyboardEvent) => {
      if (e.key === "Escape") close();
      if (e.key === "ArrowRight") step(1);
      if (e.key === "ArrowLeft") step(-1);
    };
    window.addEventListener("keydown", onKey);
    document.body.style.overflow = "hidden";
    return () => {
      window.removeEventListener("keydown", onKey);
      document.body.style.overflow = "";
    };
  }, [active, close, step]);

  return (
    <div className="relative mt-7">
      <div
        ref={trackRef}
        onScroll={update}
        onPointerDown={onPointerDown}
        onPointerMove={onPointerMove}
        onPointerUp={endDrag}
        onPointerLeave={endDrag}
        className="no-scrollbar flex cursor-grab select-none items-center gap-4 overflow-x-auto px-1 pb-12 pt-3 active:cursor-grabbing"
      >
        {images.map((src, i) => (
          <Shot key={src} src={src} alt={alt} onOpen={() => openAt(i)} />
        ))}
        <span className="shrink-0" aria-hidden style={{ width: 1 }} />
      </div>

      <Arrow
        dir="prev"
        onClick={() => scrollByPage(-1)}
        disabled={!canPrev}
        className="absolute left-2 top-1/2 z-10 -translate-y-1/2 disabled:pointer-events-none disabled:opacity-0"
      />
      <Arrow
        dir="next"
        onClick={() => scrollByPage(1)}
        disabled={!canNext}
        className="absolute right-2 top-1/2 z-10 -translate-y-1/2 disabled:pointer-events-none disabled:opacity-0"
      />

      <div
        className={`pointer-events-none absolute inset-y-0 left-0 w-10 bg-gradient-to-r from-ink to-transparent transition-opacity duration-200 ${
          canPrev ? "opacity-100" : "opacity-0"
        }`}
      />
      <div
        className={`pointer-events-none absolute inset-y-0 right-0 w-10 bg-gradient-to-l from-ink to-transparent transition-opacity duration-200 ${
          canNext ? "opacity-100" : "opacity-0"
        }`}
      />

      {/* Lightbox */}
      <AnimatePresence>
        {active !== null && (
          <motion.div
            initial={{ opacity: 0 }}
            animate={{ opacity: 1 }}
            exit={{ opacity: 0 }}
            onClick={close}
            className="fixed inset-0 z-[200] flex flex-col items-center justify-center bg-ink/92 p-4 backdrop-blur-md sm:p-8"
          >
            <button
              type="button"
              aria-label="Close"
              onClick={close}
              className="absolute right-5 top-5 z-10 grid h-10 w-10 place-items-center rounded-full border border-line bg-ink-2 text-mist transition-colors hover:text-snow"
            >
              ✕
            </button>

            <div className="flex w-full max-w-5xl flex-1 items-center justify-center gap-3 sm:gap-6">
              <Arrow dir="prev" onClick={() => step(-1)} />
              <AnimatePresence mode="popLayout">
                <motion.img
                  key={images[active]}
                  initial={{ opacity: 0, scale: 0.96 }}
                  animate={{ opacity: 1, scale: 1 }}
                  exit={{ opacity: 0, scale: 0.96 }}
                  transition={{ duration: 0.25, ease: [0.16, 1, 0.3, 1] }}
                  src={images[active]}
                  alt={alt}
                  className="max-h-[80vh] max-w-[82vw] rounded-2xl border border-line object-contain shadow-2xl"
                />
              </AnimatePresence>
              <Arrow dir="next" onClick={() => step(1)} />
            </div>

            <div
              className="mt-5 flex items-center gap-3"
              onClick={(e) => e.stopPropagation()}
            >
              <span className="font-display text-sm tabular-nums text-fog">
                {String(active + 1).padStart(2, "0")} /{" "}
                {String(images.length).padStart(2, "0")}
              </span>
              <div className="flex gap-1.5">
                {images.map((_, i) => (
                  <button
                    key={i}
                    type="button"
                    aria-label={`Go to image ${i + 1}`}
                    onClick={() => setActive(i)}
                    className={`h-1.5 rounded-full transition-all ${
                      i === active ? "w-6 bg-acid" : "w-1.5 bg-line hover:bg-fog"
                    }`}
                  />
                ))}
              </div>
            </div>
          </motion.div>
        )}
      </AnimatePresence>
    </div>
  );
}
