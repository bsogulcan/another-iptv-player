import 'package:another_iptv_player/database/database.dart';
import 'package:another_iptv_player/screens/settings/subtitle_settings_section.dart';
import 'package:another_iptv_player/services/service_locator.dart';
import 'package:another_iptv_player/utils/get_playlist_type.dart';
import 'package:another_iptv_player/utils/show_loading_dialog.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:another_iptv_player/l10n/localization_extension.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../controllers/locale_provider.dart';
import '../../controllers/xtream_code_home_controller.dart';
import '../../controllers/theme_provider.dart';
import '../../l10n/supported_languages.dart';
import '../../models/m3u_item.dart';
import '../../repositories/user_preferences.dart';
import '../../services/app_state.dart';
import '../../services/m3u_parser.dart';
import '../../widgets/dropdown_tile_widget.dart';
import '../../widgets/section_title_widget.dart';
import '../m3u/m3u_data_loader_screen.dart';
import '../playlist_screen.dart';
import '../xtream-codes/xtream_code_data_loader_screen.dart';
import 'category_settings_section.dart';

final controller = XtreamCodeHomeController(true);

class GeneralSettingsWidget extends StatefulWidget {
  const GeneralSettingsWidget({super.key});

  @override
  State<GeneralSettingsWidget> createState() => _GeneralSettingsWidgetState();
}

class _GeneralSettingsWidgetState extends State<GeneralSettingsWidget> {
  final AppDatabase database = getIt<AppDatabase>();

  bool _backgroundPlayEnabled = false;
  bool _isLoading = true;
  String? _selectedFilePath;
  String _selectedTheme = 'system';
  bool _brightnessGesture = false;
  bool _volumeGesture = false;
  bool _seekGesture = false;
  bool _speedUpOnLongPress = true;
  bool _seekOnDoubleTap = true;
  String _appVersion = '';

  @override
  void initState() {
    super.initState();
    _loadSettings();
  }

  Future<void> _loadSettings() async {
    try {
      final backgroundPlay = await UserPreferences.getBackgroundPlay();
      final themeMode = await UserPreferences.getThemeMode();
      final brightnessGesture = await UserPreferences.getBrightnessGesture();
      final volumeGesture = await UserPreferences.getVolumeGesture();
      final seekGesture = await UserPreferences.getSeekGesture();
      final speedUpOnLongPress = await UserPreferences.getSpeedUpOnLongPress();
      final seekOnDoubleTap = await UserPreferences.getSeekOnDoubleTap();
      final packageInfo = await PackageInfo.fromPlatform();
      setState(() {
        _backgroundPlayEnabled = backgroundPlay;
        _selectedTheme = _themeModeToString(themeMode);
        _brightnessGesture = brightnessGesture;
        _volumeGesture = volumeGesture;
        _seekGesture = seekGesture;
        _speedUpOnLongPress = speedUpOnLongPress;
        _seekOnDoubleTap = seekOnDoubleTap;
        _appVersion = packageInfo.version;
        _isLoading = false;
      });
    } catch (e) {
      setState(() {
        _isLoading = false;
      });
    }
  }

  String _themeModeToString(ThemeMode mode) {
    switch (mode) {
      case ThemeMode.light:
        return 'light';
      case ThemeMode.dark:
        return 'dark';
      default:
        return 'system';
    }
  }

  ThemeMode _stringToThemeMode(String value) {
    switch (value) {
      case 'light':
        return ThemeMode.light;
      case 'dark':
        return ThemeMode.dark;
      default:
        return ThemeMode.system;
    }
  }

