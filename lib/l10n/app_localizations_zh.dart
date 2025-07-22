// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for Chinese (`zh`).
class AppLocalizationsZh extends AppLocalizations {
  AppLocalizationsZh([String locale = 'zh']) : super(locale);

  @override
  String get slogan => '开源IPTV播放器';

  @override
  String get search => '搜索';

  @override
  String get search_live_stream => '搜索直播';

  @override
  String get search_movie => '搜索电影';

  @override
  String get search_series => '搜索剧集';

  @override
  String get not_found_in_category => '此分类中未找到内容';

  @override
  String get live_stream_not_found => '未找到直播';

  @override
  String get movie_not_found => '未找到电影';

  @override
  String get see_all => '查看全部';

  @override
  String get preview => '预览';

  @override
  String get info => '信息';

  @override
  String get close => '关闭';

  @override
  String get reset => '重置';

  @override
  String get delete => '删除';

  @override
  String get cancel => '取消';

  @override
  String get refresh => '刷新';

  @override
  String get back => '返回';

  @override
  String get clear => '清除';

  @override
  String get clear_all => '全部清除';

  @override
  String get day => '天';

  @override
  String get clear_all_confirmation_message => '您确定要删除所有历史记录吗？';

  @override
  String get try_again => '重试';

  @override
  String get history => '历史记录';

  @override
  String get history_empty_message => '您观看的视频将显示在这里';

  @override
  String get live => '直播';

  @override
  String get live_streams => '直播频道';

  @override
  String get on_live => '直播中';

  @override
  String get other_channels => '其他频道';

  @override
  String get movies => '电影';

  @override
  String get movie => '电影';

  @override
  String get series_singular => '剧集';

  @override
  String get series_plural => '剧集';

  @override
  String get category_id => '分类ID';

  @override
  String get channel_information => '频道信息';

  @override
  String get channel_id => '频道ID';

  @override
  String get series_id => '剧集ID';

  @override
  String get quality => '画质';

  @override
  String get stream_type => '流类型';

  @override
  String get format => '格式';

  @override
  String get season => '季';

  @override
  String episode_count(Object count) {
    return '$count集';
  }

  @override
  String duration(Object duration) {
    return '时长：$duration';
  }

  @override
  String get episode_duration => '集时长';

  @override
  String get creation_date => '添加日期';

  @override
  String get release_date => '发布日期';

  @override
  String get genre => '类型';

  @override
  String get cast => '演员';

  @override
  String get description => '描述';

  @override
  String get video_track => '视频轨道';

  @override
  String get audio_track => '音频轨道';

  @override
  String get subtitle_track => '字幕轨道';

  @override
  String get settings => '设置';

  @override
  String get general_settings => '常规设置';

  @override
  String get app_language => '应用语言';

  @override
  String get continue_on_background => '后台继续播放';

  @override
  String get continue_on_background_description => '应用在后台时继续播放';

  @override
  String get refresh_contents => '刷新内容';

  @override
  String get subtitle_settings => '字幕设置';

  @override
  String get subtitle_settings_description => '自定义字幕外观';

  @override
  String get sample_text => '示例字幕文本\n将显示为这样';

  @override
  String get font_settings => '字体设置';

  @override
  String get font_size => '字体大小';

  @override
  String get font_height => '行高';

  @override
  String get letter_spacing => '字符间距';

  @override
  String get word_spacing => '词间距';

  @override
  String get padding => '内边距';

  @override
  String get color_settings => '颜色设置';

  @override
  String get text_color => '文字颜色';

  @override
  String get background_color => '背景颜色';

  @override
  String get style_settings => '样式设置';

  @override
  String get font_weight => '字体粗细';

  @override
  String get thin => '细';

  @override
  String get normal => '正常';

  @override
  String get medium => '中等';

  @override
  String get bold => '粗体';

  @override
  String get extreme_bold => '超粗体';

  @override
  String get text_align => '文本对齐';

  @override
  String get left => '左对齐';

  @override
  String get center => '居中';

  @override
  String get right => '右对齐';

  @override
  String get justify => '两端对齐';

  @override
  String get pick_color => '选择颜色';

  @override
  String get my_playlists => '我的播放列表';

  @override
  String get create_new_playlist => '创建新播放列表';

  @override
  String get loading_playlists => '正在加载播放列表...';

  @override
  String get playlist_list => '播放列表';

  @override
  String get playlist_information => '播放列表信息';

  @override
  String get playlist_name => '播放列表名称';

  @override
  String get playlist_name_placeholder => '输入播放列表名称';

  @override
  String get playlist_name_required => '播放列表名称为必填项';

  @override
  String get playlist_name_min_2 => '名称至少需要2个字符';

  @override
  String playlist_deleted(Object name) {
    return '$name 已删除';
  }

  @override
  String get playlist_delete_confirmation_title => '删除播放列表';

  @override
  String playlist_delete_confirmation_message(Object name) {
    return '您确定要删除播放列表 \'$name\' 吗？\n此操作无法撤销。';
  }

  @override
  String get empty_playlist_title => '暂无播放列表';

  @override
  String get empty_playlist_message =>
      '从创建您的第一个播放列表开始。\n您可以添加 Xtream Code 或 M3U 格式的播放列表。';

  @override
  String get empty_playlist_button => '创建我的第一个播放列表';

  @override
  String get select_playlist_type => '选择播放列表类型';

  @override
  String get select_playlist_message => '选择您要创建的播放列表类型';

  @override
  String get xtream_code_title => '使用API URL、用户名和密码连接';

  @override
  String get xtream_code_description => '使用您的IPTV提供商信息轻松连接';

  @override
  String get select_playlist_type_footer => '您的播放列表信息安全存储在设备上。';

