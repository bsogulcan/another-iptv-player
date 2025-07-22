// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for Arabic (`ar`).
class AppLocalizationsAr extends AppLocalizations {
  AppLocalizationsAr([String locale = 'ar']) : super(locale);

  @override
  String get slogan => 'مشغل IPTV مفتوح المصدر';

  @override
  String get search => 'بحث';

  @override
  String get search_live_stream => 'البحث في البث المباشر';

  @override
  String get search_movie => 'البحث في الأفلام';

  @override
  String get search_series => 'البحث في المسلسلات';

  @override
  String get not_found_in_category => 'لم يتم العثور على محتوى في هذه الفئة';

  @override
  String get live_stream_not_found => 'لم يتم العثور على بث مباشر';

  @override
  String get movie_not_found => 'لم يتم العثور على فيلم';

  @override
  String get see_all => 'عرض الكل';

  @override
  String get preview => 'معاينة';

  @override
  String get info => 'معلومات';

  @override
  String get close => 'إغلاق';

  @override
  String get reset => 'إعادة تعيين';

  @override
  String get delete => 'حذف';

  @override
  String get cancel => 'إلغاء';

  @override
  String get refresh => 'تحديث';

  @override
  String get back => 'رجوع';

  @override
  String get clear => 'مسح';

  @override
  String get clear_all => 'مسح الكل';

  @override
  String get day => 'يوم';

  @override
  String get clear_all_confirmation_message =>
      'هل أنت متأكد من رغبتك في حذف كل السجل؟';

  @override
  String get try_again => 'حاول مرة أخرى';

  @override
  String get history => 'السجل';

  @override
  String get history_empty_message => 'ستظهر مقاطع الفيديو التي شاهدتها هنا';

  @override
  String get live => 'مباشر';

  @override
  String get live_streams => 'البث المباشر';

  @override
  String get on_live => 'مباشر';

  @override
  String get other_channels => 'قنوات أخرى';

  @override
  String get movies => 'أفلام';

  @override
  String get movie => 'فيلم';

  @override
  String get series_singular => 'مسلسل';

  @override
  String get series_plural => 'مسلسلات';

  @override
  String get category_id => 'معرف الفئة';

  @override
  String get channel_information => 'معلومات القناة';

  @override
  String get channel_id => 'معرف القناة';

  @override
  String get series_id => 'معرف المسلسل';

  @override
  String get quality => 'الجودة';

  @override
  String get stream_type => 'نوع البث';

  @override
  String get format => 'التنسيق';

  @override
  String get season => 'المواسم';

  @override
  String episode_count(Object count) {
    return '$count حلقة';
  }

  @override
  String duration(Object duration) {
    return 'المدة: $duration';
  }

  @override
  String get episode_duration => 'مدة الحلقة';

  @override
  String get creation_date => 'تاريخ الإضافة';

  @override
  String get release_date => 'تاريخ الإصدار';

  @override
  String get genre => 'النوع';

  @override
  String get cast => 'فريق التمثيل';

  @override
  String get description => 'الوصف';

  @override
  String get video_track => 'مسار الفيديو';

  @override
  String get audio_track => 'مسار الصوت';

  @override
  String get subtitle_track => 'مسار الترجمة';

  @override
  String get settings => 'الإعدادات';

  @override
  String get general_settings => 'الإعدادات العامة';

  @override
  String get app_language => 'لغة التطبيق';

  @override
  String get continue_on_background => 'متابعة التشغيل في الخلفية';

  @override
  String get continue_on_background_description =>
      'متابعة التشغيل حتى عندما يكون التطبيق في الخلفية';

  @override
  String get refresh_contents => 'تحديث المحتوى';

  @override
  String get subtitle_settings => 'إعدادات الترجمة';

  @override
  String get subtitle_settings_description => 'تخصيص مظهر الترجمة';

  @override
  String get sample_text => 'نص ترجمة تجريبي\nسيبدو هكذا';

  @override
  String get font_settings => 'إعدادات الخط';

  @override
  String get font_size => 'حجم الخط';

  @override
  String get font_height => 'ارتفاع السطر';

  @override
  String get letter_spacing => 'تباعد الأحرف';

  @override
  String get word_spacing => 'تباعد الكلمات';

  @override
  String get padding => 'الحشو';

  @override
  String get color_settings => 'إعدادات الألوان';

  @override
  String get text_color => 'لون النص';

  @override
  String get background_color => 'لون الخلفية';

  @override
  String get style_settings => 'إعدادات النمط';

  @override
  String get font_weight => 'سُمك الخط';

  @override
  String get thin => 'رفيع';

  @override
  String get normal => 'عادي';

  @override
  String get medium => 'متوسط';

  @override
  String get bold => 'عريض';

  @override
  String get extreme_bold => 'عريض جداً';

  @override
  String get text_align => 'محاذاة النص';

  @override
  String get left => 'يسار';

