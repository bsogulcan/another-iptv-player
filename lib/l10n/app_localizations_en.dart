// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for English (`en`).
class AppLocalizationsEn extends AppLocalizations {
  AppLocalizationsEn([String locale = 'en']) : super(locale);

  @override
  String get slogan => 'Open Source IPTV Player';

  @override
  String get search => 'Search';

  @override
  String get search_live_stream => 'Search live stream';

  @override
  String get search_movie => 'Search movie';

  @override
  String get not_found_in_category => 'No content found in this category';

  @override
  String get live_stream_not_found => 'No live stream found';

  @override
  String get movie_not_found => 'No movie found';

  @override
  String get see_all => 'View All';

  @override
  String get preview => 'Preview';

  @override
  String get info => 'Info';

  @override
  String get close => 'Close';

  @override
  String get reset => 'Reset';

  @override
  String get delete => 'Delete';

  @override
  String get cancel => 'Cancel';

  @override
  String get history => 'History';

  @override
  String get history_empty_message => 'Your watched videos will appear here';

  @override
  String get live => 'Live';

  @override
  String get live_streams => 'Live Streams';

  @override
  String get on_live => 'Live';

  @override
  String get other_channels => 'Other Channels';

  @override
  String get movies => 'Movies';

  @override
  String get movie => 'Movie';

  @override
  String get series_singular => 'Series';

  @override
  String get series_plural => 'Series';

  @override
  String get category_id => 'Category ID';

  @override
  String get channel_information => 'Channel Information';

  @override
  String get channel_id => 'Channel ID';

  @override
  String get series_id => 'Series ID';

  @override
  String get quality => 'Quality';

  @override
  String get stream_type => 'Stream Type';

  @override
  String get format => 'Format';

  @override
  String get season => 'Seasons';

  @override
  String episode_count(Object count) {
    return '$count Episodes';
  }

  @override
  String duration(Object duration) {
    return 'Duration: $duration';
  }

  @override
  String get episode_duration => 'Episode Duration';

  @override
  String get creation_date => 'Added Date';

  @override
  String get release_date => 'Release Date';

  @override
  String get genre => 'Genre';

  @override
  String get cast => 'Cast';

  @override
  String get description => 'Description';

  @override
  String get video_track => 'Video Track';

  @override
  String get audio_track => 'Audio Track';

  @override
  String get subtitle_track => 'Subtitle Track';

  @override
  String get settings => 'Settings';

  @override
  String get general_settings => 'General Settings';

  @override
  String get app_language => 'App Language';

  @override
  String get continue_on_background => 'Continue Playing in Background';

  @override
  String get continue_on_background_description =>
      'Keep playing even when app is in the background';

  @override
  String get refresh_contents => 'Refresh Content';

  @override
  String get subtitle_settings => 'Subtitle Settings';

  @override
  String get subtitle_settings_description => 'Customize subtitle appearance';

  @override
  String get sample_text => 'Sample subtitle text\nIt will look like this';

  @override
  String get font_settings => 'Font Settings';

  @override
  String get font_size => 'Font Size';

  @override
  String get font_height => 'Line Height';

  @override
  String get letter_spacing => 'Letter Spacing';

  @override
  String get word_spacing => 'Word Spacing';

  @override
  String get padding => 'Padding';

  @override
  String get color_settings => 'Color Settings';

  @override
  String get text_color => 'Text Color';

  @override
  String get background_color => 'Background Color';

  @override
  String get style_settings => 'Style Settings';

  @override
  String get font_weight => 'Font Weight';

  @override
  String get thin => 'Thin';

  @override
  String get normal => 'Normal';

  @override
  String get medium => 'Medium';

  @override
  String get bold => 'Bold';

  @override
  String get extreme_bold => 'Extra Bold';

  @override
  String get text_align => 'Text Alignment';

  @override
  String get left => 'Left';

  @override
  String get center => 'Center';

  @override
  String get right => 'Right';

  @override
  String get justify => 'Justify';

