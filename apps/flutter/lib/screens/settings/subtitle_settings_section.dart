import 'package:another_iptv_player/repositories/user_preferences.dart';
import 'package:flutter/material.dart';
import 'package:another_iptv_player/l10n/localization_extension.dart';
import '../../widgets/color_picker_tile_widget.dart';
import '../../widgets/dropdown_tile_widget.dart';
import '../../widgets/slider_tile_widget.dart';

class SubtitleSettingsScreen extends StatefulWidget {
  const SubtitleSettingsScreen({super.key});

  @override
  State<SubtitleSettingsScreen> createState() => _SubtitleSettingsScreenState();
}

class _SubtitleSettingsScreenState extends State<SubtitleSettingsScreen> {
  bool _isLoading = true;

  double _fontSize = 32.0;
  double _height = 1.4;
  double _letterSpacing = 0.0;
  double _wordSpacing = 0.0;
  Color _textColor = const Color(0xffffffff);
  Color _backgroundColor = const Color(0xaa000000);
  FontWeight _fontWeight = FontWeight.normal;
  TextAlign _textAlign = TextAlign.center;
  double _padding = 24.0;

  @override
  void initState() {
    super.initState();
    _loadSettings();
  }

  Future<void> _loadSettings() async {
    _fontSize = await UserPreferences.getSubtitleFontSize();
    _height = await UserPreferences.getSubtitleHeight();
    _letterSpacing = await UserPreferences.getSubtitleLetterSpacing();
    _wordSpacing = await UserPreferences.getSubtitleWordSpacing();
    _textColor = await UserPreferences.getSubtitleTextColor();
    _backgroundColor = await UserPreferences.getSubtitleBackgroundColor();
    _fontWeight = await UserPreferences.getSubtitleFontWeight();
    _textAlign = await UserPreferences.getSubtitleTextAlign();
    _padding = await UserPreferences.getSubtitlePadding();

    setState(() {
      _isLoading = false;
    });
  }

  Future<void> _saveSettings() async {
    await UserPreferences.setSubtitleFontSize(_fontSize);
    await UserPreferences.setSubtitleHeight(_height);
    await UserPreferences.setSubtitleLetterSpacing(_letterSpacing);
    await UserPreferences.setSubtitleWordSpacing(_wordSpacing);
    await UserPreferences.setSubtitleTextColor(_textColor);
    await UserPreferences.setSubtitleBackgroundColor(_backgroundColor);
    await UserPreferences.setSubtitleFontWeight(_fontWeight);
    await UserPreferences.setSubtitleTextAlign(_textAlign);
    await UserPreferences.setSubtitlePadding(_padding);
  }

  Future<void> _updateFontSize(double value) async {
    setState(() => _fontSize = value);
    await _saveSettings();
  }

  void _updateHeight(double value) {
    setState(() => _height = value);
    _saveSettings();
  }

  void _updateLetterSpacing(double value) {
    setState(() => _letterSpacing = value);
    _saveSettings();
  }

  void _updateWordSpacing(double value) {
    setState(() => _wordSpacing = value);
    _saveSettings();
  }

  void _updatePadding(double value) {
    setState(() => _padding = value);
    _saveSettings();
  }

  void _updateTextColor(Color color) {
    setState(() => _textColor = color);
    _saveSettings();
  }

  void _updateBackgroundColor(Color color) {
    setState(() => _backgroundColor = color);
    _saveSettings();
  }

  void _updateFontWeight(FontWeight weight) {
    setState(() => _fontWeight = weight);
    _saveSettings();
  }

  void _updateTextAlign(TextAlign align) {
    setState(() => _textAlign = align);
    _saveSettings();
  }

  void _resetToDefaults() {
    setState(() {
      _fontSize = 32.0;
      _height = 1.4;
      _letterSpacing = 0.0;
      _wordSpacing = 0.0;
      _textColor = const Color(0xffffffff);
      _backgroundColor = const Color(0xaa000000);
      _fontWeight = FontWeight.normal;
      _textAlign = TextAlign.center;
      _padding = 24.0;
    });
    _saveSettings();
  }

