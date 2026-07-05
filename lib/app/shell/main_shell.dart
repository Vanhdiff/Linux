import 'dart:async';
import 'dart:ui' as ui;

import 'package:fluent_ui/fluent_ui.dart';
import '../i18n/app_language.dart';
import '../i18n/app_localization.dart';
import '../i18n/app_strings.dart';
import '../router/route_names.dart';
import '../services/license/online_license_config.dart';
import '../services/license/online_license_service.dart';
import '../services/mt5/mt5_bootstrap_service.dart';
import '../state/active_account_session.dart';
import '../theme/app_colors.dart';
import '../theme/app_theme_palette.dart';
import '../../features/dashboard/presentation/pages/dashboard_page.dart';
import '../../features/journal/presentation/pages/journal_page.dart';
import '../../features/plan/presentation/pages/plan_page.dart';
import '../../features/notebook/presentation/pages/notebook_page.dart';
import '../../features/news/presentation/pages/news_page.dart';
import '../../features/guardrails/presentation/pages/guardrails_page.dart';
import '../../features/settings/presentation/pages/settings_page.dart';
import '../../features/ai_coach/presentation/pages/ai_coach_page.dart';
import 'widgets/shell_sidebar.dart';

class MainShell extends StatefulWidget {
  const MainShell({super.key});

  @override
  State<MainShell> createState() => _MainShellState();
}

class _MainShellState extends State<MainShell> with WidgetsBindingObserver {
  static const Duration _licenseMonitorInterval = Duration(minutes: 1);
  String currentRoute = RouteNames.dashboard;
  bool sidebarCollapsed = false;
  AppThemePalette _selectedTheme = AppThemePalettes.light;
  AppLanguage _selectedLanguage = AppLanguage.english;
  final Mt5BootstrapService _mt5BootstrapService = Mt5BootstrapService();
  final OnlineLicenseService _onlineLicenseService = OnlineLicenseService();
  bool _isBootstrapping = true;
  final bool _backendReady = false;
  final bool _mt5Ready = false;
  String? _connectionMessage;
  bool _isShuttingDown = false;
  Timer? _licenseMonitorTimer;
  bool _licenseMonitorBusy = false;
  bool _hadActiveOnlineLicense = false;
  String? _lastLicenseKickMessage;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _isBootstrapping = false;
    _connectionMessage = 'Sync MT5 from Settings';
    if (OnlineLicenseConfig.enabled) {
      unawaited(_refreshOnlineLicenseState(isInitialCheck: true));
      _licenseMonitorTimer = Timer.periodic(
        _licenseMonitorInterval,
        (_) => unawaited(_refreshOnlineLicenseState()),
      );
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _licenseMonitorTimer?.cancel();
    _mt5BootstrapService.close();
    _onlineLicenseService.close();
    super.dispose();
  }

  @override
  Future<ui.AppExitResponse> didRequestAppExit() async {
    if (_isShuttingDown) {
      return ui.AppExitResponse.exit;
    }
    _isShuttingDown = true;
    try {
      await _mt5BootstrapService.shutdownBackend();
    } catch (_) {
      // Allow app exit even if backend shutdown fails.
    }
    return ui.AppExitResponse.exit;
  }

  void navigateTo(String route) {
    setState(() {
      currentRoute = route;
    });
  }

  void _toggleSidebarCollapsed() {
    setState(() => sidebarCollapsed = !sidebarCollapsed);
  }

  Future<void> _refreshOnlineLicenseState({
    bool isInitialCheck = false,
  }) async {
    if (!mounted || _licenseMonitorBusy || !OnlineLicenseConfig.enabled) {
      return;
    }
    _licenseMonitorBusy = true;
    try {
      final status = await _onlineLicenseService.bootstrap();
      if (!mounted) return;
      final wasLicensed = _hadActiveOnlineLicense;
      _hadActiveOnlineLicense = status.isLicensed;
      if (status.isLicensed) {
        _lastLicenseKickMessage = null;
        return;
      }
      if (!wasLicensed || isInitialCheck) {
        return;
      }
      final message = status.message;
      if (_lastLicenseKickMessage == message) {
        return;
      }
      _lastLicenseKickMessage = message;
      setState(() {
        currentRoute = RouteNames.settings;
        _connectionMessage = message;
      });
      await _showLicenseRevokedDialog(message);
    } catch (_) {
      // Network errors are handled inside bootstrap; no extra UI action needed here.
    } finally {
      _licenseMonitorBusy = false;
    }
  }

  Future<void> _showLicenseRevokedDialog(String message) async {
    if (!mounted) return;
    final strings = AppStrings(_selectedLanguage);
    await showDialog<void>(
      context: context,
      builder: (context) {
        return ContentDialog(
          title: Text(strings.isVietnamese ? 'License da bi khoa' : 'License revoked'),
          content: Text(
            strings.isVietnamese
                ? 'Phien su dung nay da bi dang xuat. $message'
                : 'This session has been signed out. $message',
          ),
          actions: [
            Button(
              child: Text(strings.isVietnamese ? 'Dong' : 'Close'),
              onPressed: () => Navigator.of(context).pop(),
            ),
          ],
        );
      },
    );
  }

  Widget get currentPage {
    final accountKey = ValueKey('account-${ActiveAccountSession.accountId}');
    final strings = AppStrings(_selectedLanguage);
    switch (currentRoute) {
      case RouteNames.dashboard:
        return DashboardPage(key: accountKey);
      case RouteNames.journal:
        return JournalPage(key: accountKey);
      case RouteNames.plan:
        return PlanPage(key: accountKey);
      case RouteNames.notebook:
        return NotebookPage(key: accountKey);
      case RouteNames.news:
        return NewsPage();
      case RouteNames.guardrails:
        return GuardrailsPage(key: accountKey);
      case RouteNames.aiCoach:
        return AiCoachPage(key: accountKey);
      case RouteNames.settings:
        return SettingsPage(
          strings: strings,
          selectedTheme: _selectedTheme,
          selectedLanguage: _selectedLanguage,
          onThemeSelected: (theme) {
            setState(() => _selectedTheme = theme);
            AppColors.use(theme);
          },
          onLanguageSelected: (language) {
            setState(() => _selectedLanguage = language);
          },
        );
      default:
        return DashboardPage();
    }
  }

  @override
  Widget build(BuildContext context) {
    final strings = AppStrings(_selectedLanguage);
    return AppLocalization(
      strings: strings,
      child: NavigationView(
        content: DefaultTextStyle(
          style: TextStyle(color: _selectedTheme.textPrimary),
          child: IconTheme(
            data: IconThemeData(color: _selectedTheme.textSecondary),
            child: Stack(
              children: [
                Container(
                  color: _selectedTheme.bg,
                  child: Row(
                    children: [
                      ShellSidebar(
                        currentRoute: currentRoute,
                        isCollapsed: sidebarCollapsed,
                        theme: _selectedTheme,
                        strings: strings,
                        isBootstrapping: _isBootstrapping,
                        backendReady: _backendReady,
                        mt5Ready: _mt5Ready,
                        connectionMessage: _connectionMessage,
                        onNavigate: navigateTo,
                        onToggleCollapsed: _toggleSidebarCollapsed,
                      ),
                      Expanded(
                        child: Container(
                          margin: EdgeInsets.fromLTRB(0, 10, 10, 10),
                          decoration: BoxDecoration(
                            color: _selectedTheme.shellBg,
                            borderRadius: BorderRadius.circular(22),
                          ),
                          child: Column(
                            children: [Expanded(child: currentPage)],
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
