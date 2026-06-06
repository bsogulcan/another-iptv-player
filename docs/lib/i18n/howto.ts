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

const de: HowTo = {
  metaTitle: "Anleitung — Another IPTV Player",
  metaDescription:
    "Schritt-für-Schritt-Anleitung für Another IPTV Player: Xtream-Codes- oder M3U-Playlist hinzufügen, Live-TV, Filme und Serien durchsuchen, Wiedergabe steuern, Untertitel anpassen und offline herunterladen.",
  eyebrow: "Erste Schritte",
  title: "So nutzt du Another IPTV Player",
  intro:
    "Von der leeren App zum Zuschauen in unter einer Minute. Hier ist der ganze Ablauf, Bildschirm für Bildschirm — kein Konto, keine Zahlung, nur dein eigener Anbieter.",
  steps: [
    {
      title: "Playlist hinzufügen",
      body: "Öffne die App und tippe auf Playlist hinzufügen. Wähle Xtream Codes und gib die Server-URL, den Benutzernamen und das Passwort deines Anbieters ein — oder wähle M3U / M3U8 und füge einen Link ein bzw. wähle eine lokale .m3u-Datei. Deine Kanäle, Filme und Serien werden automatisch geladen.",
      images: stepImages[0],
    },
    {
      title: "Finde, was du sehen willst",
      body: "Deine Inhalte sind in die Tabs Live-TV, Filme und Serien gegliedert und nach Kategorien sortiert. Tippe auf eine Kategorie zum Stöbern, öffne einen Titel für Details und Episoden oder nutze die Suche, um direkt zu jedem Kanal, Film oder jeder Serie zu springen.",
      images: stepImages[1],
    },
    {
      title: "Abspielen und steuern",
      body: "Tippe auf einen Titel, um zu starten. Wische beim Ansehen vertikal für Helligkeit und Lautstärke, springe ±15 Sekunden und halte gedrückt für 2-fache Geschwindigkeit. Wähle Video-, Audio- und Untertitelspuren im Player — deine Auswahl wird für das nächste Mal gespeichert.",
      images: stepImages[2],
    },
    {
      title: "Untertitel feinabstimmen",
      body: "Öffne die Untertiteleinstellungen, um Schriftart, Größe, Farbe, Kontur und Position anzupassen. Sind die Untertitel nicht synchron, verschiebe den Zeitversatz — oder lade deine eigene .srt-Datei.",
      images: stepImages[3],
    },
    {
      title: "Mach es zu deinem",
      body: "In den Einstellungen kannst du mehrere Playlists verwalten, Filme und Episoden für die Offline-Wiedergabe herunterladen (mit WLAN-nur-Option), die Kindersicherung aktivieren, um nicht jugendfreie Inhalte zu filtern, ungenutzte Kategorien ausblenden und die App-Sprache wählen. Weiterschauen und Favoriten halten alles, was du liebst, nur einen Tipp entfernt.",
      images: stepImages[4],
    },
  ],
};

const es: HowTo = {
  metaTitle: "Cómo usar — Another IPTV Player",
  metaDescription:
    "Guía paso a paso de Another IPTV Player: añade una lista Xtream Codes o M3U, explora TV en vivo, películas y series, controla la reproducción, personaliza los subtítulos y descarga para ver sin conexión.",
  eyebrow: "Primeros pasos",
  title: "Cómo usar Another IPTV Player",
  intro:
    "De una app vacía a estar viendo en menos de un minuto. Aquí tienes todo el proceso, pantalla por pantalla — sin cuenta, sin pago, solo tu propio proveedor.",
  steps: [
    {
      title: "Añade tu lista",
      body: "Abre la app y toca Añadir lista. Elige Xtream Codes e introduce la URL del servidor, el usuario y la contraseña de tu proveedor — o selecciona M3U / M3U8 y pega un enlace o elige un archivo .m3u local. Tus canales, películas y series se descargan automáticamente.",
      images: stepImages[0],
    },
    {
      title: "Encuentra qué ver",
      body: "Tu contenido se organiza en las pestañas TV en vivo, Películas y Series, agrupado por categorías. Toca una categoría para explorar, abre un título para ver detalles y episodios, o usa la Búsqueda para ir directo a cualquier canal, película o serie.",
      images: stepImages[1],
    },
    {
      title: "Reproduce y controla",
      body: "Toca cualquier título para empezar. Mientras ves, desliza verticalmente para el brillo y el volumen, salta ±15 segundos y mantén pulsado para velocidad 2×. Elige las pistas de vídeo, audio y subtítulos desde el reproductor — tus preferencias se recuerdan para la próxima vez.",
      images: stepImages[2],
    },
    {
      title: "Ajusta los subtítulos",
      body: "Abre los ajustes de subtítulos para personalizar la fuente, el tamaño, el color, el contorno y la posición. Si los subtítulos están desincronizados, ajusta el desfase de tiempo — o carga tu propio archivo .srt.",
      images: stepImages[3],
    },
    {
      title: "Hazlo tuyo",
      body: "Desde Ajustes puedes gestionar varias listas, descargar películas y episodios para verlos sin conexión (con opción solo por Wi-Fi), activar el control parental para filtrar contenido para adultos, ocultar categorías que no uses y elegir el idioma de la app. Continuar viendo y Favoritos mantienen todo lo que te gusta a un toque de distancia.",
      images: stepImages[4],
    },
  ],
};

