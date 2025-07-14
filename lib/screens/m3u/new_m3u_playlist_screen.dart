import 'package:another_iptv_player/controllers/m3u_controller.dart';
import 'package:another_iptv_player/models/playlist_model.dart';
import 'package:another_iptv_player/screens/m3u/m3u_data_loader_screen.dart';
import 'package:another_iptv_player/services/m3u_parser.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:media_kit_video/media_kit_video_controls/src/controls/methods/video_state.dart';
import 'package:provider/provider.dart';
import '../../../../controllers/playlist_controller.dart';
import '../../models/m3u_item.dart';

class NewM3uPlaylistScreen extends StatefulWidget {
  const NewM3uPlaylistScreen({super.key});

  @override
  NewM3uPlaylistScreenState createState() => NewM3uPlaylistScreenState();
}

class NewM3uPlaylistScreenState extends State<NewM3uPlaylistScreen> {
  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController(text: 'M3U Playlist-1');
  final _urlController = TextEditingController();

  bool _isUrlSource = true;
  bool _isFormValid = false;
  String? _selectedFilePath;
  String? _selectedFileName;

  @override
  void initState() {
    super.initState();
    _nameController.addListener(_validateForm);
    _urlController.addListener(_validateForm);
  }

  @override
  void dispose() {
    _nameController.dispose();
    _urlController.dispose();
    super.dispose();
  }

  void _validateForm() {
    setState(() {
      _isFormValid =
          _nameController.text.trim().isNotEmpty &&
          (_isUrlSource
              ? _urlController.text.trim().isNotEmpty
              : _selectedFilePath != null);
    });
  }

  void _onSourceTypeChanged(bool isUrl) {
    setState(() {
      _isUrlSource = isUrl;
      if (isUrl) {
        _selectedFilePath = null;
        _selectedFileName = null;
      } else {
        _urlController.clear();
      }
    });
    _validateForm();
  }