  @override
  String get pick_color => 'Pick Color';

  @override
  String get my_playlists => 'My Playlists';

  @override
  String get create_new_playlist => 'Create New Playlist';

  @override
  String get playlist_list => 'Playlist List';

  @override
  String get playlist_information => 'Playlist Information';

  @override
  String get playlist_name => 'Playlist Name';

  @override
  String playlist_deleted(Object name) {
    return '$name deleted';
  }

  @override
  String get playlist_delete_confirmation_title => 'Delete Playlist';

  @override
  String playlist_delete_confirmation_message(Object name) {
    return 'Are you sure you want to delete the playlist \'$name\'?\nThis action cannot be undone.';
  }

  @override
  String get empty_playlist_title => 'No Playlist Yet';

  @override
  String get empty_playlist_message =>
      'Start by creating your first playlist.\nYou can add playlists in Xtream Code or M3U format.';

  @override
  String get empty_playlist_button => 'Create My First Playlist';

  @override
  String get select_playlist_type => 'Select Playlist Type';

  @override
  String get select_playlist_message =>
      'Choose the type of playlist you want to create';

  @override
  String get xtream_code_title =>
      'Connect with API URL, Username, and Password';

  @override
  String get xtream_code_description =>
      'Easily connect with information from your IPTV provider';

  @override
  String get select_playlist_type_footer =>
      'Your playlist information is securely stored on your device.';

  @override
  String get api_url => 'API URL';

  @override
  String get username => 'Username';

  @override
  String get username_placeholder => 'Enter your username';

  @override
  String get password => 'Password';

  @override
  String get password_placeholder => 'Enter your password';

  @override
  String get server_url => 'Server URL';

  @override
  String get submit_create_playlist => 'Save Playlist';

  @override
  String get subscription_details => 'Subscription Details';

  @override
  String subscription_remaining_day(Object days) {
    return 'Subscription: $days days';
  }

  @override
  String get remaining_day_title => 'Time Remaining';

  @override
  String remaining_day(Object days) {
    return '$days Days';
  }

  @override
  String get connected => 'Connected';

  @override
  String get active_connection => 'Active Connection';

  @override
  String get maximum_connection => 'Maximum Connection';

  @override
  String get server_information => 'Server Information';

  @override
  String get timezone => 'Time Zone';

  @override
  String get server_message => 'Server Message';

  @override
  String get all_datas_are_stored_in_device =>
      'All data is securely stored on your device';

  @override
  String get url_format_validate_message =>
      'URL format should be like http://server:port';

  @override
  String get url_format_validate_error =>
      'Please enter a valid URL (must start with http:// or https://)';

  @override
  String get playlist_name_already_exists =>
      'A playlist with this name already exists';

  @override
  String get invalid_credentials =>
      'Could not get a response from your IPTV provider, please check your information';

  @override
  String get error_occured => 'An error occurred';

  @override
  String get connecting => 'Connecting';

  @override
  String get preparing_categories => 'Preparing categories';

  @override
  String preparing_categories_exception(Object error) {
    return 'Could not load categories: $error';
  }

  @override
  String get preparing_live_streams => 'Loading live channels';

  @override
  String get preparing_live_streams_exception_1 =>
      'Could not get live channels';

  @override
  String preparing_live_streams_exception_2(Object error) {
    return 'Error loading live channels: $error';
  }

  @override
  String get preparing_movies => 'Opening movie library';

  @override
  String get preparing_movies_exception_1 => 'Could not get movies';

  @override
  String preparing_movies_exception_2(Object error) {
    return 'Error loading movies: $error';
  }

  @override
  String get preparing_series => 'Preparing series library';

  @override
  String get preparing_series_exception_1 => 'Could not get series';

  @override
  String preparing_series_exception_2(Object error) {
    return 'Error loading series: $error';
  }

  @override
  String get preparing_user_info_exception_1 =>
      'Could not get user information';

  @override
  String preparing_user_info_exception_2(Object error) {
    return 'Error loading user information: $error';
  }
}
