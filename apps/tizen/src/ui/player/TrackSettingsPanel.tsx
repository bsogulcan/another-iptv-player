import { useMemo } from "react";
import {
  FocusContext,
  useFocusable,
} from "@noriginmedia/norigin-spatial-navigation";
import { TrackInfo, TrackType } from "../../player/PlayerPort";
import { t } from "../../i18n";

// Full-screen track chooser (tvOS SettingsPanel style): one column per track
// type. Rendered inside a Modal, so Back/dismissal is handled by the caller.

const TYPE_LABEL_KEYS: { [K in TrackType]: string } = {
  VIDEO: "player.tracks.video",
  AUDIO: "player.tracks.audio",
  TEXT: "player.tracks.subtitle",
};

function TrackButton({
  label,
  detail,
  selected,
  onSelect,
}: {
  label: string;
  detail?: string;
  selected: boolean;
  onSelect: () => void;
}) {
  const { ref, focused } = useFocusable({ onEnterPress: onSelect });
  const classes = ["track-button"];
  if (selected) classes.push("selected");
  if (focused) classes.push("focused");
  return (
    <div ref={ref} className={classes.join(" ")}>
      <span className="track-button-label">{label}</span>
      {detail && <span className="track-button-detail">{detail}</span>}
    </div>
  );
}

/** iOS rule: title → UPPERCASED language code → "Parça N"; the codec /
 * resolution / channel caption comes separately via track.detail. */
function trackLabel(track: TrackInfo, index: number): string {
  if (track.label) return track.label;
  if (track.language) return track.language.toUpperCase();
  return t("tv.track_format", index + 1);
}

export function TrackSettingsPanel({
  tracks,
  selected,
  onSelectTrack,
  onDisableText,
  textDisabled,
}: {
  tracks: TrackInfo[];
  /** Currently selected index per type (-1 = unknown). */
  selected: { [K in TrackType]?: number };
  onSelectTrack: (track: TrackInfo) => void;
  onDisableText: () => void;
  textDisabled: boolean;
}) {
  const { ref, focusKey } = useFocusable({ trackChildren: true });

  const byType = useMemo(() => {
    const groups: { [K in TrackType]: TrackInfo[] } = {
      VIDEO: [],
      AUDIO: [],
      TEXT: [],
    };
    for (const track of tracks) groups[track.type].push(track);
    return groups;
  }, [tracks]);

  return (
    <FocusContext.Provider value={focusKey}>
      <div ref={ref} className="track-panel">
        {(["AUDIO", "TEXT", "VIDEO"] as TrackType[]).map((type) => {
          const group = byType[type];
          if (group.length === 0 && type !== "TEXT") return null;
          return (
            <div key={type} className="track-column">
              <h3>{t(TYPE_LABEL_KEYS[type])}</h3>
              {type === "TEXT" && (
                <TrackButton
                  label={t("player.subtitle_off")}
                  selected={textDisabled}
                  onSelect={onDisableText}
                />
              )}
              {group.map((track, index) => (
                <TrackButton
                  key={`${type}-${track.index}`}
                  label={trackLabel(track, index)}
                  detail={track.detail}
                  selected={!(
                    type === "TEXT" && textDisabled
                  ) && selected[type] === track.index}
                  onSelect={() => onSelectTrack(track)}
                />
              ))}
            </div>
          );
        })}
      </div>
    </FocusContext.Provider>
  );
}
