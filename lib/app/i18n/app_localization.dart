import 'package:fluent_ui/fluent_ui.dart';

import 'app_strings.dart';

class AppLocalization extends InheritedWidget {
  final AppStrings strings;

  const AppLocalization({
    super.key,
    required this.strings,
    required super.child,
  });

  static AppStrings of(BuildContext context) {
    final scope = context.dependOnInheritedWidgetOfExactType<AppLocalization>();
    return scope?.strings ?? const AppStrings.fallback();
  }

  @override
  bool updateShouldNotify(AppLocalization oldWidget) {
    return oldWidget.strings.language != strings.language;
  }
}
