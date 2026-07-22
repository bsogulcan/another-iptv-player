import { AppDB, bulkPut } from "../data/db";
import {
  CategoryRecord,
  LiveStreamRecord,
  PlaylistRecord,
  SeriesInfoEpisode,
  SeriesRecord,
  VodStreamRecord,
} from "../data/records";
import { savePlaylist } from "../data/playlistRepo";
import { saveSeriesInfo } from "../data/seriesInfoRepo";

// Dev-only demo playlist (iOS MockFixture equivalent): synthesized catalog so
// the dashboard can be exercised in a browser without a real Xtream account.
// Playback URLs are intentionally dead.

export const DEMO_PLAYLIST_ID = "demo-playlist";

const LIVE_CATEGORIES = ["News", "Sports", "Music", "Documentary", "Kids"];
const VOD_CATEGORIES = ["Action", "Comedy", "Drama", "Sci-Fi"];
const SERIES_CATEGORIES = ["Crime", "Fantasy", "Classic"];

export async function seedDemoPlaylist(db: AppDB): Promise<PlaylistRecord> {
  const playlist: PlaylistRecord = {
    id: DEMO_PLAYLIST_ID,
    name: "Demo Playlist",
    type: "xtream",
    serverURL: "http://demo.invalid",
    username: "demo",
    password: "demo",
    filterAdultContent: false,
    createdAt: Date.now(),
  };
  await savePlaylist(db, playlist);

  const categories: CategoryRecord[] = [];
  const live: LiveStreamRecord[] = [];
  const vod: VodStreamRecord[] = [];
  const series: SeriesRecord[] = [];

  LIVE_CATEGORIES.forEach((name, catIndex) => {
    const categoryId = `L${catIndex + 1}`;
    categories.push({
      id: `${DEMO_PLAYLIST_ID}_live_${categoryId}`,
      playlistId: DEMO_PLAYLIST_ID,
      kind: "live",
      categoryId,
      name,
      sortIndex: catIndex,
    });
    for (let i = 0; i < 32; i++) {
      const streamId = 1000 + catIndex * 100 + i;
      live.push({
        id: `${DEMO_PLAYLIST_ID}_${streamId}`,
        playlistId: DEMO_PLAYLIST_ID,
        streamId,
        name: `${name} Channel ${i + 1}`,
        categoryId,
        isAdult: false,
        sortIndex: live.length,
      });
    }
  });

  VOD_CATEGORIES.forEach((name, catIndex) => {
    const categoryId = `V${catIndex + 1}`;
    categories.push({
      id: `${DEMO_PLAYLIST_ID}_vod_${categoryId}`,
      playlistId: DEMO_PLAYLIST_ID,
      kind: "vod",
      categoryId,
      name,
      sortIndex: catIndex,
    });
    for (let i = 0; i < 40; i++) {
      const streamId = 5000 + catIndex * 100 + i;
      vod.push({
        id: `${DEMO_PLAYLIST_ID}_${streamId}`,
        playlistId: DEMO_PLAYLIST_ID,
        streamId,
        name: `${name} Movie ${i + 1}`,
        categoryId,
        rating: `${5 + ((i * 7) % 50) / 10}`,
        containerExtension: "mp4",
        added: `${1700000000 + i * 86400}`,
        isAdult: false,
        sortIndex: vod.length,
      });
    }
  });

  SERIES_CATEGORIES.forEach((name, catIndex) => {
    const categoryId = `S${catIndex + 1}`;
    categories.push({
      id: `${DEMO_PLAYLIST_ID}_series_${categoryId}`,
      playlistId: DEMO_PLAYLIST_ID,
      kind: "series",
      categoryId,
      name,
      sortIndex: catIndex,
    });
    for (let i = 0; i < 18; i++) {
      const seriesId = 9000 + catIndex * 100 + i;
      series.push({
        id: `${DEMO_PLAYLIST_ID}_${seriesId}`,
        playlistId: DEMO_PLAYLIST_ID,
        seriesId,
        name: `${name} Show ${i + 1}`,
        plot: "Demo series for browser development.",
        genre: name,
        rating: "7.5",
        categoryId,
        seasonsLoaded: false,
        sortIndex: series.length,
      });
    }
  });

  await bulkPut(db, "categories", categories);
  await bulkPut(db, "liveStreams", live);
  await bulkPut(db, "vodStreams", vod);
  await bulkPut(db, "series", series);

  // Pre-seeded series info (2 seasons × 8 episodes) so the detail screen and
  // episode queue are testable in the browser without a live panel.
  for (const record of series.slice(0, 6)) {
    const episodes: SeriesInfoEpisode[] = [];
    for (let season = 1; season <= 2; season++) {
      for (let ep = 1; ep <= 8; ep++) {
        episodes.push({
          id: `${record.seriesId}${season}${ep < 10 ? "0" : ""}${ep}`,
          seasonNumber: season,
          episodeNum: ep,
          title: `Episode ${ep}`,
          containerExtension: "mp4",
          plot: "Demo episode.",
        });
      }
    }
    await saveSeriesInfo(db, {
      id: `${DEMO_PLAYLIST_ID}_${record.seriesId}`,
      playlistId: DEMO_PLAYLIST_ID,
      seriesId: record.seriesId,
      seasons: [
        { seasonNumber: 1, episodeCount: 8 },
        { seasonNumber: 2, episodeCount: 8 },
      ],
      episodes,
      fetchedAt: Date.now(),
    });
  }
  return playlist;
}
