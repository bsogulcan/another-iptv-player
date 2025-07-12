import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:intl/intl.dart' as intl;

import 'app_localizations_en.dart';
import 'app_localizations_tr.dart';

// ignore_for_file: type=lint

/// Callers can lookup localized strings with an instance of AppLocalizations
/// returned by `AppLocalizations.of(context)`.
///
/// Applications need to include `AppLocalizations.delegate()` in their app's
/// `localizationDelegates` list, and the locales they support in the app's
/// `supportedLocales` list. For example:
///
/// ```dart
/// import 'l10n/app_localizations.dart';
///
/// return MaterialApp(
///   localizationsDelegates: AppLocalizations.localizationsDelegates,
///   supportedLocales: AppLocalizations.supportedLocales,
///   home: MyApplicationHome(),
/// );
/// ```
///
/// ## Update pubspec.yaml
///
/// Please make sure to update your pubspec.yaml to include the following
/// packages:
///
/// ```yaml
/// dependencies:
///   # Internationalization support.
///   flutter_localizations:
///     sdk: flutter
///   intl: any # Use the pinned version from flutter_localizations
///
///   # Rest of dependencies
/// ```
///
/// ## iOS Applications
///
/// iOS applications define key application metadata, including supported
/// locales, in an Info.plist file that is built into the application bundle.
/// To configure the locales supported by your app, you’ll need to edit this
/// file.
///
/// First, open your project’s ios/Runner.xcworkspace Xcode workspace file.
/// Then, in the Project Navigator, open the Info.plist file under the Runner
/// project’s Runner folder.
///
/// Next, select the Information Property List item, select Add Item from the
/// Editor menu, then select Localizations from the pop-up menu.
///
/// Select and expand the newly-created Localizations item then, for each
/// locale your application supports, add a new item and select the locale
/// you wish to add from the pop-up menu in the Value field. This list should
/// be consistent with the languages listed in the AppLocalizations.supportedLocales
/// property.
abstract class AppLocalizations {
  AppLocalizations(String locale)
    : localeName = intl.Intl.canonicalizedLocale(locale.toString());

  final String localeName;

  static AppLocalizations? of(BuildContext context) {
    return Localizations.of<AppLocalizations>(context, AppLocalizations);
  }

  static const LocalizationsDelegate<AppLocalizations> delegate =
      _AppLocalizationsDelegate();

  /// A list of this localizations delegate along with the default localizations
  /// delegates.
  ///
  /// Returns a list of localizations delegates containing this delegate along with
  /// GlobalMaterialLocalizations.delegate, GlobalCupertinoLocalizations.delegate,
  /// and GlobalWidgetsLocalizations.delegate.
  ///
  /// Additional delegates can be added by appending to this list in
  /// MaterialApp. This list does not have to be used at all if a custom list
  /// of delegates is preferred or required.
  static const List<LocalizationsDelegate<dynamic>> localizationsDelegates =
      <LocalizationsDelegate<dynamic>>[
        delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
      ];

  /// A list of this localizations delegate's supported locales.
  static const List<Locale> supportedLocales = <Locale>[
    Locale('en'),
    Locale('tr'),
  ];

  /// No description provided for @slogan.
  ///
  /// In en, this message translates to:
  /// **'Open Source IPTV Player'**
  String get slogan;

  /// No description provided for @search.
  ///
  /// In en, this message translates to:
  /// **'Search'**
  String get search;

  /// No description provided for @search_live_stream.
  ///
  /// In en, this message translates to:
  /// **'Search live stream'**
  String get search_live_stream;

  /// No description provided for @search_movie.
  ///
  /// In en, this message translates to:
  /// **'Search movie'**
  String get search_movie;

  /// No description provided for @not_found_in_category.
  ///
  /// In en, this message translates to:
  /// **'No content found in this category'**
  String get not_found_in_category;

  /// No description provided for @live_stream_not_found.
  ///
  /// In en, this message translates to:
  /// **'No live stream found'**
  String get live_stream_not_found;

  /// No description provided for @movie_not_found.
  ///
  /// In en, this message translates to:
  /// **'No movie found'**
  String get movie_not_found;

  /// No description provided for @see_all.
  ///
  /// In en, this message translates to:
  /// **'View All'**
  String get see_all;

  /// No description provided for @preview.
  ///
  /// In en, this message translates to:
  /// **'Preview'**
  String get preview;

  /// No description provided for @info.
  ///
  /// In en, this message translates to:
  /// **'Info'**
  String get info;

