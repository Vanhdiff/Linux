import 'package:fluent_ui/fluent_ui.dart';
import 'router/app_router.dart';
import 'theme/app_theme.dart';

class TradingDeskApp extends StatelessWidget {
  const TradingDeskApp({super.key});

  @override
  Widget build(BuildContext context) {
    return FluentApp(
      debugShowCheckedModeBanner: false,
      title: 'Trading Desk',
      themeMode: ThemeMode.light,
      theme: buildAppTheme(),
      home: const AppRouter(),
    );
  }
}