const fr: HowTo = {
  metaTitle: "Comment utiliser — Another IPTV Player",
  metaDescription:
    "Guide pas à pas d'Another IPTV Player : ajoutez une playlist Xtream Codes ou M3U, parcourez la TV en direct, les films et les séries, contrôlez la lecture, personnalisez les sous-titres et téléchargez pour le hors-ligne.",
  eyebrow: "Premiers pas",
  title: "Comment utiliser Another IPTV Player",
  intro:
    "D'une app vide au visionnage en moins d'une minute. Voici tout le parcours, écran par écran — pas de compte, pas de paiement, juste votre propre fournisseur.",
  steps: [
    {
      title: "Ajoutez votre playlist",
      body: "Ouvrez l'app et touchez Ajouter une playlist. Choisissez Xtream Codes et saisissez l'URL du serveur, le nom d'utilisateur et le mot de passe de votre fournisseur — ou choisissez M3U / M3U8 et collez un lien ou sélectionnez un fichier .m3u local. Vos chaînes, films et séries se téléchargent automatiquement.",
      images: stepImages[0],
    },
    {
      title: "Trouvez quoi regarder",
      body: "Votre contenu est organisé dans les onglets TV en direct, Films et Séries, regroupé par catégorie. Touchez une catégorie pour parcourir, ouvrez un titre pour les détails et les épisodes, ou utilisez la Recherche pour accéder directement à n'importe quelle chaîne, film ou série.",
      images: stepImages[1],
    },
    {
      title: "Lisez et contrôlez",
      body: "Touchez un titre pour démarrer. Pendant le visionnage, glissez verticalement pour la luminosité et le volume, avancez de ±15 secondes et appuyez longuement pour la vitesse 2×. Choisissez les pistes vidéo, audio et sous-titres depuis le lecteur — vos choix sont mémorisés pour la prochaine fois.",
      images: stepImages[2],
    },
    {
      title: "Affinez les sous-titres",
      body: "Ouvrez les réglages des sous-titres pour personnaliser la police, la taille, la couleur, le contour et la position. Si les sous-titres sont désynchronisés, ajustez le décalage temporel — ou chargez votre propre fichier .srt.",
      images: stepImages[3],
    },
    {
      title: "Personnalisez tout",
      body: "Depuis les Réglages, vous pouvez gérer plusieurs playlists, télécharger des films et des épisodes pour les regarder hors-ligne (avec une option Wi-Fi uniquement), activer le contrôle parental pour filtrer le contenu pour adultes, masquer les catégories inutilisées et choisir la langue de l'app. Reprendre la lecture et Favoris gardent tout ce que vous aimez à portée de doigt.",
      images: stepImages[4],
    },
  ],
};