  /// No description provided for @close.
  ///
  /// In en, this message translates to:
  /// **'Close'**
  String get close;

  /// No description provided for @reset.
  ///
  /// In en, this message translates to:
  /// **'Reset'**
  String get reset;

  /// No description provided for @delete.
  ///
  /// In en, this message translates to:
  /// **'Delete'**
  String get delete;

  /// No description provided for @cancel.
  ///
  /// In en, this message translates to:
  /// **'Cancel'**
  String get cancel;

  /// No description provided for @history.
  ///
  /// In en, this message translates to:
  /// **'History'**
  String get history;

  /// No description provided for @history_empty_message.
  ///
  /// In en, this message translates to:
  /// **'Your watched videos will appear here'**
  String get history_empty_message;

  /// No description provided for @live.
  ///
  /// In en, this message translates to:
  /// **'Live'**
  String get live;

  /// No description provided for @live_streams.
  ///
  /// In en, this message translates to:
  /// **'Live Streams'**
  String get live_streams;

  /// No description provided for @on_live.
  ///
  /// In en, this message translates to:
  /// **'Live'**
  String get on_live;

  /// No description provided for @other_channels.
  ///
  /// In en, this message translates to:
  /// **'Other Channels'**
  String get other_channels;

  /// No description provided for @movies.
  ///
  /// In en, this message translates to:
  /// **'Movies'**
  String get movies;

  /// No description provided for @movie.
  ///
  /// In en, this message translates to:
  /// **'Movie'**
  String get movie;

  /// No description provided for @series_singular.
  ///
  /// In en, this message translates to:
  /// **'Series'**
  String get series_singular;

  /// No description provided for @series_plural.
  ///
  /// In en, this message translates to:
  /// **'Series'**
  String get series_plural;

  /// No description provided for @category_id.
  ///
  /// In en, this message translates to:
  /// **'Category ID'**
  String get category_id;

  /// No description provided for @channel_information.
  ///
  /// In en, this message translates to:
  /// **'Channel Information'**
  String get channel_information;

  /// No description provided for @channel_id.
  ///
  /// In en, this message translates to:
  /// **'Channel ID'**
  String get channel_id;

  /// No description provided for @series_id.
  ///
  /// In en, this message translates to:
  /// **'Series ID'**
  String get series_id;

  /// No description provided for @quality.
  ///
  /// In en, this message translates to:
  /// **'Quality'**
  String get quality;

  /// No description provided for @stream_type.
  ///
  /// In en, this message translates to:
  /// **'Stream Type'**
  String get stream_type;

  /// No description provided for @format.
  ///
  /// In en, this message translates to:
  /// **'Format'**
  String get format;

  /// No description provided for @season.
  ///
  /// In en, this message translates to:
  /// **'Seasons'**
  String get season;

  /// No description provided for @episode_count.
  ///
  /// In en, this message translates to:
  /// **'{count} Episodes'**
  String episode_count(Object count);

  /// No description provided for @duration.
  ///
  /// In en, this message translates to:
  /// **'Duration: {duration}'**
  String duration(Object duration);

  /// No description provided for @episode_duration.
  ///
  /// In en, this message translates to:
  /// **'Episode Duration'**
  String get episode_duration;

  /// No description provided for @creation_date.
  ///
  /// In en, this message translates to:
  /// **'Added Date'**
  String get creation_date;

  /// No description provided for @release_date.
  ///
  /// In en, this message translates to:
  /// **'Release Date'**
  String get release_date;

  /// No description provided for @genre.
  ///
  /// In en, this message translates to:
  /// **'Genre'**
  String get genre;

  /// No description provided for @cast.
  ///
  /// In en, this message translates to:
  /// **'Cast'**
  String get cast;

  /// No description provided for @description.
  ///
  /// In en, this message translates to:
  /// **'Description'**
  String get description;

  /// No description provided for @video_track.
  ///
  /// In en, this message translates to:
  /// **'Video Track'**
  String get video_track;

  /// No description provided for @audio_track.
  ///
  /// In en, this message translates to:
  /// **'Audio Track'**
  String get audio_track;

  /// No description provided for @subtitle_track.
  ///
  /// In en, this message translates to:
  /// **'Subtitle Track'**
  String get subtitle_track;

  /// No description provided for @settings.
  ///
  /// In en, this message translates to:
  /// **'Settings'**
  String get settings;

  /// No description provided for @general_settings.
  ///
  /// In en, this message translates to:
  /// **'General Settings'**
  String get general_settings;

