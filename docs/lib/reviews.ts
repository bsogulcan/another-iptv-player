import type { Locale } from "./i18n/config";

/**
 * Hand-picked App Store reviews. `text` is the reviewer's original wording,
 * quoted verbatim (long reviews are trimmed with "…"); `translations` cover
 * every other site locale. Reviewer names are intentionally omitted; only
 * storefront and device are shown.
 */
export type Review = {
  text: string;
  lang: Locale;
  country: string;
  device: "iPhone" | "Mac";
  translations: Partial<Record<Locale, string>>;
};

export const REVIEWS: Review[] = [
  {
    text: "I swear I have tried almost every IPTV player on the App Store, and Another IPTV Player is by far the cleanest, fastest, and most user-friendly of them all.",
    lang: "en",
    country: "EG",
    device: "iPhone",
    translations: {
      tr: "Yemin ederim App Store'daki neredeyse her IPTV oynatıcıyı denedim; Another IPTV Player açık ara en temiz, en hızlı ve en kullanıcı dostu olanı.",
      de: "Ich schwöre, ich habe fast jeden IPTV-Player im App Store ausprobiert, und Another IPTV Player ist mit Abstand der aufgeräumteste, schnellste und benutzerfreundlichste von allen.",
      es: "Te lo juro, he probado casi todos los reproductores IPTV de la App Store, y Another IPTV Player es de lejos el más limpio, el más rápido y el más fácil de usar de todos.",
      fr: "Je vous jure que j’ai essayé presque tous les lecteurs IPTV de l’App Store, et Another IPTV Player est de loin le plus épuré, le plus rapide et le plus simple à utiliser.",
      pt: "Juro que já testei quase todos os players de IPTV da App Store, e o Another IPTV Player é de longe o mais limpo, o mais rápido e o mais fácil de usar de todos.",
      ru: "Честное слово, почти все IPTV-плееры из App Store уже испробованы, и Another IPTV Player — безусловно самый аккуратный, быстрый и удобный из всех.",
      ar: "أقسم أنني جربت تقريبًا كل مشغلات IPTV على App Store، وAnother IPTV Player هو بلا منازع الأنظف والأسرع والأسهل استخدامًا بينها جميعًا.",
      hi: "कसम से, मैंने App Store का लगभग हर IPTV प्लेयर आज़माया है, और Another IPTV Player इन सब में सबसे साफ़-सुथरा, सबसे तेज़ और सबसे आसान है।",
      zh: "我发誓，App Store 上几乎所有 IPTV 播放器我都试过了，Another IPTV Player 是其中最简洁、最快、最好用的，没有之一。",
    },
  },
  {
    text: "Hands down the best app on the store! Thank you for adding the EPG — that’s huge and puts your app right at the top of the list!",
    lang: "en",
    country: "US",
    device: "Mac",
    translations: {
      tr: "Mağazadaki açık ara en iyi uygulama! EPG'yi eklediğin için teşekkürler — bu çok büyük bir yenilik ve uygulamanı listenin en tepesine taşıyor!",
      de: "Ganz klar die beste App im Store! Danke, dass ihr den EPG hinzugefügt habt — das ist riesig und bringt eure App ganz an die Spitze!",
      es: "¡Sin duda la mejor app de la tienda! Gracias por añadir la EPG: es un gran avance y pone tu app en lo más alto de la lista.",
      fr: "Sans conteste la meilleure app du store ! Merci d’avoir ajouté l’EPG — c’est énorme et ça place votre app tout en haut de la liste !",
      pt: "Sem dúvida o melhor app da loja! Agradeço por adicionar o EPG — isso é enorme e coloca seu app no topo da lista!",
      ru: "Однозначно лучшее приложение в магазине! Спасибо, что добавили EPG — это огромный плюс, и он выводит ваше приложение на первое место!",
      ar: "بلا شك أفضل تطبيق في المتجر! شكرًا لإضافة دليل البرامج (EPG) — إنها إضافة ضخمة تضع تطبيقك في صدارة القائمة!",
      hi: "बिना किसी शक के स्टोर का सबसे अच्छा ऐप! EPG जोड़ने के लिए धन्यवाद — यह बहुत बड़ी बात है और इससे आपका ऐप सूची में सबसे ऊपर पहुँच गया है!",
      zh: "毫无疑问是商店里最好的应用！感谢加入 EPG——这是个巨大的提升，让你的应用稳居榜首！",
    },
  },
  {
    text: "Muito bom!! sem propagandas, sem trial, simples e direto Opção de download foi a cereja do bolo Parabéns!!!",
    lang: "pt",
    country: "BR",
    device: "iPhone",
    translations: {
      en: "Really good!! No ads, no trial, simple and straightforward. The download option was the cherry on top. Congrats!!!",
      tr: "Çok iyi!! Reklam yok, deneme süresi yok, basit ve net. İndirme seçeneği de işin kaymağı oldu. Tebrikler!!!",
      de: "Sehr gut!! Keine Werbung, keine Testphase, einfach und direkt. Die Download-Option war das Tüpfelchen auf dem i. Glückwunsch!!!",
      es: "¡¡Muy bueno!! Sin anuncios, sin prueba, simple y directo. La opción de descarga fue la guinda del pastel. ¡¡¡Felicidades!!!",
      fr: "Très bien !! Pas de pub, pas de période d’essai, simple et direct. L’option de téléchargement, c’est la cerise sur le gâteau. Bravo !!!",
      ru: "Очень круто!! Без рекламы, без пробного периода, просто и понятно. Возможность скачивания — вишенка на торте. Поздравляю!!!",
      ar: "رائع جدًا!! بدون إعلانات، بدون فترة تجريبية، بسيط ومباشر. وخيار التنزيل كان الإضافة المثالية. مبروك!!!",
      hi: "बहुत बढ़िया!! कोई विज्ञापन नहीं, कोई ट्रायल नहीं, सीधा और आसान। डाउनलोड का विकल्प तो सोने पे सुहागा है। बधाई हो!!!",
      zh: "太棒了！！没有广告，没有试用期，简单直接。下载功能更是锦上添花。恭喜！！！",
    },
  },
  {
    text: "Je souhaite donner de la force à cette application open source. Cela fait longtemps que j’en recherche une digne de ce nom et celle-ci remplit toutes les cases. Le Picture in Picture fonctionne très bien.",
    lang: "fr",
    country: "FR",
    device: "iPhone",
    translations: {
      en: "I want to show my support for this open-source app. I’ve been looking for a decent one for a long time, and this one ticks every box. Picture in Picture works really well.",
      tr: "Bu açık kaynak uygulamaya destek vermek istiyorum. Uzun zamandır adına yakışır bir uygulama arıyordum ve bu her açıdan beklentimi karşılıyor. Resim içinde resim (PiP) çok iyi çalışıyor.",
      de: "Ich möchte diese Open-Source-App unterstützen. Ich habe lange nach einer gesucht, die diesen Namen verdient, und diese hier erfüllt alle Wünsche. Bild-in-Bild funktioniert sehr gut.",
      es: "Quiero darle mi apoyo a esta app de código abierto. Llevaba mucho tiempo buscando una que valiera la pena y esta cumple con todo. El Picture in Picture funciona muy bien.",
      pt: "Quero dar meu apoio a este app de código aberto. Fazia tempo que eu procurava um que valesse a pena, e este atende a todos os requisitos. O Picture in Picture funciona muito bem.",
      ru: "Хочу поддержать это приложение с открытым исходным кодом. Долго не удавалось найти достойное, а это отвечает всем требованиям. Картинка в картинке работает отлично.",
      ar: "أود أن أدعم هذا التطبيق مفتوح المصدر. بحثت طويلًا عن تطبيق جدير بهذا الاسم، وهذا التطبيق يلبي كل المتطلبات. ميزة صورة داخل صورة تعمل بشكل ممتاز.",
      hi: "इस ओपन-सोर्स ऐप को मेरा पूरा समर्थन। लंबे समय से एक अच्छे ऐप की तलाश थी, और यह हर कसौटी पर खरा उतरता है। पिक्चर-इन-पिक्चर बहुत बढ़िया काम करता है।",
      zh: "我想为这款开源应用加油。我找了很久才找到一款名副其实的，它完全满足了我的所有需求。画中画功能也非常好用。",
    },
  },
  {
    text: "This is the best ad free iptv app you can get for you iphone, ipad and mac. Kudos to the dev for keeping it lighweight, free and ad free.",
    lang: "en",
    country: "IN",
    device: "iPhone",
    translations: {
      tr: "iPhone, iPad ve Mac için bulabileceğin en iyi reklamsız IPTV uygulaması bu. Hafif, ücretsiz ve reklamsız tuttuğu için geliştiriciyi tebrik ederim.",
      de: "Das ist die beste werbefreie IPTV-App, die du für iPhone, iPad und Mac bekommen kannst. Respekt an den Entwickler, dass sie schlank, kostenlos und werbefrei bleibt.",
      es: "Es la mejor app de IPTV sin anuncios que puedes conseguir para tu iPhone, iPad y Mac. Felicidades al desarrollador por mantenerla ligera, gratis y sin anuncios.",
      fr: "C’est la meilleure app IPTV sans pub que vous puissiez trouver pour votre iPhone, iPad et Mac. Bravo au développeur de la garder légère, gratuite et sans pub.",
      pt: "Este é o melhor app de IPTV sem anúncios que você pode ter no iPhone, iPad e Mac. Parabéns ao desenvolvedor por mantê-lo leve, gratuito e sem anúncios.",
      ru: "Это лучшее IPTV-приложение без рекламы для iPhone, iPad и Mac. Респект разработчику за то, что оно остаётся лёгким, бесплатным и без рекламы.",
      ar: "هذا أفضل تطبيق IPTV خالٍ من الإعلانات يمكنك الحصول عليه لأجهزة iPhone وiPad وMac. تحية للمطوّر لإبقائه خفيفًا ومجانيًا وبلا إعلانات.",
      hi: "यह iPhone, iPad और Mac के लिए सबसे अच्छा विज्ञापन-मुक्त IPTV ऐप है। इसे हल्का, मुफ़्त और विज्ञापन-मुक्त रखने के लिए डेवलपर को शाबाश।",
      zh: "这是你能在 iPhone、iPad 和 Mac 上找到的最好的无广告 IPTV 应用。为开发者点赞，让它保持轻量、免费、无广告。",
    },
  },
  {
    text: "Минимализм, не лагает, загрузил плейлист и сразу смотрю в отличном качестве футбол! Спасибо большое за программу! Вы молодцы!",
    lang: "ru",
    country: "RU",
    device: "Mac",
    translations: {
      en: "Minimalist, no lag — loaded my playlist and I’m watching football in great quality right away! Thanks a lot for the app! Great job!",
      tr: "Minimalist, takılma yok, listemi yükledim ve hemen mükemmel kalitede maç izliyorum! Uygulama için çok teşekkürler! Harikasınız!",
      de: "Minimalistisch, ruckelt nicht — Playlist geladen und schon schaue ich Fußball in super Qualität! Vielen Dank für die App! Klasse gemacht!",
      es: "Minimalista, sin lag: cargué mi lista y ya estoy viendo fútbol en excelente calidad. ¡Muchas gracias por la app! ¡Son unos cracks!",
      fr: "Minimaliste, aucun lag : j’ai chargé ma playlist et je regarde tout de suite le foot en super qualité ! Merci beaucoup pour l’app ! Bravo à vous !",
      pt: "Minimalista, sem travar: carreguei a playlist e já estou vendo futebol em ótima qualidade! Muito obrigado pelo app! Mandaram bem!",
      ar: "بسيط، بلا تقطيع، حمّلت قائمة التشغيل وأشاهد كرة القدم فورًا بجودة ممتازة! شكرًا جزيلًا على البرنامج! أحسنتم!",
      hi: "मिनिमल, कोई लैग नहीं — प्लेलिस्ट लोड की और तुरंत बेहतरीन क्वालिटी में फ़ुटबॉल देख रहा हूँ! ऐप के लिए बहुत-बहुत धन्यवाद! आप कमाल हैं!",
      zh: "极简，不卡顿，导入播放列表后马上就能看高清足球！非常感谢这款软件！你们太棒了！",
    },
  },
  {
    text: "Aradığınız her özellik mevcut offline izleme stabil çalışıyor özellikle iosta başka uygulama aramayın",
    lang: "tr",
    country: "TR",
    device: "iPhone",
    translations: {
      en: "Every feature you’re looking for is here, and offline viewing works reliably — especially on iOS, don’t bother looking for another app.",
      de: "Jede Funktion, die man sucht, ist da, und die Offline-Wiedergabe läuft stabil — gerade auf iOS müsst ihr keine andere App suchen.",
      es: "Tiene todas las funciones que buscas y la reproducción sin conexión funciona de forma estable; sobre todo en iOS, no busques otra app.",
      fr: "Toutes les fonctionnalités que vous cherchez sont là, et la lecture hors ligne est stable — surtout sur iOS, ne cherchez pas d’autre app.",
      pt: "Tem todos os recursos que você procura, e a reprodução offline funciona de forma estável — principalmente no iOS, nem procure outro app.",
      ru: "Есть все нужные функции, офлайн-просмотр работает стабильно — особенно на iOS, другое приложение можно не искать.",
      ar: "كل ميزة تبحث عنها موجودة، والمشاهدة دون اتصال تعمل بثبات — خصوصًا على iOS، لا تبحث عن تطبيق آخر.",
      hi: "आप जो भी फ़ीचर ढूँढ रहे हैं, सब मौजूद है, और ऑफ़लाइन देखना भी स्थिर चलता है — ख़ासकर iOS पर, कोई और ऐप ढूँढने की ज़रूरत नहीं।",
      zh: "你想要的功能这里都有，离线观看也很稳定——尤其是在 iOS 上，别再找其他应用了。",
    },
  },
  {
    text: "After 200 apps that I tried... I finally found one that works 100% well! … Total free no ads no bull Tnx",
    lang: "en",
    country: "NL",
    device: "iPhone",
    translations: {
      tr: "200 uygulama denedikten sonra... sonunda %100 sorunsuz çalışan birini buldum! … Tamamen ücretsiz, reklam yok, saçmalık yok. Sağ ol",
      de: "Nach 200 getesteten Apps... endlich eine gefunden, die zu 100 % funktioniert! … Komplett kostenlos, keine Werbung, kein Quatsch. Danke",
      es: "Después de probar 200 apps... ¡por fin encontré una que funciona al 100 %! … Totalmente gratis, sin anuncios, sin tonterías. Gracias",
      fr: "Après 200 applis testées... j’en ai enfin trouvé une qui marche à 100 % ! … Totalement gratuite, pas de pub, pas d’embrouille. Merci",
      pt: "Depois de testar 200 apps... finalmente encontrei um que funciona 100%! … Totalmente grátis, sem anúncios, sem enrolação. Valeu",
      ru: "После 200 испробованных приложений... наконец нашлось одно, которое работает на все 100%! … Полностью бесплатно, без рекламы, без ерунды. Спасибо",
      ar: "بعد تجربة 200 تطبيق... وجدت أخيرًا تطبيقًا يعمل بنسبة 100%! … مجاني تمامًا، بلا إعلانات، بلا تعقيدات. شكرًا",
      hi: "200 ऐप आज़माने के बाद... आख़िरकार एक ऐसा मिला जो 100% ठीक चलता है! … पूरी तरह मुफ़्त, कोई विज्ञापन नहीं, कोई झंझट नहीं। शुक्रिया",
      zh: "试了 200 个应用之后……终于找到一个 100% 好用的！……完全免费，没广告，不整虚的。谢了",
    },
  },
  {
    text: "This is the simplest and most reliable IPTV app for MacOS. … It’s truly free to use, very easy to use, a UI that’s better than more of the others for TV.",
    lang: "en",
    country: "US",
    device: "Mac",
    translations: {
      tr: "macOS için en sade ve en güvenilir IPTV uygulaması bu. … Gerçekten ücretsiz, kullanımı çok kolay ve TV için arayüzü diğerlerinin çoğundan daha iyi.",
      de: "Das ist die einfachste und zuverlässigste IPTV-App für macOS. … Wirklich kostenlos, sehr einfach zu bedienen und mit einer Oberfläche, die fürs Fernsehen besser ist als die der meisten anderen.",
      es: "Es la app de IPTV más sencilla y fiable para macOS. … Es realmente gratis, muy fácil de usar y su interfaz es mejor para ver TV que la de la mayoría.",
      fr: "C’est l’app IPTV la plus simple et la plus fiable sur macOS. … Vraiment gratuite, très facile à utiliser, avec une interface meilleure pour la TV que la plupart des autres.",
      pt: "É o app de IPTV mais simples e confiável para macOS. … Realmente gratuito, muito fácil de usar e com uma interface melhor para TV do que a maioria dos outros.",
      ru: "Это самое простое и надёжное IPTV-приложение для macOS. … По-настоящему бесплатное, очень простое в использовании, а интерфейс для ТВ лучше, чем у большинства других.",
      ar: "هذا أبسط تطبيق IPTV وأكثرها موثوقية على macOS. … مجاني فعلًا، وسهل الاستخدام جدًا، وواجهته لمشاهدة التلفاز أفضل من معظم التطبيقات الأخرى.",
      hi: "यह macOS के लिए सबसे सरल और भरोसेमंद IPTV ऐप है। … सच में मुफ़्त, इस्तेमाल में बहुत आसान, और TV के लिए इसका इंटरफ़ेस ज़्यादातर दूसरे ऐप्स से बेहतर है।",
      zh: "这是 macOS 上最简单、最可靠的 IPTV 应用。……真正免费，非常好用，看电视的界面比大多数同类应用都好。",
    },
  },
];