const hi: HowTo = {
  metaTitle: "कैसे उपयोग करें — Another IPTV Player",
  metaDescription:
    "Another IPTV Player की चरण-दर-चरण मार्गदर्शिका: Xtream Codes या M3U प्लेलिस्ट जोड़ें, लाइव टीवी, फ़िल्में और सीरीज़ ब्राउज़ करें, प्लेबैक नियंत्रित करें, सबटाइटल कस्टमाइज़ करें और ऑफ़लाइन डाउनलोड करें।",
  eyebrow: "शुरुआत करें",
  title: "Another IPTV Player कैसे उपयोग करें",
  intro:
    "खाली ऐप से एक मिनट से भी कम में देखने तक। यहाँ पूरा तरीका है, स्क्रीन दर स्क्रीन — कोई खाता नहीं, कोई भुगतान नहीं, बस आपका अपना प्रोवाइडर।",
  steps: [
    {
      title: "अपनी प्लेलिस्ट जोड़ें",
      body: "ऐप खोलें और प्लेलिस्ट जोड़ें पर टैप करें। Xtream Codes चुनें और अपने प्रोवाइडर का सर्वर URL, यूज़रनेम और पासवर्ड दर्ज करें — या M3U / M3U8 चुनें और लिंक पेस्ट करें या स्थानीय .m3u फ़ाइल चुनें। आपके चैनल, फ़िल्में और सीरीज़ अपने आप डाउनलोड हो जाती हैं।",
      images: stepImages[0],
    },
    {
      title: "क्या देखना है खोजें",
      body: "आपकी सामग्री लाइव टीवी, फ़िल्में और सीरीज़ टैब में, श्रेणियों के अनुसार व्यवस्थित होती है। ब्राउज़ करने के लिए किसी श्रेणी पर टैप करें, विवरण और एपिसोड के लिए कोई टाइटल खोलें, या किसी भी चैनल, फ़िल्म या शो पर सीधे जाने के लिए खोज का उपयोग करें।",
      images: stepImages[1],
    },
    {
      title: "चलाएँ और नियंत्रित करें",
      body: "शुरू करने के लिए किसी भी टाइटल पर टैप करें। देखते समय, चमक और वॉल्यूम के लिए लंबवत स्वाइप करें, ±15 सेकंड स्किप करें, और 2× गति के लिए लंबे समय तक दबाएँ। प्लेयर से वीडियो, ऑडियो और सबटाइटल ट्रैक चुनें — आपकी पसंद अगली बार के लिए याद रखी जाती है।",
      images: stepImages[2],
    },
    {
      title: "सबटाइटल को बारीकी से सेट करें",
      body: "फ़ॉन्ट, आकार, रंग, आउटलाइन और स्थिति को स्टाइल करने के लिए सबटाइटल सेटिंग्स खोलें। यदि सबटाइटल सिंक में नहीं हैं, तो टाइमिंग ऑफ़सेट समायोजित करें — या अपनी खुद की .srt फ़ाइल लोड करें।",
      images: stepImages[3],
    },
    {
      title: "इसे अपना बनाएँ",
      body: "सेटिंग्स से आप कई प्लेलिस्ट प्रबंधित कर सकते हैं, फ़िल्में और एपिसोड ऑफ़लाइन देखने के लिए डाउनलोड कर सकते हैं (केवल वाई-फ़ाई विकल्प के साथ), वयस्क सामग्री फ़िल्टर करने के लिए पैरेंटल कंट्रोल चालू कर सकते हैं, अनुपयोगी श्रेणियाँ छिपा सकते हैं और ऐप की भाषा चुन सकते हैं। देखना जारी रखें और पसंदीदा आपकी पसंद की हर चीज़ को एक टैप दूर रखते हैं।",
      images: stepImages[4],
    },
  ],
};

const pt: HowTo = {
  metaTitle: "Como usar — Another IPTV Player",
  metaDescription:
    "Guia passo a passo do Another IPTV Player: adicione uma lista Xtream Codes ou M3U, navegue por TV ao vivo, filmes e séries, controle a reprodução, personalize as legendas e baixe para assistir offline.",
  eyebrow: "Primeiros passos",
  title: "Como usar o Another IPTV Player",
  intro:
    "De um app vazio a assistir em menos de um minuto. Aqui está todo o fluxo, tela por tela — sem conta, sem pagamento, apenas o seu próprio provedor.",
  steps: [
    {
      title: "Adicione sua lista",
      body: "Abra o app e toque em Adicionar lista. Escolha Xtream Codes e insira a URL do servidor, o nome de usuário e a senha do seu provedor — ou selecione M3U / M3U8 e cole um link ou escolha um arquivo .m3u local. Seus canais, filmes e séries são baixados automaticamente.",
      images: stepImages[0],
    },
    {
      title: "Encontre o que assistir",
      body: "Seu conteúdo é organizado nas abas TV ao vivo, Filmes e Séries, agrupado por categoria. Toque em uma categoria para navegar, abra um título para ver detalhes e episódios, ou use a Busca para ir direto a qualquer canal, filme ou série.",
      images: stepImages[1],
    },
    {
      title: "Reproduza e controle",
      body: "Toque em qualquer título para começar. Enquanto assiste, deslize verticalmente para brilho e volume, avance ±15 segundos e mantenha pressionado para velocidade 2×. Escolha as faixas de vídeo, áudio e legenda no player — suas escolhas são lembradas para a próxima vez.",
      images: stepImages[2],
    },
    {
      title: "Ajuste as legendas",
      body: "Abra as configurações de legenda para personalizar a fonte, o tamanho, a cor, o contorno e a posição. Se as legendas estiverem dessincronizadas, ajuste o deslocamento de tempo — ou carregue seu próprio arquivo .srt.",
      images: stepImages[3],
    },
    {
      title: "Deixe do seu jeito",
      body: "Nas Configurações você pode gerenciar várias listas, baixar filmes e episódios para assistir offline (com opção somente Wi-Fi), ativar o controle dos pais para filtrar conteúdo adulto, ocultar categorias que não usa e escolher o idioma do app. Continuar assistindo e Favoritos mantêm tudo o que você ama a um toque de distância.",
      images: stepImages[4],
    },
  ],
};

