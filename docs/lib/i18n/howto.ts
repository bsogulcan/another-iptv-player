import { defaultLocale, type Locale } from "./config";

export type HowToStep = {
  title: string;
  body: string;
  images: string[];
};

export type HowTo = {
  metaTitle: string;
  metaDescription: string;
  eyebrow: string;
  title: string;
  intro: string;
  steps: HowToStep[];
};

const IMG = "/screenshots/iphone";

/** Every iPhone screenshot, grouped by step (shared across locales). */
const stepImages: string[][] = [
  [
    `${IMG}/playlist-screen.png`,
    `${IMG}/add-playlist-1.png`,
    `${IMG}/add-playlist-xtream-code.png`,
    `${IMG}/add-playlist-m3u.png`,
  ],
  [
    `${IMG}/home-live-tv.png`,
    `${IMG}/home-movies.png`,
    `${IMG}/home-series.png`,
    `${IMG}/home-search.png`,
    `${IMG}/series-1.png`,
    `${IMG}/series-2.png`,
    `${IMG}/movies-1.png`,
  ],
  [
    `${IMG}/player-movie.png`,
    `${IMG}/player-live-tv-1.png`,
    `${IMG}/player-live-tv-2.png`,
    `${IMG}/player-settings-1.png`,
  ],
  [
    `${IMG}/player-subtitle-1.png`,
    `${IMG}/player-subtitle-2.png`,
    `${IMG}/player-subtitle-3.png`,
  ],
  [
    `${IMG}/home-settings-1.png`,
    `${IMG}/home-settings-2.png`,
    `${IMG}/home-settings-3.png`,
  ],
];

const en: HowTo = {
  metaTitle: "How to Use — Another IPTV Player",
  metaDescription:
    "Step-by-step guide to Another IPTV Player: add an Xtream Codes or M3U playlist, browse live TV, movies and series, control playback, customize subtitles, and download for offline.",
  eyebrow: "Getting started",
  title: "How to use Another IPTV Player",
  intro:
    "From an empty app to watching in under a minute. Here's the whole flow, screen by screen — no account, no payment, just your own provider.",
  steps: [
    {
      title: "Add your playlist",
      body: "Open the app and tap Add Playlist. Choose Xtream Codes and enter your provider's server URL, username and password — or pick M3U / M3U8 and paste a link or select a local .m3u file. Your channels, movies and series download automatically.",
      images: stepImages[0],
    },
    {
      title: "Find what to watch",
      body: "Your content is organized into Live TV, Movies and Series tabs, grouped by category. Tap a category to browse, open a title for details and episodes, or use Search to jump straight to any channel, film or show.",
      images: stepImages[1],
    },
    {
      title: "Play and control",
      body: "Tap any title to start. While watching, swipe vertically for brightness and volume, skip ±15 seconds, and long-press for 2× speed. Pick video, audio and subtitle tracks from the player — your choices are remembered for next time.",
      images: stepImages[2],
    },
    {
      title: "Fine-tune subtitles",
      body: "Open subtitle settings to style the font, size, color, outline and position. If subtitles are out of sync, nudge the timing offset — or load your own .srt file.",
      images: stepImages[3],
    },
    {
      title: "Make it yours",
      body: "From Settings you can manage multiple playlists, download movies and episodes for offline viewing (with a Wi-Fi-only option), turn on parental controls to filter adult content, hide categories you don't use, and choose the app language. Continue Watching and Favorites keep everything you love one tap away.",
      images: stepImages[4],
    },
  ],
};

const tr: HowTo = {
  metaTitle: "Nasıl Kullanılır — Another IPTV Player",
  metaDescription:
    "Another IPTV Player adım adım rehber: Xtream Codes veya M3U oynatma listesi ekle, canlı TV, film ve dizilere göz at, oynatmayı kontrol et, altyazıları özelleştir ve çevrimdışı indir.",
  eyebrow: "Başlangıç",
  title: "Another IPTV Player nasıl kullanılır",
  intro:
    "Boş uygulamadan bir dakikadan kısa sürede izlemeye. İşte ekran ekran tüm akış — hesap yok, ödeme yok, sadece kendi sağlayıcın.",
  steps: [
    {
      title: "Oynatma listeni ekle",
      body: "Uygulamayı aç ve Oynatma Listesi Ekle'ye dokun. Xtream Codes'u seçip sağlayıcının sunucu URL'si, kullanıcı adı ve şifresini gir — ya da M3U / M3U8 seçip bir bağlantı yapıştır veya yerel bir .m3u dosyası seç. Kanalların, filmlerin ve dizilerin otomatik olarak indirilir.",
      images: stepImages[0],
    },
    {
      title: "Ne izleyeceğini bul",
      body: "İçeriğin Canlı TV, Filmler ve Diziler sekmelerinde, kategorilere göre düzenlenir. Göz atmak için bir kategoriye dokun, detay ve bölümler için bir içeriği aç ya da Ara ile herhangi bir kanal, film veya diziye anında ulaş.",
      images: stepImages[1],
    },
    {
      title: "Oynat ve kontrol et",
      body: "Başlamak için bir içeriğe dokun. İzlerken parlaklık ve ses için dikey kaydır, ±15 saniye atla, 2× hız için uzun bas. Oynatıcıdan video, ses ve altyazı parçalarını seç — tercihlerin bir sonraki sefere hatırlanır.",
      images: stepImages[2],
    },
    {
      title: "Altyazıları ince ayarla",
      body: "Altyazı ayarlarından font, boyut, renk, kontur ve konumu düzenle. Altyazı senkron değilse zamanlama ayarıyla kaydır — ya da kendi .srt dosyanı yükle.",
      images: stepImages[3],
    },
    {
      title: "Sana göre yap",
      body: "Ayarlar'dan birden fazla oynatma listesini yönetebilir, filmleri ve bölümleri çevrimdışı izlemek için indirebilir (yalnızca Wi-Fi seçeneğiyle), yetişkin içeriği filtrelemek için ebeveyn denetimini açabilir, kullanmadığın kategorileri gizleyebilir ve uygulama dilini seçebilirsin. Kaldığın Yerden Devam ve Favoriler, sevdiğin her şeyi bir dokunuş uzağında tutar.",
      images: stepImages[4],
    },
  ],
};

const content: Partial<Record<Locale, HowTo>> = { en, tr };

export function getHowTo(locale: Locale): HowTo {
  return content[locale] ?? content[defaultLocale] ?? en;
}
