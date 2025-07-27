// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for Portuguese (`pt`).
class AppLocalizationsPt extends AppLocalizations {
  AppLocalizationsPt([String locale = 'pt']) : super(locale);

  @override
  String get slogan => 'Player IPTV de Código Aberto';

  @override
  String get search => 'Pesquisar';

  @override
  String get search_live_stream => 'Pesquisar transmissão ao vivo';

  @override
  String get search_movie => 'Pesquisar filme';

  @override
  String get search_series => 'Pesquisar série';

  @override
  String get not_found_in_category =>
      'Nenhum conteúdo encontrado nesta categoria';

  @override
  String get live_stream_not_found => 'Nenhuma transmissão ao vivo encontrada';

  @override
  String get movie_not_found => 'Nenhum filme encontrado';

  @override
  String get see_all => 'Ver Todos';

  @override
  String get preview => 'Visualizar';

  @override
  String get info => 'Informações';

  @override
  String get close => 'Fechar';

  @override
  String get reset => 'Redefinir';

  @override
  String get delete => 'Excluir';

  @override
  String get cancel => 'Cancelar';

  @override
  String get refresh => 'Atualizar';

  @override
  String get back => 'Voltar';

  @override
  String get clear => 'Limpar';

  @override
  String get clear_all => 'Limpar Tudo';

  @override
  String get day => 'Dia';

  @override
  String get clear_all_confirmation_message =>
      'Tem certeza de que deseja excluir todo o histórico?';

  @override
  String get try_again => 'Tentar Novamente';

  @override
  String get history => 'Histórico';

  @override
  String get history_empty_message => 'Seus vídeos assistidos aparecerão aqui';

  @override
  String get live => 'Ao Vivo';

  @override
  String get live_streams => 'Transmissões ao Vivo';

  @override
  String get on_live => 'Ao Vivo';

  @override
  String get other_channels => 'Outros Canais';

  @override
  String get movies => 'Filmes';

  @override
  String get movie => 'Filme';

  @override
  String get series_singular => 'Série';

  @override
  String get series_plural => 'Séries';

  @override
  String get category_id => 'ID da Categoria';

  @override
  String get channel_information => 'Informações do Canal';

  @override
  String get channel_id => 'ID do Canal';

  @override
  String get series_id => 'ID da Série';

  @override
  String get quality => 'Qualidade';

  @override
  String get stream_type => 'Tipo de Transmissão';

  @override
  String get format => 'Formato';

  @override
  String get season => 'Temporadas';

  @override
  String episode_count(Object count) {
    return '$count Episódios';
  }

  @override
  String duration(Object duration) {
    return 'Duração: $duration';
  }

  @override
  String get episode_duration => 'Duração do Episódio';

  @override
  String get creation_date => 'Data de Adição';

  @override
  String get release_date => 'Data de Lançamento';

  @override
  String get genre => 'Gênero';

  @override
  String get cast => 'Elenco';

  @override
  String get description => 'Descrição';

  @override
  String get video_track => 'Faixa de Vídeo';

  @override
  String get audio_track => 'Faixa de Áudio';

  @override
  String get subtitle_track => 'Faixa de Legendas';

  @override
  String get settings => 'Configurações';

  @override
  String get general_settings => 'Configurações Gerais';

  @override
  String get app_language => 'Idioma do App';

  @override
  String get continue_on_background =>
      'Continuar Reproduzindo em Segundo Plano';

  @override
  String get continue_on_background_description =>
      'Continuar reproduzindo mesmo quando o app estiver em segundo plano';

  @override
  String get refresh_contents => 'Atualizar Conteúdo';

  @override
  String get subtitle_settings => 'Configurações de Legendas';

  @override
  String get subtitle_settings_description =>
      'Personalizar a aparência das legendas';

  @override
  String get sample_text => 'Texto de legenda de exemplo\nFicará assim';

  @override
  String get font_settings => 'Configurações de Fonte';

  @override
  String get font_size => 'Tamanho da Fonte';

  @override
  String get font_height => 'Altura da Linha';

  @override
  String get letter_spacing => 'Espaçamento de Letras';

  @override
  String get word_spacing => 'Espaçamento de Palavras';

  @override
  String get padding => 'Preenchimento';

  @override
  String get color_settings => 'Configurações de Cor';

  @override
  String get text_color => 'Cor do Texto';

  @override
  String get background_color => 'Cor de Fundo';

  @override
  String get style_settings => 'Configurações de Estilo';

  @override
  String get font_weight => 'Peso da Fonte';

  @override
  String get thin => 'Fino';

  @override
  String get normal => 'Normal';

  @override
  String get medium => 'Médio';