const ru: HowTo = {
  metaTitle: "Как пользоваться — Another IPTV Player",
  metaDescription:
    "Пошаговое руководство по Another IPTV Player: добавьте плейлист Xtream Codes или M3U, просматривайте прямой эфир, фильмы и сериалы, управляйте воспроизведением, настраивайте субтитры и скачивайте для офлайн-просмотра.",
  eyebrow: "Начало работы",
  title: "Как пользоваться Another IPTV Player",
  intro:
    "От пустого приложения до просмотра меньше чем за минуту. Вот весь процесс, экран за экраном — без аккаунта, без оплаты, только ваш собственный провайдер.",
  steps: [
    {
      title: "Добавьте плейлист",
      body: "Откройте приложение и нажмите «Добавить плейлист». Выберите Xtream Codes и введите URL сервера, имя пользователя и пароль вашего провайдера — или выберите M3U / M3U8 и вставьте ссылку либо выберите локальный файл .m3u. Ваши каналы, фильмы и сериалы загрузятся автоматически.",
      images: stepImages[0],
    },
    {
      title: "Найдите, что посмотреть",
      body: "Контент разбит на вкладки «Прямой эфир», «Фильмы» и «Сериалы» и сгруппирован по категориям. Нажмите на категорию для просмотра, откройте элемент для деталей и серий или используйте поиск, чтобы сразу перейти к любому каналу, фильму или сериалу.",
      images: stepImages[1],
    },
    {
      title: "Воспроизводите и управляйте",
      body: "Нажмите на любой элемент, чтобы начать. Во время просмотра проводите вертикально для яркости и громкости, перематывайте на ±15 секунд и удерживайте для скорости 2×. Выбирайте дорожки видео, аудио и субтитров в плеере — ваш выбор запоминается на следующий раз.",
      images: stepImages[2],
    },
    {
      title: "Настройте субтитры",
      body: "Откройте настройки субтитров, чтобы настроить шрифт, размер, цвет, обводку и положение. Если субтитры не синхронизированы, сместите тайминг — или загрузите собственный файл .srt.",
      images: stepImages[3],
    },
    {
      title: "Сделайте по-своему",
      body: "В настройках можно управлять несколькими плейлистами, скачивать фильмы и серии для офлайн-просмотра (с опцией «только Wi-Fi»), включать родительский контроль для фильтрации контента для взрослых, скрывать ненужные категории и выбирать язык приложения. «Продолжить просмотр» и «Избранное» держат всё, что вы любите, в одном касании.",
      images: stepImages[4],
    },
  ],
};

