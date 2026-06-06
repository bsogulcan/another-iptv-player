import 'package:another_iptv_player/repositories/user_preferences.dart';
import 'package:flutter/material.dart';
import 'package:another_iptv_player/l10n/localization_extension.dart';
import '../../widgets/color_picker_tile_widget.dart';
import '../../widgets/dropdown_tile_widget.dart';
import '../../widgets/slider_tile_widget.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../controllers/xtream_code_home_controller.dart';

class CategorySettingsScreen extends StatefulWidget {
  final XtreamCodeHomeController controller;

  const CategorySettingsScreen({super.key, required this.controller});

  @override
  State<CategorySettingsScreen> createState() => _CategorySettingsScreenState();
}

class _CategorySettingsScreenState extends State<CategorySettingsScreen> {
  Set<String> _hiddenCategories = {};
  bool _hasChanges = false;

  @override
  void initState() {
    super.initState();
    _loadHiddenCategories();
  }

  Future<void> _loadHiddenCategories() async {
    final hidden = await UserPreferences.getHiddenCategories();
    setState(() {
      _hiddenCategories = hidden.toSet();
    });
  }

  Future<void> _toggleHidden(bool isVisible, String categoryId) async {
    setState(() {
      _hasChanges = true;
      if (isVisible) {
        _hiddenCategories.remove(categoryId);
      } else {
        _hiddenCategories.add(categoryId);
      }
    });
    await UserPreferences.setHiddenCategories(_hiddenCategories.toList());
    widget.controller.notifyListeners();
  }

  Future<void> _setAllCategoriesVisible(Iterable<String> ids, bool visible) async {
    setState(() {
      _hasChanges = true;
      if (visible) {
        _hiddenCategories.removeAll(ids);
      } else {
        _hiddenCategories.addAll(ids);
      }
    });
    await UserPreferences.setHiddenCategories(_hiddenCategories.toList());
    widget.controller.notifyListeners();
  }

  void _closeScreen(BuildContext context) {
    if (_hasChanges) {
      widget.controller.notifyListeners();
    }
    Navigator.pop(context, _hasChanges);
  }

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider.value(
      value: widget.controller,
      child: WillPopScope(
        onWillPop: () async {
          Navigator.pop(context, _hasChanges);
          return false;
        },
        child: Scaffold(
          appBar: AppBar(
            title: Text(context.loc.hide_category),
            leading: IconButton(
              icon: const Icon(Icons.arrow_back),
              onPressed: () {
                Navigator.pop(context, _hasChanges);
              },
            ),
          ),
          body: Consumer<XtreamCodeHomeController>(
            builder: (context, controller, _) {
              return ListView(
                children: [
                  ListTile(
                    title: Text(context.loc.live),
                    tileColor: Colors.black12,
                  ),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [
                      TextButton(
                        onPressed: () => _setAllCategoriesVisible(
                          widget.controller.liveCategories!.map((c) => c.category.categoryId),
                          true,
                        ),
                        child: Text(context.loc.select_all),
                      ),
                      TextButton(
                        onPressed: () => _setAllCategoriesVisible(
                          widget.controller.liveCategories!.map((c) => c.category.categoryId),
                          false,
                        ),
                        child: Text(context.loc.deselect_all),
                      ),
                    ],
                  ),
                  ...?controller.liveCategories?.map((cat) {
                    final isHidden = _hiddenCategories.contains(cat.category.categoryId);
                    return SwitchListTile(
                      title: Text(cat.category.categoryName),
                      value: !isHidden,
                      onChanged: (val) => _toggleHidden(val, cat.category.categoryId),
                    );
                  }),

                  const Divider(),
                  ListTile(
                    title: Text(context.loc.movies),
                    tileColor: Colors.black12,
                  ),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [
                      TextButton(
                        onPressed: () => _setAllCategoriesVisible(
                          widget.controller.movieCategories.map((c) => c.category.categoryId),
                          true,
                        ),
                        child: Text(context.loc.select_all),
                      ),
                      TextButton(
                        onPressed: () => _setAllCategoriesVisible(
                          widget.controller.movieCategories.map((c) => c.category.categoryId),
                          false,
                        ),
                        child: Text(context.loc.deselect_all),
                      ),
                    ],
                  ),
                  ...controller.movieCategories.map((cat) {
                    final isHidden = _hiddenCategories.contains(cat.category.categoryId);
                    return SwitchListTile(
                      title: Text(cat.category.categoryName),
                      value: !isHidden,
                      onChanged: (val) => _toggleHidden(val, cat.category.categoryId),
                    );
                  }),

                  const Divider(),
                  ListTile(
                    title: Text(context.loc.series_plural),
                    tileColor: Colors.black12,
                  ),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [
                      TextButton(
                        onPressed: () => _setAllCategoriesVisible(
                          widget.controller.seriesCategories.map((c) => c.category.categoryId),
                          true,
                        ),
                        child: Text(context.loc.select_all),
                      ),
                      TextButton(
                        onPressed: () => _setAllCategoriesVisible(
                          widget.controller.seriesCategories.map((c) => c.category.categoryId),
                          false,
                        ),
                        child: Text(context.loc.deselect_all),
                      ),
                    ],
                  ),
                  ...controller.seriesCategories.map((cat) {
                    final isHidden = _hiddenCategories.contains(cat.category.categoryId);
                    return SwitchListTile(
                      title: Text(cat.category.categoryName),
                      value: !isHidden,
                      onChanged: (val) => _toggleHidden(val, cat.category.categoryId),
                    );
                  }),
                ],
              );
            },
          ),
        ),
      ),
    );
  }
}