  /// No description provided for @app_language.
  ///
  /// In en, this message translates to:
  /// **'App Language'**
  String get app_language;

  /// No description provided for @continue_on_background.
  ///
  /// In en, this message translates to:
  /// **'Continue Playing in Background'**
  String get continue_on_background;

  /// No description provided for @continue_on_background_description.
  ///
  /// In en, this message translates to:
  /// **'Keep playing even when app is in the background'**
  String get continue_on_background_description;

  /// No description provided for @refresh_contents.
  ///
  /// In en, this message translates to:
  /// **'Refresh Content'**
  String get refresh_contents;

  /// No description provided for @subtitle_settings.
  ///
  /// In en, this message translates to:
  /// **'Subtitle Settings'**
  String get subtitle_settings;

  /// No description provided for @subtitle_settings_description.
  ///
  /// In en, this message translates to:
  /// **'Customize subtitle appearance'**
  String get subtitle_settings_description;

  /// No description provided for @sample_text.
  ///
  /// In en, this message translates to:
  /// **'Sample subtitle text\nIt will look like this'**
  String get sample_text;

  /// No description provided for @font_settings.
  ///
  /// In en, this message translates to:
  /// **'Font Settings'**
  String get font_settings;

  /// No description provided for @font_size.
  ///
  /// In en, this message translates to:
  /// **'Font Size'**
  String get font_size;

  /// No description provided for @font_height.
  ///
  /// In en, this message translates to:
  /// **'Line Height'**
  String get font_height;

  /// No description provided for @letter_spacing.
  ///
  /// In en, this message translates to:
  /// **'Letter Spacing'**
  String get letter_spacing;

  /// No description provided for @word_spacing.
  ///
  /// In en, this message translates to:
  /// **'Word Spacing'**
  String get word_spacing;

  /// No description provided for @padding.
  ///
  /// In en, this message translates to:
  /// **'Padding'**
  String get padding;

  /// No description provided for @color_settings.
  ///
  /// In en, this message translates to:
  /// **'Color Settings'**
  String get color_settings;

  /// No description provided for @text_color.
  ///
  /// In en, this message translates to:
  /// **'Text Color'**
  String get text_color;

  /// No description provided for @background_color.
  ///
  /// In en, this message translates to:
  /// **'Background Color'**
  String get background_color;

  /// No description provided for @style_settings.
  ///
  /// In en, this message translates to:
  /// **'Style Settings'**
  String get style_settings;

  /// No description provided for @font_weight.
  ///
  /// In en, this message translates to:
  /// **'Font Weight'**
  String get font_weight;

  /// No description provided for @thin.
  ///
  /// In en, this message translates to:
  /// **'Thin'**
  String get thin;

  /// No description provided for @normal.
  ///
  /// In en, this message translates to:
  /// **'Normal'**
  String get normal;

  /// No description provided for @medium.
  ///
  /// In en, this message translates to:
  /// **'Medium'**
  String get medium;

  /// No description provided for @bold.
  ///
  /// In en, this message translates to:
  /// **'Bold'**
  String get bold;

  /// No description provided for @extreme_bold.
  ///
  /// In en, this message translates to:
  /// **'Extra Bold'**
  String get extreme_bold;

  /// No description provided for @text_align.
  ///
  /// In en, this message translates to:
  /// **'Text Alignment'**
  String get text_align;

  /// No description provided for @left.
  ///
  /// In en, this message translates to:
  /// **'Left'**
  String get left;

  /// No description provided for @center.
  ///
  /// In en, this message translates to:
  /// **'Center'**
  String get center;

  /// No description provided for @right.
  ///
  /// In en, this message translates to:
  /// **'Right'**
  String get right;

  /// No description provided for @justify.
  ///
  /// In en, this message translates to:
  /// **'Justify'**
  String get justify;

  /// No description provided for @pick_color.
  ///
  /// In en, this message translates to:
  /// **'Pick Color'**
  String get pick_color;

  /// No description provided for @my_playlists.
  ///
  /// In en, this message translates to:
  /// **'My Playlists'**
  String get my_playlists;

  /// No description provided for @create_new_playlist.
  ///
  /// In en, this message translates to:
  /// **'Create New Playlist'**
  String get create_new_playlist;

  /// No description provided for @playlist_list.
  ///
  /// In en, this message translates to:
  /// **'Playlist List'**
  String get playlist_list;

  /// No description provided for @playlist_information.
  ///
  /// In en, this message translates to:
  /// **'Playlist Information'**
  String get playlist_information;

