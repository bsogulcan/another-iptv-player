// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for German (`de`).
class AppLocalizationsDe extends AppLocalizations {
  AppLocalizationsDe([String locale = 'de']) : super(locale);

  @override
  String get slogan => 'Open Source IPTV Player';

  @override
  String get search => 'Suchen';

  @override
  String get search_live_stream => 'Live-Stream suchen';

  @override
  String get search_movie => 'Film suchen';

  @override
  String get search_series => 'Serie suchen';

  @override
  String get not_found_in_category =>
      'Kein Inhalt in dieser Kategorie gefunden';

  @override
  String get live_stream_not_found => 'Kein Live-Stream gefunden';

  @override
  String get movie_not_found => 'Kein Film gefunden';

  @override
  String get see_all => 'Alle Anzeigen';

  @override
  String get preview => 'Vorschau';

  @override
  String get info => 'Info';

  @override
  String get close => 'Schließen';

  @override
  String get reset => 'Zurücksetzen';

  @override
  String get delete => 'Löschen';

  @override
  String get cancel => 'Abbrechen';

  @override
  String get refresh => 'Aktualisieren';

  @override
  String get back => 'Zurück';

  @override
  String get clear => 'Löschen';

  @override
  String get clear_all => 'Alle Löschen';

  @override
  String get day => 'Tag';

  @override
  String get clear_all_confirmation_message =>
      'Sind Sie sicher, dass Sie die gesamte Verlaufsliste löschen möchten?';

  @override
  String get try_again => 'Erneut Versuchen';

  @override
  String get history => 'Verlauf';

  @override
  String get history_empty_message =>
      'Ihre angesehenen Videos werden hier angezeigt';

  @override
  String get live => 'Live';

  @override
  String get live_streams => 'Live-Streams';

  @override
  String get on_live => 'Live';

  @override
  String get other_channels => 'Andere Kanäle';

  @override
  String get movies => 'Filme';

  @override
  String get movie => 'Film';

  @override
  String get series_singular => 'Serie';

  @override
  String get series_plural => 'Serien';

  @override
  String get category_id => 'Kategorie-ID';

  @override
  String get channel_information => 'Kanal-Informationen';

  @override
  String get channel_id => 'Kanal-ID';

  @override
  String get series_id => 'Serien-ID';

  @override
  String get quality => 'Qualität';

  @override
  String get stream_type => 'Stream-Typ';

  @override
  String get format => 'Format';

  @override
  String get season => 'Staffeln';

  @override
  String episode_count(Object count) {
    return '$count Episoden';
  }

  @override
  String duration(Object duration) {
    return 'Dauer: $duration';
  }

  @override
  String get episode_duration => 'Episoden-Dauer';

  @override
  String get creation_date => 'Hinzugefügt am';

  @override
  String get release_date => 'Erscheinungsdatum';

  @override
  String get genre => 'Genre';

  @override
  String get cast => 'Besetzung';

  @override
  String get description => 'Beschreibung';

  @override
  String get video_track => 'Video-Spur';

  @override
  String get audio_track => 'Audio-Spur';

  @override
  String get subtitle_track => 'Untertitel-Spur';

  @override
  String get settings => 'Einstellungen';

  @override
  String get general_settings => 'Allgemeine Einstellungen';

  @override
  String get app_language => 'App-Sprache';

  @override
  String get continue_on_background => 'Im Hintergrund Weiterspielen';

  @override
  String get continue_on_background_description =>
      'Wiedergabe fortsetzen, auch wenn die App im Hintergrund ist';

  @override
  String get refresh_contents => 'Inhalte Aktualisieren';

  @override
  String get subtitle_settings => 'Untertitel-Einstellungen';

  @override
  String get subtitle_settings_description => 'Untertitel-Darstellung anpassen';

  @override
  String get sample_text => 'Beispiel-Untertiteltext\nSo wird es aussehen';

  @override
  String get font_settings => 'Schriftart-Einstellungen';

  @override
  String get font_size => 'Schriftgröße';

  @override
  String get font_height => 'Zeilenhöhe';

  @override
  String get letter_spacing => 'Buchstabenabstand';

  @override
  String get word_spacing => 'Wortabstand';

  @override
  String get padding => 'Innenabstand';

  @override
  String get color_settings => 'Farb-Einstellungen';

  @override
  String get text_color => 'Textfarbe';

  @override
  String get background_color => 'Hintergrundfarbe';

  @override
  String get style_settings => 'Stil-Einstellungen';

  @override
  String get font_weight => 'Schriftstärke';

  @override
  String get thin => 'Dünn';

  @override
  String get normal => 'Normal';

  @override
  String get medium => 'Mittel';

  @override
  String get bold => 'Fett';

  @override
  String get extreme_bold => 'Extra Fett';

  @override
  String get text_align => 'Textausrichtung';

  @override
  String get left => 'Links';

