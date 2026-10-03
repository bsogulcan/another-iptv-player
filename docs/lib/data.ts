export const LINKS = {
  github: "https://github.com/bsogulcan/another-iptv-player",
  releases:
    "https://github.com/bsogulcan/another-iptv-player/releases/latest",
  appStore:
    "https://apps.apple.com/us/app/another-iptv-player/id6747290392",
  sponsor: "https://github.com/sponsors/bsogulcan",
  email: "mailto:bsogulcan@gmail.com",
};

/** Real App Store / Mac App Store ratings (update as they change). */
export const RATINGS = {
  appStore: { value: 4.7, count: 36 },
  macStore: { value: 4.8, count: 16 },
};

export const PLATFORMS = ["iOS", "iPadOS", "macOS"];

export type Shot = { src: string; alt: string };

export const SCREENSHOTS: Record<string, Shot[]> = {
  iPhone: [
    { src: "/screenshots/iphone/home-series.png", alt: "Series home on iPhone" },
    { src: "/screenshots/iphone/home-movies.png", alt: "Movies home on iPhone" },
    {
      src: "/screenshots/iphone/home-live-tv.png",
      alt: "Live TV home on iPhone",
    },
    { src: "/screenshots/iphone/series-1.png", alt: "Series detail on iPhone" },
    { src: "/screenshots/iphone/movies-1.png", alt: "Movie detail on iPhone" },
    {
      src: "/screenshots/iphone/player-live-tv-1.png",
      alt: "Live TV player on iPhone",
    },
    {
      src: "/screenshots/iphone/player-movie.png",
      alt: "Movie player on iPhone",
    },
    {
      src: "/screenshots/iphone/player-subtitle-1.png",
      alt: "Subtitle customization on iPhone",
    },
    {
      src: "/screenshots/iphone/player-settings-1.png",
      alt: "Player settings on iPhone",
    },
    { src: "/screenshots/iphone/home-search.png", alt: "Global search on iPhone" },
    {
      src: "/screenshots/iphone/home-settings-1.png",
      alt: "Settings on iPhone",
    },
    {
      src: "/screenshots/iphone/add-playlist-xtream-code.png",
      alt: "Add Xtream Codes playlist on iPhone",
    },
  ],
  iPad: [
    { src: "/screenshots/ipad/serie.png", alt: "Series detail on iPad" },
    { src: "/screenshots/ipad/episode.png", alt: "Episode on iPad" },
    { src: "/screenshots/ipad/movies.png", alt: "Movies on iPad" },
  ],
};

export const DOWNLOADS = [
  { name: "App Store", href: LINKS.appStore, featured: true },
  { name: "macOS", href: LINKS.appStore },
  { name: "GitHub Releases", href: LINKS.releases },
];