  @override
  String get center => 'وسط';

  @override
  String get right => 'يمين';

  @override
  String get justify => 'ضبط';

  @override
  String get pick_color => 'اختر لون';

  @override
  String get my_playlists => 'قوائم التشغيل الخاصة بي';

  @override
  String get create_new_playlist => 'إنشاء قائمة تشغيل جديدة';

  @override
  String get loading_playlists => 'جارٍ تحميل قوائم التشغيل...';

  @override
  String get playlist_list => 'قائمة التشغيل';

  @override
  String get playlist_information => 'معلومات قائمة التشغيل';

  @override
  String get playlist_name => 'اسم قائمة التشغيل';

  @override
  String get playlist_name_placeholder => 'أدخل اسماً لقائمة التشغيل';

  @override
  String get playlist_name_required => 'اسم قائمة التشغيل مطلوب';

  @override
  String get playlist_name_min_2 => 'يجب أن يحتوي الاسم على حرفين على الأقل';

  @override
  String playlist_deleted(Object name) {
    return 'تم حذف $name';
  }

  @override
  String get playlist_delete_confirmation_title => 'حذف قائمة التشغيل';

  @override
  String playlist_delete_confirmation_message(Object name) {
    return 'هل أنت متأكد من رغبتك في حذف قائمة التشغيل \'$name\'؟\nلا يمكن التراجع عن هذا الإجراء.';
  }

  @override
  String get empty_playlist_title => 'لا توجد قوائم تشغيل بعد';

  @override
  String get empty_playlist_message =>
      'ابدأ بإنشاء قائمة التشغيل الأولى.\nيمكنك إضافة قوائم تشغيل بتنسيق Xtream Code أو M3U.';

  @override
  String get empty_playlist_button => 'إنشاء قائمة التشغيل الأولى';

  @override
  String get select_playlist_type => 'اختر نوع قائمة التشغيل';

  @override
  String get select_playlist_message =>
      'اختر نوع قائمة التشغيل التي تريد إنشاءها';

  @override
  String get xtream_code_title =>
      'الاتصال باستخدام API URL واسم المستخدم وكلمة المرور';

  @override
  String get xtream_code_description =>
      'اتصل بسهولة باستخدام معلومات مزود IPTV الخاص بك';

  @override
  String get select_playlist_type_footer =>
      'يتم تخزين معلومات قائمة التشغيل بأمان على جهازك.';

  @override
  String get api_url => 'رابط API';

  @override
  String get api_url_required => 'رابط API مطلوب';

  @override
  String get username => 'اسم المستخدم';

  @override
  String get username_placeholder => 'أدخل اسم المستخدم';

  @override
  String get username_required => 'اسم المستخدم مطلوب';

  @override
  String get username_min_3 => 'يجب أن يحتوي اسم المستخدم على 3 أحرف على الأقل';

  @override
  String get password => 'كلمة المرور';

  @override
  String get password_placeholder => 'أدخل كلمة المرور';

  @override
  String get password_required => 'كلمة المرور مطلوبة';

  @override
  String get password_min_3 => 'يجب أن تحتوي كلمة المرور على 3 أحرف على الأقل';

  @override
  String get server_url => 'رابط الخادم';

  @override
  String get submitting => 'جارٍ الحفظ...';

  @override
  String get submit_create_playlist => 'حفظ قائمة التشغيل';

  @override
  String get subscription_details => 'تفاصيل الاشتراك';

  @override
  String subscription_remaining_day(Object days) {
    return 'الاشتراك: $days';
  }

  @override
  String get remaining_day_title => 'الوقت المتبقي';

  @override
  String remaining_day(Object days) {
    return '$days يوم';
  }

  @override
  String get connected => 'متصل';

  @override
  String get no_connection => 'لا يوجد اتصال';

  @override
  String get expired => 'منتهي الصلاحية';

  @override
  String get active_connection => 'اتصال نشط';

  @override
  String get maximum_connection => 'الحد الأقصى للاتصال';

  @override
  String get server_information => 'معلومات الخادم';

  @override
  String get timezone => 'المنطقة الزمنية';

  @override
  String get server_message => 'رسالة الخادم';

  @override
  String get all_datas_are_stored_in_device =>
      'يتم تخزين جميع البيانات بأمان على جهازك';

  @override
  String get url_format_validate_message =>
      'يجب أن يكون تنسيق الرابط مثل http://server:port';

  @override
  String get url_format_validate_error =>
      'يرجى إدخال رابط صحيح (يجب أن يبدأ بـ http:// أو https://)';

  @override
  String get playlist_name_already_exists =>
      'توجد قائمة تشغيل بهذا الاسم بالفعل';

  @override
  String get invalid_credentials =>
      'تعذر الحصول على استجابة من مزود IPTV، يرجى التحقق من معلوماتك';

  @override
  String get error_occurred => 'حدث خطأ';