  @override
  String get bold => 'Negrito';

  @override
  String get extreme_bold => 'Extra Negrito';

  @override
  String get text_align => 'Alinhamento do Texto';

  @override
  String get left => 'Esquerda';

  @override
  String get center => 'Centro';

  @override
  String get right => 'Direita';

  @override
  String get justify => 'Justificar';

  @override
  String get pick_color => 'Escolher Cor';

  @override
  String get my_playlists => 'Minhas Playlists';

  @override
  String get create_new_playlist => 'Criar Nova Playlist';

  @override
  String get loading_playlists => 'Carregando Playlists...';

  @override
  String get playlist_list => 'Lista de Playlist';

  @override
  String get playlist_information => 'Informações da Playlist';

  @override
  String get playlist_name => 'Nome da Playlist';

  @override
  String get playlist_name_placeholder => 'Digite um nome para sua playlist';

  @override
  String get playlist_name_required => 'Nome da playlist é obrigatório';

  @override
  String get playlist_name_min_2 => 'O nome deve ter pelo menos 2 caracteres';

  @override
  String playlist_deleted(Object name) {
    return '$name excluída';
  }

  @override
  String get playlist_delete_confirmation_title => 'Excluir Playlist';

  @override
  String playlist_delete_confirmation_message(Object name) {
    return 'Tem certeza de que deseja excluir a playlist \'$name\'?\nEsta ação não pode ser desfeita.';
  }

  @override
  String get empty_playlist_title => 'Ainda Não Há Playlists';

  @override
  String get empty_playlist_message =>
      'Comece criando sua primeira playlist.\nVocê pode adicionar playlists no formato Xtream Code ou M3U.';

  @override
  String get empty_playlist_button => 'Criar Minha Primeira Playlist';

  @override
  String get favorites => 'Favoritos';

  @override
  String get see_all_favorites => 'Ver Todos';

  @override
  String get added_to_favorites => 'Adicionado aos favoritos';

  @override
  String get removed_from_favorites => 'Removido dos favoritos';

  @override
  String get select_playlist_type => 'Selecionar Tipo de Playlist';

  @override
  String get select_playlist_message =>
      'Escolha o tipo de playlist que deseja criar';

  @override
  String get xtream_code_title =>
      'Conectar com URL da API, Nome de Usuário e Senha';

  @override
  String get xtream_code_description =>
      'Conecte-se facilmente com as informações do seu provedor IPTV';

  @override
  String get select_playlist_type_footer =>
      'As informações da sua playlist são armazenadas com segurança no seu dispositivo.';

  @override
  String get api_url => 'URL da API';

  @override
  String get api_url_required => 'URL da API é obrigatória';

  @override
  String get username => 'Nome de Usuário';

  @override
  String get username_placeholder => 'Digite seu nome de usuário';

  @override
  String get username_required => 'Nome de usuário é obrigatório';

  @override
  String get username_min_3 =>
      'Nome de usuário deve ter pelo menos 3 caracteres';

  @override
  String get password => 'Senha';

  @override
  String get password_placeholder => 'Digite sua senha';

  @override
  String get password_required => 'Senha é obrigatória';

  @override
  String get password_min_3 => 'Senha deve ter pelo menos 3 caracteres';

  @override
  String get server_url => 'URL do Servidor';

  @override
  String get submitting => 'Salvando...';

  @override
  String get submit_create_playlist => 'Salvar Playlist';

  @override
  String get subscription_details => 'Detalhes da Assinatura';

  @override
  String subscription_remaining_day(Object days) {
    return 'Assinatura: $days';
  }

  @override
  String get remaining_day_title => 'Tempo Restante';

  @override
  String remaining_day(Object days) {
    return '$days Dias';
  }

  @override
  String get connected => 'Conectado';

  @override
  String get no_connection => 'Sem Conexão';

  @override
  String get expired => 'Expirado';

  @override
  String get active_connection => 'Conexão Ativa';

  @override
  String get maximum_connection => 'Conexão Máxima';

  @override
  String get server_information => 'Informações do Servidor';

  @override
  String get timezone => 'Fuso Horário';

  @override
  String get server_message => 'Mensagem do Servidor';

  @override
  String get all_datas_are_stored_in_device =>
      'Todos os dados são armazenados com segurança no seu dispositivo';

  @override
  String get url_format_validate_message =>
      'O formato da URL deve ser como http://servidor:porta';

  @override
  String get url_format_validate_error =>
      'Digite uma URL válida (deve começar com http:// ou https://)';

  @override
  String get playlist_name_already_exists =>
      'Já existe uma playlist com este nome';

  @override
  String get invalid_credentials =>
      'Não foi possível obter resposta do seu provedor IPTV, verifique suas informações';

