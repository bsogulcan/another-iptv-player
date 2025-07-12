// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for Turkish (`tr`).
class AppLocalizationsTr extends AppLocalizations {
  AppLocalizationsTr([String locale = 'tr']) : super(locale);

  @override
  String get slogan => 'Açık Kaynaklı IPTV Oynatıcı';

  @override
  String get search => 'Ara';

  @override
  String get search_live_stream => 'Canlı yayın ara';

  @override
  String get search_movie => 'Film ara';

  @override
  String get not_found_in_category => 'Bu kategoride içerik bulunamadı';

  @override
  String get live_stream_not_found => 'Canlı yayın bulunamadı';

  @override
  String get movie_not_found => 'Film bulunamadı';

  @override
  String get see_all => 'Tümünü Görüntüle';

  @override
  String get preview => 'Önizleme';

  @override
  String get info => 'Bilgi';

  @override
  String get close => 'Kapat';

  @override
  String get reset => 'Sıfırla';

  @override
  String get delete => 'Sil';

  @override
  String get cancel => 'İptal';

  @override
  String get history => 'Geçmiş';

  @override
  String get history_empty_message =>
      'Video izlemeye başladığınızda burada görünecek';

  @override
  String get live => 'Canlı';

  @override
  String get live_streams => 'Canlı Yayınlar';

  @override
  String get on_live => 'Canlı';

  @override
  String get other_channels => 'Diğer Kanallar';

  @override
  String get movies => 'Filmler';

  @override
  String get movie => 'Film';

  @override
  String get series_singular => 'Dizi';

  @override
  String get series_plural => 'Diziler';

  @override
  String get category_id => 'Kategori ID';

  @override
  String get channel_information => 'Kanal Bilgileri';

  @override
  String get channel_id => 'Kanal ID';

  @override
  String get series_id => 'Dizi ID';

  @override
  String get quality => 'Kalite';

  @override
  String get stream_type => 'Yayın Türü';

  @override
  String get format => 'Format';

  @override
  String get season => 'Sezonlar';

  @override
  String episode_count(Object count) {
    return '$count Bölüm';
  }

  @override
  String duration(Object duration) {
    return 'Süre: $duration';
  }

  @override
  String get episode_duration => 'Bölüm Süresi';

  @override
  String get creation_date => 'Eklenme Tarihi';

  @override
  String get release_date => 'Çıkış Tarihi';

  @override
  String get genre => 'Tür';

  @override
  String get cast => 'Oyuncular';

  @override
  String get description => 'Açıklama';

  @override
  String get video_track => 'Video Parçası';

  @override
  String get audio_track => 'Ses Parçası';

  @override
  String get subtitle_track => 'Altyazı Parçası';

  @override
  String get settings => 'Ayarlar';

  @override
  String get general_settings => 'Genel Ayarlar';

  @override
  String get app_language => 'Uygulama Dili';

  @override
  String get continue_on_background => 'Arka Planda Çalmaya Devam Et';

  @override
  String get continue_on_background_description =>
      'Uygulama arka planda olsa da oynatmaya devam et';

  @override
  String get refresh_contents => 'İçerikleri Yenile';

  @override
  String get subtitle_settings => 'Altyazı Ayarları';

  @override
  String get subtitle_settings_description => 'Altyazı görünümünü özelleştirin';

  @override
  String get sample_text => 'Örnek altyazı metni\nBu şekilde görünecek';

  @override
  String get font_settings => 'Yazı Tipi Ayarları';

  @override
  String get font_size => 'Yazı Tipi Boyutu';

  @override
  String get font_height => 'Satır Yüksekliği';

  @override
  String get letter_spacing => 'Harf Aralığı';

  @override
  String get word_spacing => 'Kelime Aralığı';

  @override
  String get padding => 'İç Boşluk';

  @override
  String get color_settings => 'Renk Ayarları';

  @override
  String get text_color => 'Metin Rengi';

  @override
  String get background_color => 'Arka Plan Rengi';

  @override
  String get style_settings => 'Stil Ayarları';

  @override
  String get font_weight => 'Yazı Tipi Kalınlığı';

  @override
  String get thin => 'İnce';

  @override
  String get normal => 'Normal';

  @override
  String get medium => 'Orta';

  @override
  String get bold => 'Kalın';

  @override
  String get extreme_bold => 'Çok Kalın';

  @override
  String get text_align => 'Metin Hizalama';

  @override
  String get left => 'Sol';

  @override
  String get center => 'Orta';

  @override
  String get right => 'Sağ';

  @override
  String get justify => 'Yasla';

  @override
  String get pick_color => 'Renk Seç';

  @override
  String get my_playlists => 'Playlistlerim';

  @override
  String get create_new_playlist => 'Yeni Playlist Oluştur';