  /// No description provided for @playlist_name.
  ///
  /// In en, this message translates to:
  /// **'Playlist Name'**
  String get playlist_name;

  /// No description provided for @playlist_deleted.
  ///
  /// In en, this message translates to:
  /// **'{name} deleted'**
  String playlist_deleted(Object name);

  /// No description provided for @playlist_delete_confirmation_title.
  ///
  /// In en, this message translates to:
  /// **'Delete Playlist'**
  String get playlist_delete_confirmation_title;

  /// No description provided for @playlist_delete_confirmation_message.
  ///
  /// In en, this message translates to:
  /// **'Are you sure you want to delete the playlist \'{name}\'?\nThis action cannot be undone.'**
  String playlist_delete_confirmation_message(Object name);

  /// No description provided for @empty_playlist_title.
  ///
  /// In en, this message translates to:
  /// **'No Playlist Yet'**
  String get empty_playlist_title;

  /// No description provided for @empty_playlist_message.
  ///
  /// In en, this message translates to:
  /// **'Start by creating your first playlist.\nYou can add playlists in Xtream Code or M3U format.'**
  String get empty_playlist_message;

  /// No description provided for @empty_playlist_button.
  ///
  /// In en, this message translates to:
  /// **'Create My First Playlist'**
  String get empty_playlist_button;

  /// No description provided for @select_playlist_type.
  ///
  /// In en, this message translates to:
  /// **'Select Playlist Type'**
  String get select_playlist_type;

  /// No description provided for @select_playlist_message.
  ///
  /// In en, this message translates to:
  /// **'Choose the type of playlist you want to create'**
  String get select_playlist_message;

  /// No description provided for @xtream_code_title.
  ///
  /// In en, this message translates to:
  /// **'Connect with API URL, Username, and Password'**
  String get xtream_code_title;

  /// No description provided for @xtream_code_description.
  ///
  /// In en, this message translates to:
  /// **'Easily connect with information from your IPTV provider'**
  String get xtream_code_description;

  /// No description provided for @select_playlist_type_footer.
  ///
  /// In en, this message translates to:
  /// **'Your playlist information is securely stored on your device.'**
  String get select_playlist_type_footer;

  /// No description provided for @api_url.
  ///
  /// In en, this message translates to:
  /// **'API URL'**
  String get api_url;

  /// No description provided for @username.
  ///
  /// In en, this message translates to:
  /// **'Username'**
  String get username;

  /// No description provided for @username_placeholder.
  ///
  /// In en, this message translates to:
  /// **'Enter your username'**
  String get username_placeholder;

  /// No description provided for @password.
  ///
  /// In en, this message translates to:
  /// **'Password'**
  String get password;

  /// No description provided for @password_placeholder.
  ///
  /// In en, this message translates to:
  /// **'Enter your password'**
  String get password_placeholder;

  /// No description provided for @server_url.
  ///
  /// In en, this message translates to:
  /// **'Server URL'**
  String get server_url;

  /// No description provided for @submit_create_playlist.
  ///
  /// In en, this message translates to:
  /// **'Save Playlist'**
  String get submit_create_playlist;

  /// No description provided for @subscription_details.
  ///
  /// In en, this message translates to:
  /// **'Subscription Details'**
  String get subscription_details;

  /// No description provided for @subscription_remaining_day.
  ///
  /// In en, this message translates to:
  /// **'Subscription: {days} days'**
  String subscription_remaining_day(Object days);

  /// No description provided for @remaining_day_title.
  ///
  /// In en, this message translates to:
  /// **'Time Remaining'**
  String get remaining_day_title;

  /// No description provided for @remaining_day.
  ///
  /// In en, this message translates to:
  /// **'{days} Days'**
  String remaining_day(Object days);

  /// No description provided for @connected.
  ///
  /// In en, this message translates to:
  /// **'Connected'**
  String get connected;

  /// No description provided for @active_connection.
  ///
  /// In en, this message translates to:
  /// **'Active Connection'**
  String get active_connection;

  /// No description provided for @maximum_connection.
  ///
  /// In en, this message translates to:
  /// **'Maximum Connection'**
  String get maximum_connection;

  /// No description provided for @server_information.
  ///
  /// In en, this message translates to:
  /// **'Server Information'**
  String get server_information;

  /// No description provided for @timezone.
  ///
  /// In en, this message translates to:
  /// **'Time Zone'**
  String get timezone;

  /// No description provided for @server_message.
  ///
  /// In en, this message translates to:
  /// **'Server Message'**
  String get server_message;