  @override
  String get center => 'Mitte';

  @override
  String get right => 'Rechts';

  @override
  String get justify => 'Blocksatz';

  @override
  String get pick_color => 'Farbe Wählen';

  @override
  String get my_playlists => 'Meine Wiedergabelisten';

  @override
  String get create_new_playlist => 'Neue Wiedergabeliste Erstellen';

  @override
  String get loading_playlists => 'Wiedergabelisten Werden Geladen...';

  @override
  String get playlist_list => 'Wiedergabeliste';

  @override
  String get playlist_information => 'Wiedergabelisten-Informationen';

  @override
  String get playlist_name => 'Name der Wiedergabeliste';

  @override
  String get playlist_name_placeholder =>
      'Namen für Ihre Wiedergabeliste eingeben';

  @override
  String get playlist_name_required =>
      'Name der Wiedergabeliste ist erforderlich';

  @override
  String get playlist_name_min_2 =>
      'Der Name sollte mindestens 2 Zeichen haben';

  @override
  String playlist_deleted(Object name) {
    return '$name gelöscht';
  }

  @override
  String get playlist_delete_confirmation_title => 'Wiedergabeliste Löschen';

  @override
  String playlist_delete_confirmation_message(Object name) {
    return 'Sind Sie sicher, dass Sie die Wiedergabeliste \'$name\' löschen möchten?\nDiese Aktion kann nicht rückgängig gemacht werden.';
  }

  @override
  String get empty_playlist_title => 'Noch Keine Wiedergabeliste';

  @override
  String get empty_playlist_message =>
      'Beginnen Sie mit der Erstellung Ihrer ersten Wiedergabeliste.\nSie können Wiedergabelisten im Xtream Code oder M3U Format hinzufügen.';

  @override
  String get empty_playlist_button => 'Meine Erste Wiedergabeliste Erstellen';

  @override
  String get select_playlist_type => 'Wiedergabelisten-Typ Auswählen';

  @override
  String get select_playlist_message =>
      'Wählen Sie den Typ der Wiedergabeliste, die Sie erstellen möchten';

  @override
  String get xtream_code_title =>
      'Mit API-URL, Benutzername und Passwort verbinden';

  @override
  String get xtream_code_description =>
      'Einfach mit den Informationen Ihres IPTV-Anbieters verbinden';

  @override
  String get select_playlist_type_footer =>
      'Ihre Wiedergabelisten-Informationen werden sicher auf Ihrem Gerät gespeichert.';

  @override
  String get api_url => 'API-URL';

  @override
  String get api_url_required => 'API-URL erforderlich';

  @override
  String get username => 'Benutzername';

  @override
  String get username_placeholder => 'Benutzername eingeben';

  @override
  String get username_required => 'Benutzername ist erforderlich';

  @override
  String get username_min_3 => 'Benutzername sollte mindestens 3 Zeichen haben';

  @override
  String get password => 'Passwort';

  @override
  String get password_placeholder => 'Passwort eingeben';

  @override
  String get password_required => 'Passwort ist erforderlich';

  @override
  String get password_min_3 => 'Passwort sollte mindestens 3 Zeichen haben';

  @override
  String get server_url => 'Server-URL';

  @override
  String get submitting => 'Wird Gespeichert...';

  @override
  String get submit_create_playlist => 'Wiedergabeliste Speichern';

  @override
  String get subscription_details => 'Abonnement-Details';

  @override
  String subscription_remaining_day(Object days) {
    return 'Abonnement: $days';
  }

  @override
  String get remaining_day_title => 'Verbleibende Zeit';

  @override
  String remaining_day(Object days) {
    return '$days Tage';
  }

  @override
  String get connected => 'Verbunden';

  @override
  String get no_connection => 'Keine Verbindung';

  @override
  String get expired => 'Abgelaufen';

  @override
  String get active_connection => 'Aktive Verbindung';

  @override
  String get maximum_connection => 'Maximale Verbindung';

  @override
  String get server_information => 'Server-Informationen';

  @override
  String get timezone => 'Zeitzone';

  @override
  String get server_message => 'Server-Nachricht';

  @override
  String get all_datas_are_stored_in_device =>
      'Alle Daten werden sicher auf Ihrem Gerät gespeichert';

  @override
  String get url_format_validate_message =>
      'URL-Format sollte wie http://server:port sein';

  @override
  String get url_format_validate_error =>
      'Bitte geben Sie eine gültige URL ein (muss mit http:// oder https:// beginnen)';

  @override
  String get playlist_name_already_exists =>
      'Eine Wiedergabeliste mit diesem Namen existiert bereits';

  @override
  String get invalid_credentials =>
      'Keine Antwort von Ihrem IPTV-Anbieter erhalten, bitte überprüfen Sie Ihre Informationen';

  @override
  String get error_occurred => 'Ein Fehler ist aufgetreten';