  Widget _buildPreviewCard() {
    return Container(
      width: double.infinity,
      color: Theme.of(context).scaffoldBackgroundColor,
      child: Card(
        margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(
                    Icons.visibility,
                    size: 18,
                    color: Theme.of(context).colorScheme.primary,
                  ),
                  const SizedBox(width: 8),
                  Text(
                    context.loc.preview,
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Container(
                width: double.infinity,
                padding: EdgeInsets.all(_padding),
                decoration: BoxDecoration(
                  color: Colors.grey[900],
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  context.loc.sample_text,
                  textAlign: _textAlign,
                  textScaler: TextScaler.linear(.38),
                  style: TextStyle(
                    fontSize: _fontSize,
                    height: _height,
                    letterSpacing: _letterSpacing,
                    wordSpacing: _wordSpacing,
                    color: _textColor,
                    backgroundColor: _backgroundColor,
                    fontWeight: _fontWeight,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(context.loc.subtitle_settings),
        actions: [
          if (!_isLoading)
            TextButton(
              onPressed: _resetToDefaults,
              child: Text(context.loc.reset),
            ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : Column(
              children: [
                _buildPreviewCard(),

                Expanded(
                  child: ListView(
                    padding: const EdgeInsets.only(bottom: 16),
                    children: [
                      Card(
                        margin: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 4,
                        ),
                        child: Column(
                          children: [
                            Padding(
                              padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
                              child: Row(
                                children: [
                                  Icon(
                                    Icons.text_fields,
                                    size: 18,
                                    color: Theme.of(
                                      context,
                                    ).colorScheme.primary,
                                  ),
                                  const SizedBox(width: 8),
                                  Text(
                                    context.loc.font_settings,
                                    style: Theme.of(context)
                                        .textTheme
                                        .titleSmall
                                        ?.copyWith(fontWeight: FontWeight.w600),
                                  ),
                                ],
                              ),
                            ),
                            SliderTileWidget(
                              icon: Icons.format_size,
                              label: context.loc.font_size,
                              value: _fontSize,
                              min: 24,
                              max: 96,
                              divisions: 18,
                              onChanged: _updateFontSize,
                            ),
                            const Divider(height: 1),
                            SliderTileWidget(
                              icon: Icons.format_line_spacing,
                              label: context.loc.font_height,
                              value: _height,
                              min: 1.0,
                              max: 2.5,
                              divisions: 15,
                              onChanged: _updateHeight,
                            ),
                            const Divider(height: 1),
                            SliderTileWidget(
                              icon: Icons.space_bar,
                              label: context.loc.letter_spacing,
                              value: _letterSpacing,
                              min: -2.0,
                              max: 5.0,
                              divisions: 70,
                              onChanged: _updateLetterSpacing,
                            ),
                            const Divider(height: 1),
                            SliderTileWidget(
                              icon: Icons.format_textdirection_l_to_r,
                              label: context.loc.word_spacing,
                              value: _wordSpacing,
                              min: -2.0,
                              max: 10.0,
                              divisions: 120,
                              onChanged: _updateWordSpacing,
                            ),
                            const Divider(height: 1),
                            SliderTileWidget(
                              icon: Icons.padding,
                              label: context.loc.padding,
                              value: _padding,
                              min: 8.0,
                              max: 48.0,
                              divisions: 40,
                              onChanged: _updatePadding,
                            ),
                          ],
                        ),
                      ),

                      const SizedBox(height: 8),

                      Card(
                        margin: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 4,
                        ),
                        child: Column(
                          children: [
                            Padding(
                              padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
                              child: Row(
                                children: [
                                  Icon(
                                    Icons.palette,
                                    size: 18,
                                    color: Theme.of(
                                      context,
                                    ).colorScheme.primary,
                                  ),
                                  const SizedBox(width: 8),
                                  Text(
                                    context.loc.color_settings,
                                    style: Theme.of(context)
                                        .textTheme
                                        .titleSmall
                                        ?.copyWith(fontWeight: FontWeight.w600),
                                  ),
                                ],
                              ),
                            ),
                            ColorPickerTileWidget(
                              title: context.loc.text_color,
                              icon: Icons.format_color_text,
                              color: _textColor,
                              onChanged: _updateTextColor,
                            ),
                            const Divider(height: 1),
                            ColorPickerTileWidget(
                              title: context.loc.background_color,
                              icon: Icons.format_color_fill,
                              color: _backgroundColor,
                              onChanged: _updateBackgroundColor,
                            ),
                          ],
                        ),
                      ),

                      const SizedBox(height: 8),
                      Card(
                        margin: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 4,
                        ),
                        child: Column(
                          children: [
                            Padding(
                              padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
                              child: Row(
                                children: [
                                  Icon(
                                    Icons.style,
                                    size: 18,
                                    color: Theme.of(
                                      context,
                                    ).colorScheme.primary,
                                  ),
                                  const SizedBox(width: 8),
                                  Text(
                                    context.loc.style_settings,
                                    style: Theme.of(context)
                                        .textTheme
                                        .titleSmall
                                        ?.copyWith(fontWeight: FontWeight.w600),
                                  ),
                                ],
                              ),
                            ),
                            DropdownTileWidget<FontWeight>(
                              icon: Icons.format_bold,
                              label: context.loc.font_weight,
                              value: _fontWeight,
                              items: [
                                DropdownMenuItem(
                                  value: FontWeight.w300,
                                  child: Text(context.loc.thin),
                                ),
                                DropdownMenuItem(
                                  value: FontWeight.normal,
                                  child: Text(context.loc.normal),
                                ),
                                DropdownMenuItem(
                                  value: FontWeight.w500,
                                  child: Text(context.loc.medium),
                                ),
                                DropdownMenuItem(
                                  value: FontWeight.bold,
                                  child: Text(context.loc.bold),
                                ),
                                DropdownMenuItem(
                                  value: FontWeight.w900,
                                  child: Text(context.loc.extreme_bold),
                                ),
                              ],
                              onChanged: (v) => _updateFontWeight(v!),
                            ),
                            const Divider(height: 1),
                            DropdownTileWidget<TextAlign>(
                              icon: Icons.format_align_center,
                              label: context.loc.text_align,
                              value: _textAlign,
                              items: [
                                DropdownMenuItem(
                                  value: TextAlign.left,
                                  child: Text(context.loc.left),
                                ),
                                DropdownMenuItem(
                                  value: TextAlign.center,
                                  child: Text(context.loc.center),
                                ),
                                DropdownMenuItem(
                                  value: TextAlign.right,
                                  child: Text(context.loc.right),
                                ),
                                DropdownMenuItem(
                                  value: TextAlign.justify,
                                  child: Text(context.loc.justify),
                                ),
                              ],
                              onChanged: (v) => _updateTextAlign(v!),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
    );
  }
}
