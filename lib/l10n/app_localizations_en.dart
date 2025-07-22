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
  String get search_series => 'Search series';

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
  String get refresh => 'Refresh';

  @override
  String get back => 'Back';

  @override
  String get clear => 'Clear';

  @override
  String get clear_all => 'Clear All';

  @override
  String get day => 'Day';

  @override
  String get clear_all_confirmation_message =>
      'Are you sure want to delete all history?';

  @override
  String get try_again => 'Try Again';

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
  String get loading_playlists => 'Loading Playlists...';

  @override
  String get playlist_list => 'Playlist List';

  @override
  String get playlist_information => 'Playlist Information';

  @override
  String get playlist_name => 'Playlist Name';

  @override
  String get playlist_name_placeholder => 'Name for your playlist';

  @override
  String get playlist_name_required => 'Playlist name is required';

  @override
  String get playlist_name_min_2 => 'Playlist should at least 2 character';

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
  String get api_url_required => 'API URL required';

  @override
  String get username => 'Username';

  @override
  String get username_placeholder => 'Enter your username';

  @override
  String get username_required => 'Username is required';

  @override
  String get username_min_3 => 'Username should at least 3 character';

  @override
  String get password => 'Password';

  @override
  String get password_placeholder => 'Enter your password';

  @override
  String get password_required => 'Password is required';

  @override
  String get password_min_3 => 'Password should at least 3 character';

  @override
  String get server_url => 'Server URL';

  @override
  String get submitting => 'Saving...';

  @override
  String get submit_create_playlist => 'Save Playlist';

  @override
  String get subscription_details => 'Subscription Details';

  @override
  String subscription_remaining_day(Object days) {
    return 'Subscription: $days';
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
  String get no_connection => 'No Connection';

  @override
  String get expired => 'Expired';

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
  String get error_occurred => 'An error occurred';

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

  @override
  String get m3u_playlist_title => 'Add playlist with M3U file or URL';

  @override
  String get m3u_playlist_description =>
      'Supports traditional M3U format files';

  @override
  String get m3u_playlist => 'M3U Playlist';

  @override
  String get m3u_playlist_load_description =>
      'Load IPTV channels with M3U playlist file or URL';

  @override
  String get playlist_name_hint => 'Enter playlist name';

  @override
  String get playlist_name_min_length =>
      'Playlist name must be at least 2 characters';

  @override
  String get source_type => 'Source Type';

  @override
  String get url => 'URL';

  @override
  String get file => 'File';

  @override
  String get m3u_url => 'M3U URL';

  @override
  String get m3u_url_hint => 'http://example.com/playlist.m3u';

  @override
  String get m3u_url_required => 'M3U URL is required';

  @override
  String get url_format_error => 'Enter a valid URL format';

  @override
  String get url_scheme_error => 'URL must start with http:// or https://';

  @override
  String get m3u_file => 'M3U File';

  @override
  String get file_selected => 'File selected';

  @override
  String get select_m3u_file => 'Select M3U file (.m3u, .m3u8)';

  @override
  String get please_select_m3u_file => 'Please select an M3U file';

  @override
  String get file_selection_error => 'Error occurred while selecting file';

  @override
  String get processing => 'Processing...';

  @override
  String get create_playlist => 'Create Playlist';

  @override
  String get error_occurred_title => 'Error Occurred';

  @override
  String get m3u_info_message =>
      'All data is securely stored on your device.\nSupported formats: .m3u, .m3u8\nURL format: Must start with http:// or https://';

  @override
  String get m3u_parse_error => 'M3U parsing error';

  @override
  String get loading_m3u => 'Loading M3U';

  @override
  String get preparing_m3u_exception_no_source => 'No M3U source found';

  @override
  String get preparing_m3u_exception_empty => 'M3U file is empty';

  @override
  String preparing_m3u_exception_parse(Object error) {
    return 'M3U parsing error: $error';
  }

  @override
  String get not_categorized => 'Uncategorized';

  @override
  String get loading_lists => 'Loading Lists...';

  @override
  String get all => 'All';

  @override
  String iptv_channels_count(Object count) {
    return 'IPTV Channels ($count)';
  }

  @override
  String get unknown_channel => 'Unknown Channel';

  @override
  String get live_content => 'LIVE';

  @override
  String get movie_content => 'MOVIE';

  @override
  String get series_content => 'SERIES';

  @override
  String get media_content => 'MEDIA';

  @override
  String get m3u_error => 'M3U Error';

  @override
  String get episode_short => 'Ep';

  @override
  String season_number(Object number) {
    return '$number. Season';
  }

  @override
  String get image_loading => 'Loading image...';

  @override
  String get image_not_found => 'Image Not Found';
}