  /// No description provided for @all_datas_are_stored_in_device.
  ///
  /// In en, this message translates to:
  /// **'All data is securely stored on your device'**
  String get all_datas_are_stored_in_device;

  /// No description provided for @url_format_validate_message.
  ///
  /// In en, this message translates to:
  /// **'URL format should be like http://server:port'**
  String get url_format_validate_message;

  /// No description provided for @url_format_validate_error.
  ///
  /// In en, this message translates to:
  /// **'Please enter a valid URL (must start with http:// or https://)'**
  String get url_format_validate_error;

  /// No description provided for @playlist_name_already_exists.
  ///
  /// In en, this message translates to:
  /// **'A playlist with this name already exists'**
  String get playlist_name_already_exists;

  /// No description provided for @invalid_credentials.
  ///
  /// In en, this message translates to:
  /// **'Could not get a response from your IPTV provider, please check your information'**
  String get invalid_credentials;

  /// No description provided for @error_occured.
  ///
  /// In en, this message translates to:
  /// **'An error occurred'**
  String get error_occured;

  /// No description provided for @connecting.
  ///
  /// In en, this message translates to:
  /// **'Connecting'**
  String get connecting;

  /// No description provided for @preparing_categories.
  ///
  /// In en, this message translates to:
  /// **'Preparing categories'**
  String get preparing_categories;

  /// No description provided for @preparing_categories_exception.
  ///
  /// In en, this message translates to:
  /// **'Could not load categories: {error}'**
  String preparing_categories_exception(Object error);

  /// No description provided for @preparing_live_streams.
  ///
  /// In en, this message translates to:
  /// **'Loading live channels'**
  String get preparing_live_streams;

  /// No description provided for @preparing_live_streams_exception_1.
  ///
  /// In en, this message translates to:
  /// **'Could not get live channels'**
  String get preparing_live_streams_exception_1;

  /// No description provided for @preparing_live_streams_exception_2.
  ///
  /// In en, this message translates to:
  /// **'Error loading live channels: {error}'**
  String preparing_live_streams_exception_2(Object error);

  /// No description provided for @preparing_movies.
  ///
  /// In en, this message translates to:
  /// **'Opening movie library'**
  String get preparing_movies;

  /// No description provided for @preparing_movies_exception_1.
  ///
  /// In en, this message translates to:
  /// **'Could not get movies'**
  String get preparing_movies_exception_1;

  /// No description provided for @preparing_movies_exception_2.
  ///
  /// In en, this message translates to:
  /// **'Error loading movies: {error}'**
  String preparing_movies_exception_2(Object error);

  /// No description provided for @preparing_series.
  ///
  /// In en, this message translates to:
  /// **'Preparing series library'**
  String get preparing_series;

  /// No description provided for @preparing_series_exception_1.
  ///
  /// In en, this message translates to:
  /// **'Could not get series'**
  String get preparing_series_exception_1;

  /// No description provided for @preparing_series_exception_2.
  ///
  /// In en, this message translates to:
  /// **'Error loading series: {error}'**
  String preparing_series_exception_2(Object error);

  /// No description provided for @preparing_user_info_exception_1.
  ///
  /// In en, this message translates to:
  /// **'Could not get user information'**
  String get preparing_user_info_exception_1;

  /// No description provided for @preparing_user_info_exception_2.
  ///
  /// In en, this message translates to:
  /// **'Error loading user information: {error}'**
  String preparing_user_info_exception_2(Object error);
}

class _AppLocalizationsDelegate
    extends LocalizationsDelegate<AppLocalizations> {
  const _AppLocalizationsDelegate();

  @override
  Future<AppLocalizations> load(Locale locale) {
    return SynchronousFuture<AppLocalizations>(lookupAppLocalizations(locale));
  }

  @override
  bool isSupported(Locale locale) =>
      <String>['en', 'tr'].contains(locale.languageCode);

  @override
  bool shouldReload(_AppLocalizationsDelegate old) => false;
}

AppLocalizations lookupAppLocalizations(Locale locale) {
  // Lookup logic when only language code is specified.
  switch (locale.languageCode) {
    case 'en':
      return AppLocalizationsEn();
    case 'tr':
      return AppLocalizationsTr();
  }

  throw FlutterError(
    'AppLocalizations.delegate failed to load unsupported locale "$locale". This is likely '
    'an issue with the localizations generation tool. Please file an issue '
    'on GitHub with a reproducible sample app and the gen-l10n configuration '
    'that was used.',
  );
}
