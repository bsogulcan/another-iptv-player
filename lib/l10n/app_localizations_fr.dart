// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for French (`fr`).
class AppLocalizationsFr extends AppLocalizations {
  AppLocalizationsFr([String locale = 'fr']) : super(locale);

  @override
  String get slogan => 'Lecteur IPTV Open Source';

  @override
  String get search => 'Rechercher';

  @override
  String get search_live_stream => 'Rechercher un direct';

  @override
  String get search_movie => 'Rechercher un film';

  @override
  String get search_series => 'Rechercher une série';

  @override
  String get not_found_in_category =>
      'Aucun contenu trouvé dans cette catégorie';

  @override
  String get live_stream_not_found => 'Aucun direct trouvé';

  @override
  String get movie_not_found => 'Aucun film trouvé';

  @override
  String get see_all => 'Voir tout';

  @override
  String get preview => 'Aperçu';

  @override
  String get info => 'Informations';

  @override
  String get close => 'Fermer';

  @override
  String get reset => 'Réinitialiser';

  @override
  String get delete => 'Supprimer';

  @override
  String get cancel => 'Annuler';

  @override
  String get refresh => 'Actualiser';

  @override
  String get back => 'Retour';

  @override
  String get clear => 'Effacer';

  @override
  String get clear_all => 'Tout effacer';

  @override
  String get day => 'Jour';

  @override
  String get clear_all_confirmation_message =>
      'Êtes-vous sûr de vouloir supprimer tout l\'historique ?';

  @override
  String get try_again => 'Réessayer';

  @override
  String get history => 'Historique';

  @override
  String get history_empty_message => 'Vos vidéos regardées apparaîtront ici';

  @override
  String get live => 'Direct';

  @override
  String get live_streams => 'Diffusions en direct';

  @override
  String get on_live => 'En direct';

  @override
  String get other_channels => 'Autres chaînes';

  @override
  String get movies => 'Films';

  @override
  String get movie => 'Film';

  @override
  String get series_singular => 'Série';

  @override
  String get series_plural => 'Séries';

  @override
  String get category_id => 'ID de catégorie';

  @override
  String get channel_information => 'Informations de la chaîne';

  @override
  String get channel_id => 'ID de la chaîne';

  @override
  String get series_id => 'ID de la série';

  @override
  String get quality => 'Qualité';

  @override
  String get stream_type => 'Type de flux';

  @override
  String get format => 'Format';

  @override
  String get season => 'Saisons';

  @override
  String episode_count(Object count) {
    return '$count épisodes';
  }

  @override
  String duration(Object duration) {
    return 'Durée : $duration';
  }

  @override
  String get episode_duration => 'Durée de l\'épisode';

  @override
  String get creation_date => 'Date d\'ajout';

  @override
  String get release_date => 'Date de sortie';

  @override
  String get genre => 'Genre';

  @override
  String get cast => 'Distribution';

  @override
  String get description => 'Description';

  @override
  String get video_track => 'Piste vidéo';

  @override
  String get audio_track => 'Piste audio';

  @override
  String get subtitle_track => 'Piste de sous-titres';

  @override
  String get settings => 'Paramètres';

  @override
  String get general_settings => 'Paramètres généraux';

  @override
  String get app_language => 'Langue de l\'application';

  @override
  String get continue_on_background => 'Continuer la lecture en arrière-plan';

  @override
  String get continue_on_background_description =>
      'Continuer la lecture même quand l\'app est en arrière-plan';

  @override
  String get refresh_contents => 'Actualiser le contenu';

  @override
  String get subtitle_settings => 'Paramètres des sous-titres';

  @override
  String get subtitle_settings_description =>
      'Personnaliser l\'apparence des sous-titres';

  @override
  String get sample_text =>
      'Exemple de texte de sous-titre\nCela ressemblera à ceci';

  @override
  String get font_settings => 'Paramètres de police';

  @override
  String get font_size => 'Taille de police';

  @override
  String get font_height => 'Hauteur de ligne';

  @override
  String get letter_spacing => 'Espacement des lettres';

  @override
  String get word_spacing => 'Espacement des mots';

  @override
  String get padding => 'Espacement interne';

  @override
  String get color_settings => 'Paramètres de couleur';

  @override
  String get text_color => 'Couleur du texte';

  @override
  String get background_color => 'Couleur d\'arrière-plan';

  @override
  String get style_settings => 'Paramètres de style';

  @override
  String get font_weight => 'Épaisseur de police';

  @override
  String get thin => 'Fin';

  @override
  String get normal => 'Normal';

  @override
  String get medium => 'Moyen';

  @override
  String get bold => 'Gras';