  Future<void> _pickFile() async {
    try {
      FilePickerResult? result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['m3u', 'm3u8'],
        allowMultiple: false,
        withData: false,
        withReadStream: false,
      );

      if (result != null) {
        setState(() {
          _selectedFilePath = result.files.single.path;
          _selectedFileName = result.files.single.name;
        });
        _validateForm();
      }
    } catch (e) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Dosya seçilirken hata oluştu')));
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Scaffold(
      appBar: AppBar(title: Text('M3U Playlist')),
      body: Consumer<PlaylistController>(
        builder: (context, controller, child) {
          return SingleChildScrollView(
            padding: EdgeInsets.all(24),
            child: Form(
              key: _formKey,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _buildHeader(colorScheme),
                  SizedBox(height: 32),
                  _buildPlaylistNameField(colorScheme),
                  SizedBox(height: 20),
                  _buildSourceTypeSelector(colorScheme),
                  SizedBox(height: 20),
                  _isUrlSource
                      ? _buildUrlField(colorScheme)
                      : _buildFilePickerField(colorScheme),
                  SizedBox(height: 32),
                  _buildSaveButton(controller, colorScheme),
                  if (controller.error != null) ...[
                    SizedBox(height: 20),
                    _buildErrorCard(controller.error!, colorScheme),
                  ],
                  SizedBox(height: 20),
                  _buildInfoCard(colorScheme),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _buildHeader(ColorScheme colorScheme) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: 60,
          height: 60,
          decoration: BoxDecoration(
            color: Colors.green,
            borderRadius: BorderRadius.circular(30),
          ),
          child: Icon(Icons.playlist_play, size: 30, color: Colors.white),
        ),
        SizedBox(height: 16),
        Text(
          'M3U Playlist',
          style: TextStyle(
            fontSize: 26,
            fontWeight: FontWeight.bold,
            color: colorScheme.onSurface,
          ),
        ),
        SizedBox(height: 8),
        Text(
          'M3U playlist dosyası veya URL\'si ile IPTV kanallarını yükleyin',
          style: TextStyle(
            fontSize: 16,
            color: colorScheme.onSurface.withOpacity(0.7),
          ),
        ),
      ],
    );
  }

  Widget _buildPlaylistNameField(ColorScheme colorScheme) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Playlist Adı',
          style: TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.w600,
            color: colorScheme.onSurface,
          ),
        ),
        SizedBox(height: 8),
        TextFormField(
          controller: _nameController,
          decoration: InputDecoration(
            hintText: 'Playlist adını girin',
            prefixIcon: Icon(Icons.playlist_add, color: colorScheme.primary),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: BorderSide(color: colorScheme.outline),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: BorderSide(color: colorScheme.primary, width: 2),
            ),
            filled: true,
            fillColor: colorScheme.surface,
          ),
          validator: (value) {
            if (value == null || value.trim().isEmpty) {
              return 'Playlist adı gereklidir';
            }
            if (value.trim().length < 2) {
              return 'Playlist adı en az 2 karakter olmalıdır';
            }
            return null;
          },
        ),
      ],
    );
  }

  Widget _buildSourceTypeSelector(ColorScheme colorScheme) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Kaynak Türü',
          style: TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.w600,
            color: colorScheme.onSurface,
          ),
        ),
        SizedBox(height: 12),
        Container(
          decoration: BoxDecoration(
            border: Border.all(color: colorScheme.outline),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Row(
            children: [
              Expanded(
                child: GestureDetector(
                  onTap: () => _onSourceTypeChanged(true),
                  child: Container(
                    padding: EdgeInsets.symmetric(vertical: 16, horizontal: 20),
                    decoration: BoxDecoration(
                      color: _isUrlSource
                          ? colorScheme.primary
                          : Colors.transparent,
                      borderRadius: BorderRadius.only(
                        topLeft: Radius.circular(12),
                        bottomLeft: Radius.circular(12),
                      ),
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(
                          Icons.link,
                          color: _isUrlSource
                              ? colorScheme.onPrimary
                              : colorScheme.onSurface,
                        ),
                        SizedBox(width: 8),
                        Text(
                          'URL',
                          style: TextStyle(
                            color: _isUrlSource
                                ? colorScheme.onPrimary
                                : colorScheme.onSurface,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
              Container(width: 1, height: 56, color: colorScheme.outline),
              Expanded(
                child: GestureDetector(
                  onTap: () => _onSourceTypeChanged(false),
                  child: Container(
                    padding: EdgeInsets.symmetric(vertical: 16, horizontal: 20),
                    decoration: BoxDecoration(
                      color: !_isUrlSource
                          ? colorScheme.primary
                          : Colors.transparent,
                      borderRadius: BorderRadius.only(
                        topRight: Radius.circular(12),
                        bottomRight: Radius.circular(12),
                      ),
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(
                          Icons.folder,
                          color: !_isUrlSource
                              ? colorScheme.onPrimary
                              : colorScheme.onSurface,
                        ),
                        SizedBox(width: 8),
                        Text(
                          'Dosya',
                          style: TextStyle(
                            color: !_isUrlSource
                                ? colorScheme.onPrimary
                                : colorScheme.onSurface,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildUrlField(ColorScheme colorScheme) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'M3U URL',
          style: TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.w600,
            color: colorScheme.onSurface,
          ),
        ),
        SizedBox(height: 8),
        TextFormField(
          controller: _urlController,
          keyboardType: TextInputType.url,
          decoration: InputDecoration(
            hintText: 'http://example.com/playlist.m3u',
            prefixIcon: Icon(Icons.link, color: colorScheme.primary),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: BorderSide(color: colorScheme.outline),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: BorderSide(color: colorScheme.primary, width: 2),
            ),
            filled: true,
            fillColor: colorScheme.surface,
          ),
          validator: (value) {
            if (value == null || value.trim().isEmpty) {
              return 'M3U URL gereklidir';
            }

            final uri = Uri.tryParse(value.trim());
            if (uri == null || !uri.hasScheme || !uri.hasAuthority) {
              return 'Geçerli bir URL formatı girin';
            }

            if (!['http', 'https'].contains(uri.scheme)) {
              return 'URL http:// veya https:// ile başlamalıdır';
            }

            return null;
          },
        ),
      ],
    );
  }

  Widget _buildFilePickerField(ColorScheme colorScheme) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'M3U Dosyası',
          style: TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.w600,
            color: colorScheme.onSurface,
          ),
        ),
        SizedBox(height: 8),
        GestureDetector(
          onTap: _pickFile,
          child: Container(
            width: double.infinity,
            padding: EdgeInsets.symmetric(vertical: 16, horizontal: 16),
            decoration: BoxDecoration(
              border: Border.all(color: colorScheme.outline),
              borderRadius: BorderRadius.circular(12),
              color: colorScheme.surface,
            ),
            child: Row(
              children: [
                Icon(
                  _selectedFilePath != null ? Icons.check_circle : Icons.folder,
                  color: _selectedFilePath != null
                      ? Colors.green
                      : colorScheme.primary,
                ),
                SizedBox(width: 12),
                Expanded(
                  child: Text(
                    _selectedFilePath != null
                        ? _selectedFileName ?? 'Dosya seçildi'
                        : 'M3U dosyası seçin (.m3u, .m3u8)',
                    style: TextStyle(
                      color: _selectedFilePath != null
                          ? colorScheme.onSurface
                          : colorScheme.onSurface.withOpacity(0.6),
                    ),
                  ),
                ),
                Icon(
                  Icons.arrow_forward_ios,
                  size: 16,
                  color: colorScheme.onSurface.withOpacity(0.6),
                ),
              ],
            ),
          ),
        ),
        if (_selectedFilePath == null && !_isUrlSource)
          Padding(
            padding: EdgeInsets.only(top: 8),
            child: Text(
              'Lütfen bir M3U dosyası seçin',
              style: TextStyle(color: colorScheme.error, fontSize: 12),
            ),
          ),
      ],
    );
  }

  Widget _buildSaveButton(
    PlaylistController controller,
    ColorScheme colorScheme,
  ) {
    return SizedBox(
      height: 56,
      child: ElevatedButton(
        onPressed: controller.isLoading
            ? null
            : (_isFormValid ? _savePlaylist : null),
        style: ElevatedButton.styleFrom(
          backgroundColor: colorScheme.primary,
          foregroundColor: colorScheme.onPrimary,
          disabledBackgroundColor: colorScheme.onSurface.withOpacity(0.12),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
          elevation: controller.isLoading ? 0 : 2,
        ),
        child: controller.isLoading
            ? Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      valueColor: AlwaysStoppedAnimation<Color>(
                        colorScheme.onPrimary,
                      ),
                    ),
                  ),
                  SizedBox(width: 12),
                  Text(
                    'İşlem yapılıyor...',
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
                  ),
                ],
              )
            : Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.save, size: 20),
                  SizedBox(width: 8),
                  Text(
                    'Playlist Oluştur',
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
                  ),
                ],
              ),
      ),
    );
  }

  Widget _buildErrorCard(String error, ColorScheme colorScheme) {
    return Container(
      padding: EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: colorScheme.errorContainer,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: colorScheme.error),
      ),
      child: Row(
        children: [
          Icon(Icons.error_outline, color: colorScheme.error),
          SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Hata Oluştu',
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    color: colorScheme.onErrorContainer,
                  ),
                ),
                SizedBox(height: 4),
                Text(
                  error,
                  style: TextStyle(
                    color: colorScheme.onErrorContainer,
                    fontSize: 14,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildInfoCard(ColorScheme colorScheme) {
    return Container(
      padding: EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: colorScheme.primaryContainer,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: colorScheme.primary),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.info_outline, color: colorScheme.primary, size: 20),
              SizedBox(width: 8),
              Text(
                'Bilgi',
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                  color: colorScheme.onPrimaryContainer,
                ),
              ),
            ],
          ),
          SizedBox(height: 8),
          Text(
            'Tüm veriler cihazınızda güvenli şekilde saklanır.\nDesteklenen formatlar: .m3u, .m3u8\nURL formatı: http:// veya https:// ile başlamalıdır.',
            style: TextStyle(
              color: colorScheme.onPrimaryContainer,
              fontSize: 13,
              height: 1.4,
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _savePlaylist() async {
    if (_formKey.currentState!.validate()) {
      final playlistController = Provider.of<PlaylistController>(
        context,
        listen: false,
      );

      playlistController.clearError();

      print('Playlist Name: ${_nameController.text.trim()}');
      print('Is URL Source: $_isUrlSource');

      var playlist = await playlistController.createPlaylist(
        name: _nameController.text.trim(),
        type: PlaylistType.m3u,
        url: _isUrlSource ? _urlController.text : _selectedFilePath,
      );

      List<M3uItem> m3uItems = [];
      if (_isUrlSource) {
        print('URL: ${_urlController.text.trim()}');
        m3uItems = await M3uParser.parseUrl(playlist!.id, _urlController.text);
      } else {
        print('File Path: $_selectedFilePath');
        print('File Name: $_selectedFileName');
        m3uItems = await M3uParser.parseFile(playlist!.id, _selectedFilePath!);
      }

      if (m3uItems.length == 0) {
        playlistController.setError('M3U Error');
        return;
      }

      Navigator.pushReplacement(
        context,
        MaterialPageRoute(
          builder: (context) =>
              M3uDataLoaderScreen(playlist: playlist!, m3uItems: m3uItems),
        ),
      );
    }
  }
}
