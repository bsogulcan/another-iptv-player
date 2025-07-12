import 'package:another_iptv_player/screens/settings/subtitle_settings_section.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../controllers/locale_provider.dart';
import '../../repositories/user_preferences.dart';
import '../../services/app_state.dart';
import '../../widgets/dropdown_tile_widget.dart';
import '../../widgets/section_title_widget.dart';
import '../playlist_screen.dart';
import '../xtream-codes/xtream_code_data_loader_screen.dart';

class GeneralSettingsWidget extends StatefulWidget {
  const GeneralSettingsWidget({super.key});

  @override
  State<GeneralSettingsWidget> createState() => _GeneralSettingsWidgetState();
}

class _GeneralSettingsWidgetState extends State<GeneralSettingsWidget> {
  bool _backgroundPlayEnabled = false;
  Locale _appLanguage = Locale('tr');
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadSettings();
  }

  Future<void> _loadSettings() async {
    try {
      final backgroundPlay = await UserPreferences.getBackgroundPlay();
      setState(() {
        _backgroundPlayEnabled = backgroundPlay;
        _isLoading = false;
      });
    } catch (e) {
      setState(() {
        _isLoading = false;
      });
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
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SectionTitleWidget(title: 'Genel Ayarlar'),
        Card(
          child: Column(
            children: [
              ListTile(
                leading: const Icon(Icons.home),
                title: const Text('Playlist Listesi'),
                trailing: const Icon(Icons.chevron_right),
                onTap: () async {
                  await UserPreferences.removeLastPlaylist();
                  if (mounted) {
                    Navigator.pushReplacement(
                      context,
                      MaterialPageRoute(builder: (context) => PlaylistScreen()),
                    );
                  }
                },
              ),
              const Divider(height: 1),
              SwitchListTile(
                secondary: const Icon(Icons.play_circle_outline),
                title: const Text('Arkaplanda Çalmaya Devam Et'),
                subtitle: const Text(
                  'Uygulama arka plana geçtiğinde oynatmayı sürdür',
                ),
                value: _backgroundPlayEnabled,
                onChanged: _saveBackgroundPlaySetting,
              ),
              const Divider(height: 1),
              ListTile(
                leading: const Icon(Icons.subtitles_outlined),
                title: const Text('Altyazı Ayarları'),
                subtitle: const Text('Altyazı görünümünü özelleştirin'),
                trailing: const Icon(Icons.chevron_right),
                onTap: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (context) => const SubtitleSettingsScreen(),
                    ),
                  );
                },
              ),
              const Divider(height: 1),
              ListTile(
                leading: const Icon(Icons.refresh),
                title: const Text('İçerikleri Yenile'),
                trailing: const Icon(Icons.cloud_download),
                onTap: () {
                  Navigator.pushReplacement(
                    context,
                    MaterialPageRoute(
                      builder: (context) => XtreamCodeDataLoaderScreen(
                        playlist: AppState.currentPlaylist!,
                        refreshAll: true,
                      ),
                    ),
                  );
                },
              ),
              const Divider(height: 1),

              DropdownTileWidget<Locale>(
                icon: Icons.format_bold,
                label: 'Uygulama Dili',
                value:
                    Provider.of<LocaleProvider>(context).locale ??
                    const Locale('tr'),
                items: const [
                  DropdownMenuItem(value: Locale('tr'), child: Text('Türkçe')),
                  DropdownMenuItem(value: Locale('en'), child: Text('English')),
                ],
                onChanged: (v) {
                  Provider.of<LocaleProvider>(
                    context,
                    listen: false,
                  ).setLocale(v!);
                },
              ),
            ],
          ),
        ),
      ],
    );
  }
}