  @override
  String get api_url => 'API URL';

  @override
  String get api_url_required => 'API URL为必填项';

  @override
  String get username => '用户名';

  @override
  String get username_placeholder => '输入您的用户名';

  @override
  String get username_required => '用户名为必填项';

  @override
  String get username_min_3 => '用户名至少需要3个字符';

  @override
  String get password => '密码';

  @override
  String get password_placeholder => '输入您的密码';

  @override
  String get password_required => '密码为必填项';

  @override
  String get password_min_3 => '密码至少需要3个字符';

  @override
  String get server_url => '服务器URL';

  @override
  String get submitting => '正在保存...';

  @override
  String get submit_create_playlist => '保存播放列表';

  @override
  String get subscription_details => '订阅详情';

  @override
  String subscription_remaining_day(Object days) {
    return '订阅：$days';
  }

  @override
  String get remaining_day_title => '剩余时间';

  @override
  String remaining_day(Object days) {
    return '$days天';
  }

  @override
  String get connected => '已连接';

  @override
  String get no_connection => '无连接';

  @override
  String get expired => '已过期';

  @override
  String get active_connection => '活跃连接';

  @override
  String get maximum_connection => '最大连接数';

  @override
  String get server_information => '服务器信息';

  @override
  String get timezone => '时区';

  @override
  String get server_message => '服务器消息';

  @override
  String get all_datas_are_stored_in_device => '所有数据安全存储在您的设备上';

  @override
  String get url_format_validate_message => 'URL格式应为 http://服务器:端口';

  @override
  String get url_format_validate_error => '请输入有效的URL（必须以http://或https://开头）';

  @override
  String get playlist_name_already_exists => '此名称的播放列表已存在';

  @override
  String get invalid_credentials => '无法从您的IPTV提供商获得响应，请检查您的信息';

  @override
  String get error_occurred => '发生错误';

  @override
  String get connecting => '正在连接';

  @override
  String get preparing_categories => '正在准备分类';

  @override
  String preparing_categories_exception(Object error) {
    return '无法加载分类：$error';
  }

  @override
  String get preparing_live_streams => '正在加载直播频道';

  @override
  String get preparing_live_streams_exception_1 => '无法获取直播频道';

  @override
  String preparing_live_streams_exception_2(Object error) {
    return '加载直播频道时出错：$error';
  }

  @override
  String get preparing_movies => '正在打开电影库';

  @override
  String get preparing_movies_exception_1 => '无法获取电影';

  @override
  String preparing_movies_exception_2(Object error) {
    return '加载电影时出错：$error';
  }

  @override
  String get preparing_series => '正在准备剧集库';

  @override
  String get preparing_series_exception_1 => '无法获取剧集';

  @override
  String preparing_series_exception_2(Object error) {
    return '加载剧集时出错：$error';
  }

  @override
  String get preparing_user_info_exception_1 => '无法获取用户信息';

  @override
  String preparing_user_info_exception_2(Object error) {
    return '加载用户信息时出错：$error';
  }

  @override
  String get m3u_playlist_title => '使用M3U文件或URL添加播放列表';

  @override
  String get m3u_playlist_description => '支持传统M3U格式文件';

  @override
  String get m3u_playlist => 'M3U播放列表';

  @override
  String get m3u_playlist_load_description => '使用M3U播放列表文件或URL加载IPTV频道';

  @override
  String get playlist_name_hint => '输入播放列表名称';

  @override
  String get playlist_name_min_length => '播放列表名称至少需要2个字符';

  @override
  String get source_type => '源类型';

  @override
  String get url => '网址';

  @override
  String get file => '文件';

  @override
  String get m3u_url => 'M3U网址';

  @override
  String get m3u_url_hint => 'http://example.com/playlist.m3u';

  @override
  String get m3u_url_required => '需要M3U网址';

  @override
  String get url_format_error => '请输入有效的网址格式';

  @override
  String get url_scheme_error => '网址必须以http://或https://开头';

  @override
  String get m3u_file => 'M3U文件';

  @override
  String get file_selected => '文件已选择';

  @override
  String get select_m3u_file => '选择M3U文件（.m3u, .m3u8）';

  @override
  String get please_select_m3u_file => '请选择一个M3U文件';

  @override
  String get file_selection_error => '选择文件时出错';

  @override
  String get processing => '正在处理...';

  @override
  String get create_playlist => '创建播放列表';

  @override
  String get error_occurred_title => '发生错误';

  @override
  String get m3u_info_message =>
      '所有数据都安全存储在您的设备上。\n支持的格式：.m3u, .m3u8\n网址格式：必须以http://或https://开头';

  @override
  String get m3u_parse_error => 'M3U解析错误';

  @override
  String get loading_m3u => '正在加载M3U';

  @override
  String get preparing_m3u_exception_no_source => '未找到M3U源';

  @override
  String get preparing_m3u_exception_empty => 'M3U文件为空';

  @override
  String preparing_m3u_exception_parse(Object error) {
    return 'M3U解析错误：$error';
  }

  @override
  String get not_categorized => '未分类';

  @override
  String get loading_lists => '正在加载列表...';

  @override
  String get all => '全部';

  @override
  String iptv_channels_count(Object count) {
    return 'IPTV频道（$count）';
  }

  @override
  String get unknown_channel => '未知频道';

  @override
  String get live_content => '直播';

  @override
  String get movie_content => '电影';

  @override
  String get series_content => '剧集';

  @override
  String get media_content => '媒体';

  @override
  String get m3u_error => 'M3U错误';

  @override
  String get episode_short => '集';

  @override
  String season_number(Object number) {
    return '第$number季';
  }

  @override
  String get image_loading => '正在加载图片...';

  @override
  String get image_not_found => '图片未找到';
}