  @override
  String get connecting => 'جارٍ الاتصال';

  @override
  String get preparing_categories => 'جارٍ تحضير الفئات';

  @override
  String preparing_categories_exception(Object error) {
    return 'تعذر تحميل الفئات: $error';
  }

  @override
  String get preparing_live_streams => 'جارٍ تحميل القنوات المباشرة';

  @override
  String get preparing_live_streams_exception_1 =>
      'تعذر الحصول على القنوات المباشرة';

  @override
  String preparing_live_streams_exception_2(Object error) {
    return 'خطأ في تحميل القنوات المباشرة: $error';
  }

  @override
  String get preparing_movies => 'جارٍ فتح مكتبة الأفلام';

  @override
  String get preparing_movies_exception_1 => 'تعذر الحصول على الأفلام';

  @override
  String preparing_movies_exception_2(Object error) {
    return 'خطأ في تحميل الأفلام: $error';
  }

  @override
  String get preparing_series => 'جارٍ تحضير مكتبة المسلسلات';

  @override
  String get preparing_series_exception_1 => 'تعذر الحصول على المسلسلات';

  @override
  String preparing_series_exception_2(Object error) {
    return 'خطأ في تحميل المسلسلات: $error';
  }

  @override
  String get preparing_user_info_exception_1 =>
      'تعذر الحصول على معلومات المستخدم';

  @override
  String preparing_user_info_exception_2(Object error) {
    return 'خطأ في تحميل معلومات المستخدم: $error';
  }

  @override
  String get m3u_playlist_title => 'إضافة قائمة تشغيل بملف M3U أو رابط';

  @override
  String get m3u_playlist_description => 'يدعم ملفات تنسيق M3U التقليدية';

  @override
  String get m3u_playlist => 'قائمة تشغيل M3U';

  @override
  String get m3u_playlist_load_description =>
      'تحميل قنوات IPTV بملف قائمة تشغيل M3U أو رابط';

  @override
  String get playlist_name_hint => 'أدخل اسم قائمة التشغيل';

  @override
  String get playlist_name_min_length =>
      'يجب أن يكون اسم قائمة التشغيل على الأقل حرفين';

  @override
  String get source_type => 'نوع المصدر';

  @override
  String get url => 'رابط';

  @override
  String get file => 'ملف';

  @override
  String get m3u_url => 'رابط M3U';

  @override
  String get m3u_url_hint => 'http://example.com/playlist.m3u';

  @override
  String get m3u_url_required => 'رابط M3U مطلوب';

  @override
  String get url_format_error => 'أدخل تنسيق رابط صحيح';

  @override
  String get url_scheme_error => 'يجب أن يبدأ الرابط بـ http:// أو https://';

  @override
  String get m3u_file => 'ملف M3U';

  @override
  String get file_selected => 'تم اختيار الملف';

  @override
  String get select_m3u_file => 'اختر ملف M3U (.m3u, .m3u8)';

  @override
  String get please_select_m3u_file => 'يرجى اختيار ملف M3U';

  @override
  String get file_selection_error => 'حدث خطأ أثناء اختيار الملف';

  @override
  String get processing => 'جاري المعالجة...';

  @override
  String get create_playlist => 'إنشاء قائمة التشغيل';

  @override
  String get error_occurred_title => 'حدث خطأ';

  @override
  String get m3u_info_message =>
      'جميع البيانات محفوظة بأمان على جهازك.\nالتنسيقات المدعومة: .m3u, .m3u8\nتنسيق الرابط: يجب أن يبدأ بـ http:// أو https://';

  @override
  String get m3u_parse_error => 'خطأ في تحليل M3U';

  @override
  String get loading_m3u => 'تحميل M3U';

  @override
  String get preparing_m3u_exception_no_source => 'لم يتم العثور على مصدر M3U';

  @override
  String get preparing_m3u_exception_empty => 'ملف M3U فارغ';

  @override
  String preparing_m3u_exception_parse(Object error) {
    return 'خطأ في تحليل M3U: $error';
  }

  @override
  String get not_categorized => 'غير مصنف';

  @override
  String get loading_lists => 'تحميل القوائم...';

  @override
  String get all => 'الكل';

  @override
  String iptv_channels_count(Object count) {
    return 'قنوات IPTV ($count)';
  }

  @override
  String get unknown_channel => 'قناة غير معروفة';

  @override
  String get live_content => 'مباشر';

  @override
  String get movie_content => 'فيلم';

  @override
  String get series_content => 'مسلسل';

  @override
  String get media_content => 'وسائط';

  @override
  String get m3u_error => 'خطأ M3U';

  @override
  String get episode_short => 'حلقة';

  @override
  String season_number(Object number) {
    return 'الموسم $number';
  }

  @override
  String get image_loading => 'تحميل الصورة...';

  @override
  String get image_not_found => 'الصورة غير موجودة';
}