const zh: HowTo = {
  metaTitle: "使用方法 — Another IPTV Player",
  metaDescription:
    "Another IPTV Player 分步指南：添加 Xtream Codes 或 M3U 播放列表，浏览直播电视、电影和剧集，控制播放，自定义字幕，并下载离线观看。",
  eyebrow: "快速上手",
  title: "如何使用 Another IPTV Player",
  intro:
    "从空白应用到开始观看，不到一分钟。这是完整的流程，逐屏演示——无需账户，无需付费，只需你自己的服务商。",
  steps: [
    {
      title: "添加你的播放列表",
      body: "打开应用并点按「添加播放列表」。选择 Xtream Codes 并输入服务商的服务器 URL、用户名和密码——或选择 M3U / M3U8 并粘贴链接或选择本地 .m3u 文件。你的频道、电影和剧集会自动下载。",
      images: stepImages[0],
    },
    {
      title: "找到想看的内容",
      body: "你的内容分为「直播电视」「电影」和「剧集」标签页，按分类分组。点按某个分类即可浏览，打开某个条目查看详情和分集，或使用搜索直接跳转到任意频道、电影或节目。",
      images: stepImages[1],
    },
    {
      title: "播放与控制",
      body: "点按任意条目即可开始。观看时，垂直滑动调节亮度和音量，快进或快退 ±15 秒，长按可 2× 倍速。在播放器中选择视频、音频和字幕轨道——你的选择会被记住，下次自动应用。",
      images: stepImages[2],
    },
    {
      title: "微调字幕",
      body: "打开字幕设置，调整字体、大小、颜色、描边和位置。如果字幕不同步，可调节时间偏移——或加载你自己的 .srt 文件。",
      images: stepImages[3],
    },
    {
      title: "打造专属体验",
      body: "在设置中，你可以管理多个播放列表，下载电影和剧集以便离线观看（可选仅 Wi-Fi），开启家长控制以过滤成人内容，隐藏不用的分类，并选择应用语言。「继续观看」和「收藏」让你喜爱的一切触手可及。",
      images: stepImages[4],
    },
  ],
};

const ar: HowTo = {
  metaTitle: "كيفية الاستخدام — Another IPTV Player",
  metaDescription:
    "دليل خطوة بخطوة لـ Another IPTV Player: أضف قائمة تشغيل Xtream Codes أو M3U، وتصفّح البث المباشر والأفلام والمسلسلات، وتحكّم في التشغيل، وخصّص الترجمة، ونزّل للمشاهدة دون اتصال.",
  eyebrow: "البدء",
  title: "كيفية استخدام Another IPTV Player",
  intro:
    "من تطبيق فارغ إلى المشاهدة في أقل من دقيقة. إليك العملية كاملة، شاشة بشاشة — بلا حساب، بلا دفع، فقط مزوّدك الخاص.",
  steps: [
    {
      title: "أضف قائمة التشغيل",
      body: "افتح التطبيق واضغط على «إضافة قائمة تشغيل». اختر Xtream Codes وأدخل عنوان URL للخادم واسم المستخدم وكلمة المرور الخاصة بمزوّدك — أو اختر M3U / M3U8 والصق رابطًا أو حدّد ملف .m3u محليًا. تُنزَّل قنواتك وأفلامك ومسلسلاتك تلقائيًا.",
      images: stepImages[0],
    },
    {
      title: "اعثر على ما تشاهده",
      body: "يُنظَّم المحتوى في علامات تبويب البث المباشر والأفلام والمسلسلات، مجمّعًا حسب الفئة. اضغط على فئة للتصفّح، أو افتح عنوانًا لعرض التفاصيل والحلقات، أو استخدم البحث للانتقال مباشرة إلى أي قناة أو فيلم أو برنامج.",
      images: stepImages[1],
    },
    {
      title: "شغّل وتحكّم",
      body: "اضغط على أي عنوان للبدء. أثناء المشاهدة، اسحب عموديًا لضبط السطوع ومستوى الصوت، وتخطَّ ±15 ثانية، واضغط مطوّلًا للسرعة 2×. اختر مسارات الفيديو والصوت والترجمة من المشغّل — تُحفَظ اختياراتك للمرة القادمة.",
      images: stepImages[2],
    },
    {
      title: "اضبط الترجمة بدقّة",
      body: "افتح إعدادات الترجمة لتنسيق الخط والحجم واللون والحدود والموضع. إذا كانت الترجمة غير متزامنة، فعدّل إزاحة التوقيت — أو حمّل ملف .srt الخاص بك.",
      images: stepImages[3],
    },
    {
      title: "اجعله خاصًا بك",
      body: "من الإعدادات يمكنك إدارة قوائم تشغيل متعددة، وتنزيل الأفلام والحلقات للمشاهدة دون اتصال (مع خيار Wi-Fi فقط)، وتفعيل الرقابة الأبوية لتصفية المحتوى المخصّص للبالغين، وإخفاء الفئات غير المستخدمة، واختيار لغة التطبيق. تُبقي «متابعة المشاهدة» و«المفضّلة» كل ما تحبّه على بُعد ضغطة واحدة.",
      images: stepImages[4],
    },
  ],
};

const content: Partial<Record<Locale, HowTo>> = {
  en,
  tr,
  de,
  es,
  fr,
  hi,
  pt,
  ru,
  zh,
  ar,
};

export function getHowTo(locale: Locale): HowTo {
  return content[locale] ?? content[defaultLocale] ?? en;
}