  @override
  String get error_occurred => 'Ocorreu um erro';

  @override
  String get connecting => 'Conectando';

  @override
  String get preparing_categories => 'Preparando categorias';

  @override
  String preparing_categories_exception(Object error) {
    return 'Não foi possível carregar as categorias: $error';
  }

  @override
  String get preparing_live_streams => 'Carregando canais ao vivo';

  @override
  String get preparing_live_streams_exception_1 =>
      'Não foi possível obter os canais ao vivo';

  @override
  String preparing_live_streams_exception_2(Object error) {
    return 'Erro ao carregar canais ao vivo: $error';
  }

  @override
  String get preparing_movies => 'Abrindo biblioteca de filmes';

  @override
  String get preparing_movies_exception_1 => 'Não foi possível obter os filmes';

  @override
  String preparing_movies_exception_2(Object error) {
    return 'Erro ao carregar filmes: $error';
  }

  @override
  String get preparing_series => 'Preparando biblioteca de séries';

  @override
  String get preparing_series_exception_1 => 'Não foi possível obter as séries';

  @override
  String preparing_series_exception_2(Object error) {
    return 'Erro ao carregar séries: $error';
  }

  @override
  String get preparing_user_info_exception_1 =>
      'Não foi possível obter informações do usuário';

  @override
  String preparing_user_info_exception_2(Object error) {
    return 'Erro ao carregar informações do usuário: $error';
  }

  @override
  String get m3u_playlist_title => 'Adicionar playlist com arquivo M3U ou URL';

  @override
  String get m3u_playlist_description =>
      'Suporta arquivos de formato M3U tradicional';

  @override
  String get m3u_playlist => 'Playlist M3U';

  @override
  String get m3u_playlist_load_description =>
      'Carregar canais IPTV com arquivo de playlist M3U ou URL';

  @override
  String get playlist_name_hint => 'Digite o nome da playlist';

  @override
  String get playlist_name_min_length =>
      'O nome da playlist deve ter pelo menos 2 caracteres';

  @override
  String get source_type => 'Tipo de fonte';

  @override
  String get url => 'URL';

  @override
  String get file => 'Arquivo';

  @override
  String get m3u_url => 'URL M3U';

  @override
  String get m3u_url_hint => 'http://example.com/playlist.m3u';

  @override
  String get m3u_url_required => 'URL M3U é obrigatória';

  @override
  String get url_format_error => 'Digite um formato de URL válido';

  @override
  String get url_scheme_error => 'A URL deve começar com http:// ou https://';

  @override
  String get m3u_file => 'Arquivo M3U';

  @override
  String get file_selected => 'Arquivo selecionado';

  @override
  String get select_m3u_file => 'Selecionar arquivo M3U (.m3u, .m3u8)';

  @override
  String get please_select_m3u_file => 'Por favor, selecione um arquivo M3U';

  @override
  String get file_selection_error => 'Erro ao selecionar arquivo';

  @override
  String get processing => 'Processando...';

  @override
  String get create_playlist => 'Criar playlist';

  @override
  String get error_occurred_title => 'Erro ocorrido';

  @override
  String get m3u_info_message =>
      'Todos os dados são armazenados com segurança no seu dispositivo.\nFormatos suportados: .m3u, .m3u8\nFormato de URL: Deve começar com http:// ou https://';

  @override
  String get m3u_parse_error => 'Erro de análise M3U';

  @override
  String get loading_m3u => 'Carregando M3U';

  @override
  String get preparing_m3u_exception_no_source =>
      'Nenhuma fonte M3U encontrada';

  @override
  String get preparing_m3u_exception_empty => 'Arquivo M3U está vazio';

  @override
  String preparing_m3u_exception_parse(Object error) {
    return 'Erro de análise M3U: $error';
  }

  @override
  String get not_categorized => 'Não categorizado';

  @override
  String get loading_lists => 'Carregando listas...';

  @override
  String get all => 'Todos';

  @override
  String iptv_channels_count(Object count) {
    return 'Canais IPTV ($count)';
  }

  @override
  String get unknown_channel => 'Canal desconhecido';

  @override
  String get live_content => 'AO VIVO';

  @override
  String get movie_content => 'FILME';

  @override
  String get series_content => 'SÉRIE';

  @override
  String get media_content => 'MÍDIA';

  @override
  String get m3u_error => 'Erro M3U';

  @override
  String get episode_short => 'Ep';

  @override
  String season_number(Object number) {
    return 'Temporada $number';
  }

  @override
  String get image_loading => 'Carregando imagem...';

  @override
  String get image_not_found => 'Imagem não encontrada';
}