  @override
  String get connecting => 'Verbindung wird hergestellt';

  @override
  String get preparing_categories => 'Kategorien werden vorbereitet';

  @override
  String preparing_categories_exception(Object error) {
    return 'Kategorien konnten nicht geladen werden: $error';
  }

  @override
  String get preparing_live_streams => 'Live-Kanäle werden geladen';

  @override
  String get preparing_live_streams_exception_1 =>
      'Live-Kanäle konnten nicht abgerufen werden';

  @override
  String preparing_live_streams_exception_2(Object error) {
    return 'Fehler beim Laden der Live-Kanäle: $error';
  }

  @override
  String get preparing_movies => 'Film-Bibliothek wird geöffnet';

  @override
  String get preparing_movies_exception_1 =>
      'Filme konnten nicht abgerufen werden';

  @override
  String preparing_movies_exception_2(Object error) {
    return 'Fehler beim Laden der Filme: $error';
  }

  @override
  String get preparing_series => 'Serien-Bibliothek wird vorbereitet';

  @override
  String get preparing_series_exception_1 =>
      'Serien konnten nicht abgerufen werden';

  @override
  String preparing_series_exception_2(Object error) {
    return 'Fehler beim Laden der Serien: $error';
  }

  @override
  String get preparing_user_info_exception_1 =>
      'Benutzerinformationen konnten nicht abgerufen werden';

  @override
  String preparing_user_info_exception_2(Object error) {
    return 'Fehler beim Laden der Benutzerinformationen: $error';
  }

  @override
  String get m3u_playlist_title => 'Playlist mit M3U-Datei oder URL hinzufügen';

  @override
  String get m3u_playlist_description =>
      'Unterstützt traditionelle M3U-Formatdateien';

  @override
  String get m3u_playlist => 'M3U-Playlist';

  @override
  String get m3u_playlist_load_description =>
      'IPTV-Kanäle mit M3U-Playlist-Datei oder URL laden';

  @override
  String get playlist_name_hint => 'Playlist-Namen eingeben';

  @override
  String get playlist_name_min_length =>
      'Playlist-Name muss mindestens 2 Zeichen haben';

  @override
  String get source_type => 'Quellentyp';

  @override
  String get url => 'URL';

  @override
  String get file => 'Datei';

  @override
  String get m3u_url => 'M3U-URL';

  @override
  String get m3u_url_hint => 'http://example.com/playlist.m3u';

  @override
  String get m3u_url_required => 'M3U-URL ist erforderlich';

  @override
  String get url_format_error => 'Gültiges URL-Format eingeben';

  @override
  String get url_scheme_error => 'URL muss mit http:// oder https:// beginnen';

  @override
  String get m3u_file => 'M3U-Datei';

  @override
  String get file_selected => 'Datei ausgewählt';

  @override
  String get select_m3u_file => 'M3U-Datei auswählen (.m3u, .m3u8)';

  @override
  String get please_select_m3u_file => 'Bitte eine M3U-Datei auswählen';

  @override
  String get file_selection_error => 'Fehler beim Auswählen der Datei';

  @override
  String get processing => 'Verarbeitung läuft...';

  @override
  String get create_playlist => 'Playlist erstellen';

  @override
  String get error_occurred_title => 'Fehler aufgetreten';

  @override
  String get m3u_info_message =>
      'Alle Daten werden sicher auf Ihrem Gerät gespeichert.\nUnterstützte Formate: .m3u, .m3u8\nURL-Format: Muss mit http:// oder https:// beginnen';

  @override
  String get m3u_parse_error => 'M3U-Parsing-Fehler';

  @override
  String get loading_m3u => 'M3U wird geladen';

  @override
  String get preparing_m3u_exception_no_source => 'Keine M3U-Quelle gefunden';

  @override
  String get preparing_m3u_exception_empty => 'M3U-Datei ist leer';

  @override
  String preparing_m3u_exception_parse(Object error) {
    return 'M3U-Parsing-Fehler: $error';
  }

  @override
  String get not_categorized => 'Nicht kategorisiert';

  @override
  String get loading_lists => 'Listen werden geladen...';

  @override
  String get all => 'Alle';

  @override
  String iptv_channels_count(Object count) {
    return 'IPTV-Kanäle ($count)';
  }

  @override
  String get unknown_channel => 'Unbekannter Kanal';

  @override
  String get live_content => 'LIVE';

  @override
  String get movie_content => 'FILM';

  @override
  String get series_content => 'SERIE';

  @override
  String get media_content => 'MEDIEN';

  @override
  String get m3u_error => 'M3U-Fehler';

  @override
  String get episode_short => 'Folge';

  @override
  String season_number(Object number) {
    return '$number. Staffel';
  }

  @override
  String get image_loading => 'Bild wird geladen...';

  @override
  String get image_not_found => 'Bild nicht gefunden';
}
