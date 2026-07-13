import 'package:fluent_ui/fluent_ui.dart';
import 'router/app_router.dart';
import 'theme/app_theme.dart';

class TradingDeskApp extends StatelessWidget {
  final Widget? home;

  const TradingDeskApp({super.key}) : home = null;
  const TradingDeskApp.withHome({super.key, required this.home});

  @override
  Widget build(BuildContext context) {
    return FluentApp(
      debugShowCheckedModeBanner: false,
      title: 'Trading Desk',
      themeMode: ThemeMode.light,
      theme: buildAppTheme(),
      home: home ?? const AppRouter(),
    );
  }
}