  Future<void> _saveBackgroundPlaySetting(bool value) async {
    try {
      await UserPreferences.setBackgroundPlay(value);
      setState(() {
        _backgroundPlayEnabled = value;
      });
    } catch (e) {
      setState(() {
        _backgroundPlayEnabled = !value;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final themeProvider = Provider.of<ThemeProvider>(context);
    return _isLoading
        ? const Center(child: CircularProgressIndicator())
        : Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Card(
          child: ListTile(
            leading: const Icon(Icons.home),
            title: Text(context.loc.playlist_list),
            trailing: const Icon(Icons.chevron_right),
            onTap: () async {
              await UserPreferences.removeLastPlaylist();
              if (mounted) {
                Navigator.pushReplacement(
                  context,
                  MaterialPageRoute(
                      builder: (context) => PlaylistScreen()),
                );
              }
            },
          ),
        ),
        const SizedBox(height: 10),
        SectionTitleWidget(title: context.loc.general_settings),
        Card(
          child: Column(
            children: [
              ListTile(
                leading: const Icon(Icons.refresh),
                title: Text(context.loc.refresh_contents),
                trailing: const Icon(Icons.cloud_download),
                onTap: () {
                  if (isXtreamCode) {
                    Navigator.pushReplacement(
                      context,
                      MaterialPageRoute(
                        builder: (context) => XtreamCodeDataLoaderScreen(
                          playlist: AppState.currentPlaylist!,
                          refreshAll: true,
                        ),
                      ),
                    );
                  }

                  if (isM3u) {
                    refreshM3uPlaylist();
                  }
                },
              ),
              if (isXtreamCode) const Divider(height: 1),
              if (isXtreamCode)
                ListTile(
                  leading: const Icon(Icons.subtitles_outlined),
                  title: Text(context.loc.hide_category),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () async {
                    final result = await Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (context) => CategorySettingsScreen(
                          controller: controller,
                        ),
                      ),
                    );

                    if (result == true) {
                      if (isXtreamCode) {
                        Navigator.pushReplacement(
                          context,
                          MaterialPageRoute(
                            builder: (context) =>
                                XtreamCodeDataLoaderScreen(
                                  playlist: AppState.currentPlaylist!,
                                  refreshAll: true,
                                ),
                          ),
                        );
                      }

                      if (isM3u) {
                        refreshM3uPlaylist();
                      }
                    }
                  },
                ),
              const Divider(height: 1),
              DropdownTileWidget<Locale>(
                icon: Icons.language,
                label: context.loc.app_language,
                value: Localizations.localeOf(context),
                items: [
                  ...supportedLanguages.map(
                        (language) => DropdownMenuItem(
                      value: Locale(language['code']),
                      child: Text(language['name']),
                    ),
                  ),
                ],
                onChanged: (v) {
                  Provider.of<LocaleProvider>(
                    context,
                    listen: false,
                  ).setLocale(v!);
                },
              ),
              const Divider(height: 1),
              DropdownTileWidget<String>(
                icon: Icons.color_lens_outlined,
                label: context.loc.theme,
                value: _selectedTheme,
                items: [
                  DropdownMenuItem(
                    value: 'system',
                    child: Text(context.loc.standard),
                  ),
                  DropdownMenuItem(
                    value: 'light',
                    child: Text(context.loc.light),
                  ),
                  DropdownMenuItem(
                    value: 'dark',
                    child: Text(context.loc.dark),
                  ),
                ],
                onChanged: (value) async {
                  if (value != null) {
                    final themeMode = _stringToThemeMode(value);
                    await themeProvider.setTheme(themeMode);
                    setState(() {
                      _selectedTheme = value;
                    });
                  }
                },
              ),
            ],
          ),
        ),
        const SizedBox(height: 10),
        SectionTitleWidget(title: context.loc.player_settings),
        Card(
          child: Column(
            children: [
              SwitchListTile(
                secondary: const Icon(Icons.play_circle_outline),
                title: Text(context.loc.continue_on_background),
                subtitle: Text(
                    context.loc.continue_on_background_description),
                value: _backgroundPlayEnabled,
                onChanged: _saveBackgroundPlaySetting,
              ),
              const Divider(height: 1),
              ListTile(
                leading: const Icon(Icons.subtitles_outlined),
                title: Text(context.loc.subtitle_settings),
                subtitle:
                Text(context.loc.subtitle_settings_description),
                trailing: const Icon(Icons.chevron_right),
                onTap: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (context) =>
                      const SubtitleSettingsScreen(),
                    ),
                  );
                },
              ),
              // Player gesture settings - Only show on mobile platforms (Android & iOS)
              if (Theme.of(context).platform == TargetPlatform.android ||
                  Theme.of(context).platform == TargetPlatform.iOS) ...[
                const Divider(height: 1),
                SwitchListTile(
                  secondary: const Icon(Icons.brightness_6),
                  title: Text(context.loc.brightness_gesture),
                  subtitle: Text(context.loc.brightness_gesture_description),
                  value: _brightnessGesture,
                  onChanged: (value) async {
                    await UserPreferences.setBrightnessGesture(value);
                    setState(() {
                      _brightnessGesture = value;
                    });
                  },
                ),
                const Divider(height: 1),
                SwitchListTile(
                  secondary: const Icon(Icons.volume_up),
                  title: Text(context.loc.volume_gesture),
                  subtitle: Text(context.loc.volume_gesture_description),
                  value: _volumeGesture,
                  onChanged: (value) async {
                    await UserPreferences.setVolumeGesture(value);
                    setState(() {
                      _volumeGesture = value;
                    });
                  },
                ),
                const Divider(height: 1),
                SwitchListTile(
                  secondary: const Icon(Icons.swipe),
                  title: Text(context.loc.seek_gesture),
                  subtitle: Text(context.loc.seek_gesture_description),
                  value: _seekGesture,
                  onChanged: (value) async {
                    await UserPreferences.setSeekGesture(value);
                    setState(() {
                      _seekGesture = value;
                    });
                  },
                ),
                const Divider(height: 1),
                SwitchListTile(
                  secondary: const Icon(Icons.fast_forward),
                  title: Text(context.loc.speed_up_on_long_press),
                  subtitle: Text(context.loc.speed_up_on_long_press_description),
                  value: _speedUpOnLongPress,
                  onChanged: (value) async {
                    await UserPreferences.setSpeedUpOnLongPress(value);
                    setState(() {
                      _speedUpOnLongPress = value;
                    });
                  },
                ),
                const Divider(height: 1),
                SwitchListTile(
                  secondary: const Icon(Icons.touch_app),
                  title: Text(context.loc.seek_on_double_tap),
                  subtitle: Text(context.loc.seek_on_double_tap_description),
                  value: _seekOnDoubleTap,
                  onChanged: (value) async {
                    await UserPreferences.setSeekOnDoubleTap(value);
                    setState(() {
                      _seekOnDoubleTap = value;
                    });
                  },
                ),
              ],
            ],
          ),
        ),
        const SizedBox(height: 10),
        SectionTitleWidget(title: context.loc.about),
        Card(
          child: Column(
            children: [
              ListTile(
                leading: const Icon(Icons.info_outline),
                title: Text(context.loc.app_version),
                subtitle: Text(_appVersion.isNotEmpty ? _appVersion : 'Loading...'),
                dense: true,
              ),
              const Divider(height: 1),
              ListTile(
                leading: const Icon(Icons.code),
                title: Text(context.loc.support_on_github),
                subtitle: Text(context.loc.support_on_github_description),
                trailing: const Icon(Icons.open_in_new, size: 18),
                dense: true,
                onTap: () async {
                  final url = Uri.parse('https://github.com/bsogulcan/another-iptv-player');
                  if (await canLaunchUrl(url)) {
                    await launchUrl(url, mode: LaunchMode.externalApplication);
                  }
                },
              ),
            ],
          ),
        ),
      ],
    );
  }

  refreshM3uPlaylist() async {
    List<M3uItem> oldM3uItems = AppState.m3uItems!;
    List<M3uItem> newM3uItems = [];

    if (AppState.currentPlaylist!.url!.startsWith('http')) {
      showLoadingDialog(context, context.loc.loading_m3u);
      final params = {
        'id': AppState.currentPlaylist!.id,
        'url': AppState.currentPlaylist!.url!,
      };
      newM3uItems = await compute(M3uParser.parseM3uUrl, params);
    } else {
      await _pickFile();
      if (_selectedFilePath == null) return;

      showLoadingDialog(context, context.loc.loading_m3u);
      final params = {
        'id': AppState.currentPlaylist!.id,
        'filePath': _selectedFilePath!,
      };
      newM3uItems = await compute(M3uParser.parseM3uFile, params);
    }

    newM3uItems = updateM3UItemIdsByPosition(
      oldItems: oldM3uItems,
      newItems: newM3uItems,
    );

    await database.deleteAllM3uItems(AppState.currentPlaylist!.id);

    Navigator.pushReplacement(
      context,
      MaterialPageRoute(
        builder: (context) => M3uDataLoaderScreen(
          playlist: AppState.currentPlaylist!,
          m3uItems: newM3uItems,
        ),
      ),
    );
  }

  Future<void> _pickFile() async {
    _selectedFilePath = null;

    try {
      FilePickerResult? result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['m3u', 'm3u8'],
        allowMultiple: false,
      );

      if (result != null) {
        setState(() {
          _selectedFilePath = result.files.single.path;
        });
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(context.loc.file_selection_error)),
      );
    }
  }

  List<M3uItem> updateM3UItemIdsByPosition({
    required List<M3uItem> oldItems,
    required List<M3uItem> newItems,
  }) {
    Map<String, List<MapEntry<int, String>>> groupedOldItems = {};
    for (int i = 0; i < oldItems.length; i++) {
      M3uItem item = oldItems[i];
      String key = "${item.url}|||${item.name}";
      groupedOldItems.putIfAbsent(key, () => []);
      groupedOldItems[key]!.add(MapEntry(i, item.id));
    }

    Map<String, int> groupUsageCounter = {};
    List<M3uItem> updatedItems = [];

    for (int i = 0; i < newItems.length; i++) {
      M3uItem newItem = newItems[i];
      String key = "${newItem.url}|||${newItem.name}";

      if (groupedOldItems.containsKey(key)) {
        List<MapEntry<int, String>> oldGroup = groupedOldItems[key]!;
        int usageCount = groupUsageCounter[key] ?? 0;

        if (usageCount < oldGroup.length) {
          String oldId = oldGroup[usageCount].value;
          updatedItems.add(newItem.copyWith(id: oldId));
          groupUsageCounter[key] = usageCount + 1;
        } else {
          updatedItems.add(newItem);
        }
      } else {
        updatedItems.add(newItem);
      }
    }

    return updatedItems;
  }
}