  @override
  String get playlist_list => 'Playlist Listesi';

  @override
  String get playlist_information => 'Playlist Bilgileri';

  @override
  String get playlist_name => 'Playlist Adı';

  @override
  String playlist_deleted(Object name) {
    return '$name silindi';
  }

  @override
  String get playlist_delete_confirmation_title => 'Playlist\'i Sil';

  @override
  String playlist_delete_confirmation_message(Object name) {
    return '\'$name\' playlist\'ini silmek istediğinizden emin misiniz?\nBu işlem geri alınamaz.';
  }

  @override
  String get empty_playlist_title => 'Henüz Playlist Yok';

  @override
  String get empty_playlist_message =>
      'İlk playlist\'inizi oluşturarak başlayın.\nXtream Code veya M3U formatında\nplaylist ekleyebilirsiniz.';

  @override
  String get empty_playlist_button => 'İlk Playlist\'imi Oluştur';

  @override
  String get select_playlist_type => 'Playlist Türü Seçin';

  @override
  String get select_playlist_message =>
      'Oluşturmak istediğiniz playlist türünü seçin';

  @override
  String get xtream_code_title =>
      'API URL, Kullanıcı Adı ve Şifre ile bağlanın';

  @override
  String get xtream_code_description =>
      'IPTV sağlayıcınızdan aldığınız bilgilerle kolayca bağlanın';

  @override
  String get select_playlist_type_footer =>
      'Playlist bilgileriniz güvenli bir şekilde cihazınızda saklanır.';

  @override
  String get api_url => 'API URL';

  @override
  String get username => 'Kullanıcı Adı';

  @override
  String get username_placeholder => 'Kullanıcı adınızı girin';

  @override
  String get password => 'Parola';

  @override
  String get password_placeholder => 'Parolanızı girin';

  @override
  String get server_url => 'Sunucu URL';

  @override
  String get submit_create_playlist => 'Playlist\'i Kaydet';

  @override
  String get subscription_details => 'Abonelik Detayları';

  @override
  String subscription_remaining_day(Object days) {
    return 'Abonelik: $days gün';
  }

  @override
  String get remaining_day_title => 'Kalan Süre';

  @override
  String remaining_day(Object days) {
    return '$days Gün';
  }

  @override
  String get connected => 'Bağlı';

  @override
  String get active_connection => 'Aktif Bağlantı';

  @override
  String get maximum_connection => 'Maksimum Bağlantı';

  @override
  String get server_information => 'Sunucu Bilgileri';

  @override
  String get timezone => 'Saat Dilimi';

  @override
  String get server_message => 'Sunucu Mesajı';

  @override
  String get all_datas_are_stored_in_device =>
      'Tüm bilgiler güvenli bir şekilde cihazınızda saklanır';

  @override
  String get url_format_validate_message =>
      'URL formatı http://sunucu:port şeklinde olmalıdır';

  @override
  String get url_format_validate_error =>
      'Geçerli bir URL giriniz (http:// veya https:// ile başlamalı)';

  @override
  String get playlist_name_already_exists =>
      'Bu isimde bir playlist zaten mevcut';

  @override
  String get invalid_credentials =>
      'IPTV sağlayıcınızdan cevap alınamadı, bilgilerinizi kontrol edin';

  @override
  String get error_occured => 'Hata oluştu';

  @override
  String get connecting => 'Bağlantı kuruluyor';

  @override
  String get preparing_categories => 'Kategoriler hazırlanıyor';

  @override
  String preparing_categories_exception(Object error) {
    return 'Kategoriler yüklenemedi: $error';
  }

  @override
  String get preparing_live_streams => 'Canlı kanallar yükleniyor';

  @override
  String get preparing_live_streams_exception_1 => 'Canlı kanallar alınamadı';

  @override
  String preparing_live_streams_exception_2(Object error) {
    return 'Canlı kanallar yüklenirken hata: $error';
  }

  @override
  String get preparing_movies => 'Film kütüphanesi açılıyor';

  @override
  String get preparing_movies_exception_1 => 'Filmler alınamadı';

  @override
  String preparing_movies_exception_2(Object error) {
    return 'Filmler yüklenirken hata: $error';
  }

  @override
  String get preparing_series => 'Dizi arşivi hazırlanıyor';

  @override
  String get preparing_series_exception_1 => 'Diziler alınamadı';

  @override
  String preparing_series_exception_2(Object error) {
    return 'Diziler yüklenirken hata: $error';
  }

  @override
  String get preparing_user_info_exception_1 => 'Kullanıcı bilgileri alınamadı';

  @override
  String preparing_user_info_exception_2(Object error) {
    return 'Kullanıcı bilgileri yüklenirken hata: $error';
  }
}