  @override
  String get extreme_bold => 'Extra gras';

  @override
  String get text_align => 'Alignement du texte';

  @override
  String get left => 'Gauche';

  @override
  String get center => 'Centre';

  @override
  String get right => 'Droite';

  @override
  String get justify => 'Justifié';

  @override
  String get pick_color => 'Choisir une couleur';

  @override
  String get my_playlists => 'Mes listes de lecture';

  @override
  String get create_new_playlist => 'Créer une nouvelle liste';

  @override
  String get loading_playlists => 'Chargement des listes...';

  @override
  String get playlist_list => 'Liste de lecture';

  @override
  String get playlist_information => 'Informations de la liste';

  @override
  String get playlist_name => 'Nom de la liste';

  @override
  String get playlist_name_placeholder => 'Entrez un nom pour votre liste';

  @override
  String get playlist_name_required => 'Le nom de la liste est requis';

  @override
  String get playlist_name_min_2 =>
      'Le nom doit contenir au moins 2 caractères';

  @override
  String playlist_deleted(Object name) {
    return '$name supprimée';
  }

  @override
  String get playlist_delete_confirmation_title => 'Supprimer la liste';

  @override
  String playlist_delete_confirmation_message(Object name) {
    return 'Êtes-vous sûr de vouloir supprimer la liste \'$name\' ?\nCette action ne peut pas être annulée.';
  }

  @override
  String get empty_playlist_title => 'Aucune liste pour le moment';

  @override
  String get empty_playlist_message =>
      'Commencez par créer votre première liste de lecture.\nVous pouvez ajouter des listes au format Xtream Code ou M3U.';

  @override
  String get empty_playlist_button => 'Créer ma première liste';

  @override
  String get select_playlist_type => 'Sélectionner le type de liste';

  @override
  String get select_playlist_message =>
      'Choisissez le type de liste que vous voulez créer';

  @override
  String get xtream_code_title =>
      'Se connecter avec l\'URL API, nom d\'utilisateur et mot de passe';

  @override
  String get xtream_code_description =>
      'Connectez-vous facilement avec les informations de votre fournisseur IPTV';

  @override
  String get select_playlist_type_footer =>
      'Les informations de votre liste sont stockées en sécurité sur votre appareil.';

  @override
  String get api_url => 'URL de l\'API';

  @override
  String get api_url_required => 'URL de l\'API requise';

  @override
  String get username => 'Nom d\'utilisateur';

  @override
  String get username_placeholder => 'Entrez votre nom d\'utilisateur';

  @override
  String get username_required => 'Nom d\'utilisateur requis';

  @override
  String get username_min_3 =>
      'Le nom d\'utilisateur doit contenir au moins 3 caractères';

  @override
  String get password => 'Mot de passe';

  @override
  String get password_placeholder => 'Entrez votre mot de passe';

  @override
  String get password_required => 'Mot de passe requis';

  @override
  String get password_min_3 =>
      'Le mot de passe doit contenir au moins 3 caractères';

  @override
  String get server_url => 'URL du serveur';

  @override
  String get submitting => 'Sauvegarde...';

  @override
  String get submit_create_playlist => 'Sauvegarder la liste';

  @override
  String get subscription_details => 'Détails de l\'abonnement';

  @override
  String subscription_remaining_day(Object days) {
    return 'Abonnement : $days';
  }

  @override
  String get remaining_day_title => 'Temps restant';

  @override
  String remaining_day(Object days) {
    return '$days jours';
  }

  @override
  String get connected => 'Connecté';

  @override
  String get no_connection => 'Pas de connexion';

  @override
  String get expired => 'Expiré';

  @override
  String get active_connection => 'Connexion active';

  @override
  String get maximum_connection => 'Connexion maximale';

  @override
  String get server_information => 'Informations du serveur';

  @override
  String get timezone => 'Fuseau horaire';

  @override
  String get server_message => 'Message du serveur';

  @override
  String get all_datas_are_stored_in_device =>
      'Toutes les données sont stockées en sécurité sur votre appareil';

  @override
  String get url_format_validate_message =>
      'Le format de l\'URL doit être comme http://serveur:port';

  @override
  String get url_format_validate_error =>
      'Veuillez entrer une URL valide (doit commencer par http:// ou https://)';

  @override
  String get playlist_name_already_exists =>
      'Une liste avec ce nom existe déjà';

  @override
  String get invalid_credentials =>
      'Impossible d\'obtenir une réponse de votre fournisseur IPTV, vérifiez vos informations';

  @override
  String get error_occurred => 'Une erreur s\'est produite';

  @override
  String get connecting => 'Connexion en cours';

