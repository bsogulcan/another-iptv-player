# iOS Tarama Ekranları — Yerel His ve Akıcılık Raporu

> **Güncel kapanış (2026-10-03):** Aşağıdaki rapor önceki dalganın tarihsel kaydıdır. Güncel durum [358 bulgu tablosunda](ios-browse-native-verification.md) ve [devir kaydının 16. bölümünde](ios-browse-native-handoff.md): 255 çözüldü, 49 kısmen, 53 kararla bırakıldı, 1 çözülmedi. Son test tekrarının geçici sonuçları bulunamadığı için başarılı sayılmadı; fiziksel cihaz kurulumu depolama doluluğu nedeniyle yapılamadı.

Tarih: 2026-10-02 · Kapsam: Canlı TV, Filmler, Diziler, detay sayfaları, Arama, Ayarlar, oynatma listesi ekranı, TV Rehberi, M3U · Durum: çalışma ağacında, **commit ve push yok**

**Sonuç:** Denetim 359 bulgu çıkardı (bağımsız doğrulamada 91'i olduğu gibi, 260'ı düzeltilerek doğrulandı, 1'i çürütüldü). Bunlar üç dalgada uygulandı. Proje derleniyor; **1345 birim testi** (önce 794) ve **37 arayüz testi** (önce 30) simülatörde geçiyor. Yeni arayüz testlerinin 7'si bu çalışmanın davranış değişikliklerini sabitliyor ve 7'si de değişiklik öncesi kodda başarısız oluyordu. Hiçbir şey gerçek cihazda görülmedi; bölüm 7'deki tur gerekli.

**Bu sayılar hakkında dürüst not:** Bulgu bazında bağımsız durum kontrolünü (47 ajan) maliyet nedeniyle senin isteğinle yapmadım. Bu yüzden "N bulgu düzeltildi" diye bir sayı vermiyorum. Aşağıdaki durumlar üç kaynaktan geliyor: (1) uygulayan ajanların kendi raporları, (2) ilk iki dalgada her kolun ayrı ve bağımsız bir incelemesi (bazı kollarda yarıda kaldı, bölüm 6), (3) testler ve ekran görüntüleri.

## 1. Nasıl yapıldı

| Aşama | İçerik | Bağımsız inceleme | Sonuç |
|---|---|---|---|
| Başlangıç | — | — | 794 birim, 30 arayüz testi; akıcılık ölçümü (bölüm 4) |
| Denetim | 28 bakış açısı, 359 bulgu, her biri ayrı bir doğrulayıcıdan geçti | — | 25 küme, 52 karar sorusu |
| 0. dalga (4 kol) | Katalog deposu, veri katmanı, arama çekirdeği, görsel hattı | 4/4 kol incelendi ve düzeltildi | 994 birim, 30 arayüz testi |
| 1. dalga (15 kol) | Her tarama ekranının davranışı ve yapısı, panolar, TV rehberi, arka plan işleri, test verisi, ortak bileşen seti | 9/15 kol incelendi; 3 kolun düzeltme turu tamamlandı | birleştirildi |
| 2. dalga (6 kol, yalın) | Ortak bileşenlerin ekranlara uygulanması, bağlam menüleri, basma hissi, geçişler, dil ve biçim | inceleme yok (maliyet) | 1345 birim, 37 arayüz testi |

Kararlar senin yerine muhafazakâr varsayılanlarla alındı (bölüm 5). Kullanıcıya görünen ürün kararları değiştirilmedi, raporlandı.

## 2. Fark edeceğin değişiklikler

**Her tarama ekranı (Canlı TV, Filmler, Diziler, M3U)**
- Raf başlıkları artık mavi bağlantı değil: kalın, metin renginde başlık ve gri `›`, Apple TV / Müzik'teki gibi. Başlığa uzun basınca "Kategoriyi gizle".
- Kartlara dokununca hafif basılma (küçülme + kararma) var; uzun basınca bağlam menüsü açılıyor: film ve dizide Favorilere ekle/çıkar, kanalda Oynat · Favori · Program akışı (rehber açıksa). İzleme geçmişi kartlarında Oynat · Geçmişten kaldır.
- Poster başlıkları iki satıra kadar sola dayalı, kanal adları ortalı; ızgaralar üstten hizalı.
- Posterden detay sayfasına **yakınlaşarak açılan geçiş** (Filmler, Diziler, Favoriler). Tek bir sabitle kapatılabilir: `BrowseTransitions.usesZoom`.
- Kategori ızgaralarında, Tüm Filmler/Diziler/Kanallar'da, Favoriler'de ve Geçmiş'te **sekme çubuğu artık kaybolmuyor** (TV Rehberi hariç).
- Aşağı çekip yenileme rafları gerçekten güncelliyor (önce sekmeden çıkıp girmek gerekiyordu). Yenileme hatası görünür bir uyarıyla geliyor.
- Yüklenirken yanlış "kategori bulunamadı" ekranı yok; yer tutucular yüklenmiş satırla aynı yükseklikte, raflar sonradan kaymıyor. "Son eklenenler" en baştan doğru yerde.
- Kategoriye atlama anında (animasyonlu kaydırma ve zamanlayıcı yok). Sıralama/filtre değişince liste başa dönüyor; detaydan geri gelince kaydırma yeri ve sayfa korunuyor.
- Rehberi olmayan ya da rehberi hiçbir kanalla eşleşmeyen listelerde kanal adlarının altındaki **boş satır kalktı**.

**Detay sayfaları**
- Film ve dizi detayı artık hiçbir zaman tüm sayfayı spinner ya da hata ekranıyla değiştirmiyor: kahraman alanı, başlık ve Oynat hemen görünüyor; yüklenemeyen parça yerinde "Tekrar dene" ile gösteriliyor ve bağlantı geri gelince bir kez kendiliğinden deniyor.
- Dizi: bölüm satırının tamamı dokunulabilir; sezon değiştirirken liste boşalmıyor; tek sezonlu dizide sezon çubuğu yok; ilk sezonu boş dizilerde "İzle" artık boşa basılmıyor, ilk oynatılabilir bölümü açıyor; bölümler arası ileri/geri ve otomatik sonraki bölüm, dizi sayfası kapansa da çalışıyor (Devam Et ve İndirilenler'deki oynatıcıyla aynı yoldan).
- Favori yıldızı anında değişiyor, hafif titreşim veriyor. İndirme düğmesi indirme sürerken dokununca menü açıyor (iptal/sil), genişliği yüzdeyle oynamıyor.
- Puan her yerde aynı biçimde (posterde 7,5 detayda 7.5 farkı yok).

**Arama**
- Sistem kapsam çubuğu (Tümü · Canlı TV · Filmler · Diziler) el yapımı çiplerin yerine geldi.
- Sıralama: tam eşleşme, sonra başlangıç eşleşmesi, sonra diğerleri ("mi" yazınca Midnight Horizon, Family Ties'ın önünde). Türkçe cihazda "film" artık "FİLM"i buluyor; aksan ve noktalama fark etmiyor.
- Eski sorgunun taraması yenisi gelince iptal ediliyor; "Sonuç yok" ancak gerçekten aranmış bir sorgu için çıkıyor. Kaydırınca klavye kapanıyor.

**Ayarlar**
- Yerel bölümler (istatistik, TV rehberi, içerik yönetimi) hesap isteğini beklemiyor; hesap bilgisi her açılışta yeniden çekilmiyor, hata kırmızı ham metin değil.
- Yetişkin içerik anahtarı (Xtream) önce soruyor, sonra yeni değerle yeniden indiriyor. Silme gibi yıkıcı işlemler onay penceresiyle.
- Bir ayarın kaydı artık başka bir ayarı geri almıyor (eski kopyanın üstüne yazma sorunu).
- "TV rehberini göster" kapatılınca rehber gerçekten kapanıyor: şimdi/sonra satırları, Rehber düğmesi ve dakikalık sayaç kalkıyor; veriler duruyor, tekrar açınca anında geliyor.

**Oynatma listesi ekranı ve ekleme**
- + düğmesi doğrudan menü (Xtream Code / M3U); ara ekran yok. Satırlar sunucu adresini kimlik bilgisi olmadan gösteriyor; düzenle/sil kaydırma ve uzun basmayla, silme onaylı.
- Formlar: alan odakları, gönderim sırası, kaydederken iptal (indirme bitmeden iptal edilirse hiçbir şey yazılmıyor), anlaşılır hata başlıkları ve mesajları, kaydedilmemiş girdi varsa "Değişiklikleri at" sorusu.

**TV rehberi**
- Rehber satırları ana iş parçacığı dışında kuruluyor; gizli kategorilerin kanalları listede ve oynatma sırasında yok.
- Kanal programından dönünce rehber kaldığın saatte; gece yarısını geçince "Bugün" doğru güne geçiyor. M3U listelerinde kanala dokunmak oynatıyor.
- Gün çipleri seçili durumu erişilebilirliğe bildiriyor; saat ve süreler uygulama dilinde.

**Arka planda değişenler (hissedilen etkisi)**
- Rehber güncellemesi (gzip açma, XML çözme, veritabanına yazma) artık ana iş parçacığını dondurmuyor; önce büyük rehberlerde birkaç saniyelik donma yapıyordu.
- Katalog okuma hızlandı: 150 bin filmlik katalogda 664 ms → 170 ms (Mac'te ölçüldü).
- Görseller: 300 MB küçük resim disk önbelleği, ekrana göre küçültülerek çözme, ölü sunuculara karşı devre kesici (kendiliğinden toparlanıyor), bağlantı/ön plana dönüşte başarısız görsellerin yeniden denenmesi.
- Uygulama dili ile sayı, tarih ve çoğul biçimleri tutarlı (Rusça/Arapça çoğullar doğru).
- iPad'de uygulama tek pencereli (ikinci pencere ilkini bozuyordu; derlenen uygulamada `UIApplicationSupportsMultipleScenes = false` doğrulandı, iPad simülatöründe açılıyor); poster boyutları pencere boyutunu izliyor.

## 3. Yeni davranış testleri

Hepsi önce değişiklik öncesi koda karşı çalıştırıldı ve 7'si de başarısız oldu; şimdi geçiyorlar (`UserFlowsUITests.swift` → `BrowseBehaviourUITests`):

1. Kategori ızgarasında sekme çubuğu kalıyor.
2. Arama, başlangıç eşleşmesini içerik eşleşmesinin önüne koyuyor.
3. Aramadaki tür filtresi sistem kapsam çubuğu.
4. + düğmesi menü; arada sayfa açılmıyor.
5. Dizi detayı, sezonlar yüklenemediğinde de başlığını gösteriyor.
6. Yetişkin içerik anahtarı önce soruyor; vazgeçince değer değişmiyor. (Önceki kodda anahtar ekrana hiç gelmiyordu, çünkü bölüm hesap isteğini bekliyordu.)
7. Postere uzun basınca detay açılmadan "Favorilere ekle" çıkıyor.

## 4. Akıcılık: önce ve sonra

Simülatörde, 120 bin öğelik yapay katalogla, optimize derlemeyle, uygulamanın içinden sürülen aynı 16 senaryo. Sayılar ana iş parçacığının bir kareyi kaçıracak kadar meşgul kaldığı süreleri gösteriyor. Simülatör ve ölçüm aracı yük ekliyor; mutlak değil, önce/sonra karşılaştırması olarak okunmalı.

| Ölçüm | Önce | Sonra |
|---|---|---|
| Açılış: en uzun takılma (ilk 8 sn) | 113 ms | 23 ms |
| Açılış: kare bütçesini aşan toplam süre | 99 ms | 6 ms |
| Arama: son tuştan sonuçların oturmasına | 1,16 sn | 0,32 sn |
| Sekme geçişi: en uzun takılma (4 geçiş) | 36–77 ms | 43–70 ms |
| Kategoriye girme: en uzun takılma | 61 ms | 86 ms |
| Kategoriden geri dönme: en uzun takılma | 93 ms | 74 ms |
| Raf ve ızgara kaydırma: en uzun takılma | 16–33 ms | 17–38 ms |
| Film detayına girip çıkma | 87–125 ms (ilk 255) | ölçülemedi (aşağıda) |

Okuma: açılış ve arama belirgin biçimde hızlandı. Kaydırma ve sekme geçişi ölçüm gürültüsü içinde aynı kaldı; kategoriye girme biraz yavaşladı, geri dönme hızlandı. Ekranlardaki asıl fark kare hızında değil: yanlış boş ekranların, sonradan kayan rafların, sayfayı kaplayan spinner'ların ve yenilenmeyen listelerin kalkmasında. Film detayı ölçümünde ölçüm aracı yeni detay sayfasından programla geri dönemedi (ilk açılış ölçüldü: en uzun takılma 157 ms, önce 255 ms), bu yüzden tekrarlı aç/kapa sayısı yok. Uygulamada geri dönüş çalışıyor; detayı açıp geri gelen arayüz testleri geçiyor.

## 5. Senin yerine verilen kararlar

Benimsenenler (kısa): sekme çubuğu itilen ekranlarda kalıyor (rehber hariç) · tek raf başlığı stili · poster başlıkları 2 satır sola dayalı · bağlam menüleri (yalnızca favori/gizle/oynat/geçmişten kaldır; indirme, paylaşma yok) · kart ve satırlarda basma hissi · aramada sistem kapsamları, 2 karakter ve 250 ms bekleme kaldı · boş/hata durumları uygulama dilinde · yıkıcı işlemler onaylı · yetişkin içerik anahtarı soruyor · detay sayfası asla tamamen spinner/hata olmuyor · indirme düğmesi menüsü · + düğmesi menü · dil değişince Ayarlar'a dönülüyor · 300 MB küçük resim önbelleği · iPad'de tek pencere · titreşimler (favori, seçim, senkron sonucu) · posterden detaya yakınlaşma · "Kategoriyi gizle" rehberde ve oynatma sırasında da gizliyor · "TV rehberini göster" kapalıyken rehber tamamen kapalı · uygulama dili + cihaz bölgesi tek yerel ayar · M3U'da artık listede olmayan kanalın geçmiş kartı "Geçmişten kaldır" soruyor · M3U rehberinde kanala dokunmak oynatıyor · rehberi eşleşmeyen listede şimdi/sonra satırı yer kaplamıyor.

Bilerek dokunulmayanlar (senin kararın): liste görünümlü kanal satırları ve büyük kanal karoları, raflarda "Tümünü gör" sınırı, sekmelerdeki arama alanının kaldırılması, Kitaplık sekmesi, Ayarlar'ın alt sayfalara bölünmesi · Devam Et'te tekrarların birleştirilmesi, "Sıradaki" mantığı, 16:9 bölüm görselleri, sezon menüsü · rehberde verisi olmayan kanalları gizleme · otomatik açılış, isteğe bağlı liste adı, arka planda katalog yenileme, indirmeyi duraklatma · mini oynatıcının konumu ve kaydırma payı · iPad yoğunluğu ve klavye kısayolları · sekme çubuğunu küçültme, detay düğmelerini sistem stiline çevirme, uygulama vurgu rengi · M3U için arama sekmesi, sıralama, poster kartları · oynatıcı dosyaları · indirme yaşam döngüsü, M3U indirme uyarısı, değerlendirme isteğinin zamanı (yalnızca korumalar eklendi), sezonların yenilemeden sonra saklanması, kategori başına sıralama, sistem dil ayarına geçiş.

## 6. Açık kalanlar ve riskler

- **İncelenmeden giren kod:** 1. dalgada panolar, TV rehberi, arka plan işleri, test verisi, ortak bileşen seti ve oynatma listesi ekranı kollarının bağımsız incelemesi yarıda kaldı; 2. dalganın hiç incelemesi yok. Bunlar yalnızca testlerle ve ekran görüntüleriyle kontrol edildi.
- **Bırakılan küçük inceleme notları:** 1. dalga incelemelerinin 15 "minor" notu düzeltilmedi. Örnekler: raf görsel ön yüklemesinin durdurulması her zaman başlatıldığı listeyle aynı olmayabilir; Filmler yüklenirken "Son eklenenler" yeri ayrılıp katalogda tarih yoksa kaldırılıyor (bir kez kayma); dizi sezonunun bölümleri ana iş parçacığında okunuyor (sezon başına birkaç düzine satır); boş M3U listesinde aşağı çekip yenileme yükleme ekranına geçiyor.
- **M3U kart menüsünde indirme:** karar "kart menüsünde indirme yok" diyor, ama M3U'da film indirmenin tek yolu bu menü olduğu için kaldırılmadı. Karar senin.
- **Favoriler ekranı** kendi kart görünümünü kullanıyor (ortak kartlar değil); ileride kart değişiklikleri oraya ayrıca yansıtılmalı.
- **Ortak kartlarda ilerleme çubuğu** film/dizi kartlarında hâlâ posterin üstünde; Devam Et ve Geçmiş'te altta.
- **Rehberde kanal hücreleri** artık düğme + bağlam menüsü; iki yönlü kaydırmanın cihazda aynı rahatlıkta olduğu görülmedi.
- **Rehberi hiç eşleşmeyen liste** (karar A31): ilk açılışta çevrimdışıysa kartlar satırsız başlar, rehber sonra eşleşirse raflar bir kez büyür.
- **App Store ekran görüntüleri:** demo listede şimdi/sonra satırı kalktığı için Canlı TV kartları ~22 pt kısaldı; görüntüler yeniden alınırsa düzen biraz değişir.

## 7. Cihazda bakılması gerekenler

1. Uzun katalogda raf ve ızgara kaydırma, sekme geçişi, detay aç/kapa (yakınlaşma geçişi dahil, iPhone ve iPad).
2. Kartlarda basma hissi ile kaydırma çakışıyor mu (hızlı fiske kartları basılı göstermemeli); bağlam menüsü ve önizleme şekli.
3. Aşağı çekip yenileme sonrası rafların güncellenmesi; yenileme hatası uyarısı.
4. Dizi detayı: sezon geçişi, tek sezonlu dizi, bölüm satırına her yerden dokunma, mini oynatıcıdayken sonraki bölüme geçiş.
5. "TV rehberini göster" kapat/aç; rehberi olmayan Xtream listesinde kartların yüksekliği.
6. Arama: Türkçe klavyeyle "film" / "FİLM", kapsam çubuğu, klavyenin kaydırmayla kapanması.
7. Ayarlar: yetişkin içerik sorusu, dil değişince Ayarlar'a dönüş, bağlantı kopup gelince hesap bloğunun toparlanması.
8. iPad: tek pencere (ikinci pencere açılmamalı), pencere boyutu değişince poster boyutları, işaretçiyle kart vurgusu.
9. VoiceOver ve büyük yazı boyutu: kartlar tek öğe, simge düğmeleri etiketli, detay posteri açılabiliyor.
10. Arapça arayüz: `›` işaretlerinin yönü, sayılar.

## 8. Çalışma ağacı

- Değişiklikler commit edilmedi. `apps/ios` altında 88 izlenen dosya değişti (+13.230 / −4.679 satır), 50'den fazla yeni dosya eklendi (çoğu test; uygulamada `Views/Components/Browse/*`, `XtreamFavoriteStore`, `NetworkStatus`, `ImageHostBreaker`, `EPGLineReservation`, `MockFixture+*`). `PlaylistTypeSelectionView.swift` silindi (artık kullanılmıyor).
- En çok değişenler: `SeriesView.swift`, `VODView.swift`, `LiveStreamsView.swift`, `M3UChannelsView.swift`, `PlaylistSettingsView.swift`, `SearchView.swift`, `PlaylistContentStore.swift`.
- Bahşiş özelliğine ait dosyalarına ve satırlarına dokunulmadı. Oynatıcı dosyalarına dokunulmadı.
- Proje dosyasında tek değişiklik: iPad tek pencere için `INFOPLIST_KEY_UIApplicationSceneManifest_Generation = NO` (iki yapılandırma) ve `App-Info.plist`'e sahne bildirimi.
- Uygulama yeni sabit metinler için on dilin hepsine çeviri aldı (`Localizable.strings` dosyalarının sonuna eklendi, mevcut anahtarlara dokunulmadı).
- Gözden geçirmek için yeterince büyük bir fark; bölüm 2 neye bakacağını sıralıyor.