  @override
  String get preparing_categories => 'Préparation des catégories';

  @override
  String preparing_categories_exception(Object error) {
    return 'Impossible de charger les catégories : $error';
  }

  @override
  String get preparing_live_streams => 'Chargement des chaînes en direct';

  @override
  String get preparing_live_streams_exception_1 =>
      'Impossible d\'obtenir les chaînes en direct';

  @override
  String preparing_live_streams_exception_2(Object error) {
    return 'Erreur lors du chargement des chaînes en direct : $error';
  }

  @override
  String get preparing_movies => 'Ouverture de la bibliothèque de films';

  @override
  String get preparing_movies_exception_1 => 'Impossible d\'obtenir les films';

  @override
  String preparing_movies_exception_2(Object error) {
    return 'Erreur lors du chargement des films : $error';
  }

  @override
  String get preparing_series => 'Préparation de la bibliothèque de séries';

  @override
  String get preparing_series_exception_1 => 'Impossible d\'obtenir les séries';

  @override
  String preparing_series_exception_2(Object error) {
    return 'Erreur lors du chargement des séries : $error';
  }

  @override
  String get preparing_user_info_exception_1 =>
      'Impossible d\'obtenir les informations utilisateur';

  @override
  String preparing_user_info_exception_2(Object error) {
    return 'Erreur lors du chargement des informations utilisateur : $error';
  }

  @override
  String get m3u_playlist_title =>
      'Ajouter une playlist avec un fichier M3U ou une URL';

  @override
  String get m3u_playlist_description =>
      'Prend en charge les fichiers au format M3U traditionnel';

  @override
  String get m3u_playlist => 'Playlist M3U';

  @override
  String get m3u_playlist_load_description =>
      'Charger les chaînes IPTV avec un fichier de playlist M3U ou une URL';

  @override
  String get playlist_name_hint => 'Entrez le nom de la playlist';

  @override
  String get playlist_name_min_length =>
      'Le nom de la playlist doit comporter au moins 2 caractères';

  @override
  String get source_type => 'Type de source';

  @override
  String get url => 'URL';

  @override
  String get file => 'Fichier';

  @override
  String get m3u_url => 'URL M3U';

  @override
  String get m3u_url_hint => 'http://example.com/playlist.m3u';

  @override
  String get m3u_url_required => 'L\'URL M3U est requise';

  @override
  String get url_format_error => 'Entrez un format d\'URL valide';

  @override
  String get url_scheme_error =>
      'L\'URL doit commencer par http:// ou https://';

  @override
  String get m3u_file => 'Fichier M3U';

  @override
  String get file_selected => 'Fichier sélectionné';

  @override
  String get select_m3u_file => 'Sélectionner un fichier M3U (.m3u, .m3u8)';

  @override
  String get please_select_m3u_file => 'Veuillez sélectionner un fichier M3U';

  @override
  String get file_selection_error => 'Erreur lors de la sélection du fichier';

  @override
  String get processing => 'Traitement en cours...';

  @override
  String get create_playlist => 'Créer une playlist';

  @override
  String get error_occurred_title => 'Erreur survenue';

  @override
  String get m3u_info_message =>
      'Toutes les données sont stockées en toute sécurité sur votre appareil.\nFormats pris en charge : .m3u, .m3u8\nFormat d\'URL : Doit commencer par http:// ou https://';

  @override
  String get m3u_parse_error => 'Erreur d\'analyse M3U';

  @override
  String get loading_m3u => 'Chargement M3U';

  @override
  String get preparing_m3u_exception_no_source => 'Aucune source M3U trouvée';

  @override
  String get preparing_m3u_exception_empty => 'Le fichier M3U est vide';

  @override
  String preparing_m3u_exception_parse(Object error) {
    return 'Erreur d\'analyse M3U : $error';
  }

  @override
  String get not_categorized => 'Non catégorisé';

  @override
  String get loading_lists => 'Chargement des listes...';

  @override
  String get all => 'Tous';

  @override
  String iptv_channels_count(Object count) {
    return 'Chaînes IPTV ($count)';
  }

  @override
  String get unknown_channel => 'Chaîne inconnue';

  @override
  String get live_content => 'EN DIRECT';

  @override
  String get movie_content => 'FILM';

  @override
  String get series_content => 'SÉRIE';

  @override
  String get media_content => 'MÉDIA';

  @override
  String get m3u_error => 'Erreur M3U';

  @override
  String get episode_short => 'Ép';

  @override
  String season_number(Object number) {
    return 'Saison $number';
  }

  @override
  String get image_loading => 'Chargement de l\'image...';

  @override
  String get image_not_found => 'Image non trouvée';
}
