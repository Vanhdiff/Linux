import 'package:fluent_ui/fluent_ui.dart';

import '../../../../app/i18n/app_language.dart';
import '../../../../app/i18n/app_strings.dart';
import '../../../../app/services/api/api_client.dart';
import '../../../../app/services/backend/backend_process_service.dart';
import '../../../../app/services/license/online_license_config.dart';
import '../../../../app/services/license/online_license_service.dart';
import '../../../../app/services/mt5/mt5_bootstrap_service.dart';
import '../../../../app/state/active_account_session.dart';
import '../../../../app/theme/app_theme_palette.dart';
import '../services/data_management_service.dart';

class SettingsPage extends StatefulWidget {
  final AppStrings strings;
  final AppThemePalette selectedTheme;
  final AppLanguage selectedLanguage;
  final ValueChanged<AppThemePalette> onThemeSelected;
  final ValueChanged<AppLanguage> onLanguageSelected;

  const SettingsPage({
    super.key,
    required this.strings,
    required this.selectedTheme,
    required this.selectedLanguage,
    required this.onThemeSelected,
    required this.onLanguageSelected,
  });

  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> {
  bool _tradeBlockAlerts = true;
  bool _newsAlerts = true;
  bool _syncAlerts = false;
  bool _connectingMt5 = false;
  String? _accountMessage;
  bool _isLicenseLoading = false;
  bool _isLicenseActive = false;
  bool _isActivatingLicense = false;
  String _licenseMessage = '';
  bool _isBackingUp = false;
  bool _isRestoring = false;
  String _dataMessage = '';
  final TextEditingController _licenseKeyController = TextEditingController();
  final TextEditingController _licenseEmailController = TextEditingController();
  final TextEditingController _licensePasswordController =
      TextEditingController();
  final Mt5BootstrapService _mt5BootstrapService = Mt5BootstrapService();
  final ApiClient _apiClient = ApiClient();
  final BackendProcessService _backendProcessService = BackendProcessService();
  final OnlineLicenseService _onlineLicenseService = OnlineLicenseService();
  final DataManagementService _dataManagementService = DataManagementService();

  AppThemePalette get theme => widget.selectedTheme;
  AppStrings get strings => widget.strings;

  @override
  void initState() {
    super.initState();
    _loadLicense();
  }

  Future<void> _loadLicense() async {
    setState(() {
      _isLicenseLoading = true;
      _licenseMessage = '';
    });
    try {
      if (OnlineLicenseConfig.enabled) {
        final status = await _onlineLicenseService.bootstrap();
        if (!mounted) return;
        setState(() {
          _isLicenseActive = status.isLicensed;
          _licenseKeyController.text =
              status.session?.licenseKey ?? _licenseKeyController.text;
          _licenseEmailController.text =
              status.session?.ownerEmail ??
              status.session?.email ??
              _licenseEmailController.text;
          _licenseMessage = status.message;
        });
        return;
      }

      await _backendProcessService.ensureRunning();
      final response = await _apiClient.getJson('/api/license');
      if (!mounted) return;
      setState(() {
        _licenseKeyController.text = response['license_key'] as String? ?? '';
        _licenseEmailController.text =
            response['owner_email'] as String? ?? _licenseEmailController.text;
        _isLicenseActive = response['is_active'] as bool? ?? false;
        _licenseMessage = response['message'] as String? ?? '';
      });
    } catch (error) {
      if (mounted) {
        setState(() {
          _licenseMessage = error.toString();
        });
      }
    } finally {
      if (mounted) {
        setState(() {
          _isLicenseLoading = false;
        });
      }
    }
  }

  Future<void> _activateLicense() async {
    final key = _licenseKeyController.text.trim();
    if (key.isEmpty) {
      setState(() {
        _licenseMessage = strings.licenseKeyRequired;
      });
      return;
    }

    setState(() {
      _isActivatingLicense = true;
      _licenseMessage = '';
    });

    try {
      if (OnlineLicenseConfig.enabled) {
        final email = _licenseEmailController.text.trim();
        final password = _licensePasswordController.text;
        if (email.isEmpty || password.isEmpty) {
          setState(() {
            _licenseMessage = strings.isVietnamese
                ? 'Vui long nhap email va mat khau.'
                : 'Please enter email and password.';
          });
          return;
        }

        final result = await _onlineLicenseService.signInAndActivate(
          email: email,
          password: password,
          licenseKey: key,
        );
        if (!mounted) return;
        setState(() {
          _isLicenseActive = result.isLicensed;
          _licenseMessage = result.message;
          _licensePasswordController.clear();
        });
        return;
      }

      await _backendProcessService.ensureRunning();
      final response = await _apiClient.postJson('/api/license', {
        'license_key': key,
      });
      if (!mounted) return;
      setState(() {
        _isLicenseActive = response['is_active'] as bool? ?? false;
        _licenseMessage = response['message'] as String? ?? '';
      });
    } catch (error) {
      if (mounted) {
        setState(() {
          _licenseMessage = error.toString();
        });
      }
    } finally {
      if (mounted) {
        setState(() {
          _isActivatingLicense = false;
        });
      }
    }
  }

  @override
  void dispose() {
    _licenseKeyController.dispose();
    _licenseEmailController.dispose();
    _licensePasswordController.dispose();
    _apiClient.close();
    _backendProcessService.close();
    _mt5BootstrapService.close();
    _onlineLicenseService.close();
    _dataManagementService.close();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(24, 28, 24, 30),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 1180),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                strings.settingsTitle,
                style: TextStyle(
                  color: theme.textPrimary,
                  fontSize: 20,
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(height: 10),
              Text(
                strings.settingsSubtitle,
                style: TextStyle(
                  color: theme.textSecondary,
                  fontSize: 13,
                  fontWeight: FontWeight.w500,
                ),
              ),
              const SizedBox(height: 34),
              _AccountCard(
                theme: theme,
                strings: strings,
                connecting: _connectingMt5,
                canSyncMt5: !OnlineLicenseConfig.enabled || _isLicenseActive,
                message: _accountMessage,
                onSignIn: _connectMt5,
              ),
              const SizedBox(height: 26),
              _LicenseCard(
                theme: theme,
                strings: strings,
                controller: _licenseKeyController,
                emailController: _licenseEmailController,
                passwordController: _licensePasswordController,
                onlineMode: OnlineLicenseConfig.enabled,
                isLoading: _isLicenseLoading,
                isActive: _isLicenseActive,
                isActivating: _isActivatingLicense,
                message: _licenseMessage,
                onActivate: _activateLicense,
              ),
              const SizedBox(height: 26),
              _DataManagementCard(
                theme: theme,
                storageSummary: _dataManagementService.storageSummary,
                isBackingUp: _isBackingUp,
                isRestoring: _isRestoring,
                message: _dataMessage,
                onBackup: _createBackup,
                onRestore: _restoreBackup,
                onOpenBackupFolder: _openBackupFolder,
              ),
              const SizedBox(height: 26),
              _NotificationCard(
                theme: theme,
                strings: strings,
                tradeBlockAlerts: _tradeBlockAlerts,
                newsAlerts: _newsAlerts,
                syncAlerts: _syncAlerts,
                onTradeBlockChanged: (value) =>
                    setState(() => _tradeBlockAlerts = value),
                onNewsChanged: (value) => setState(() => _newsAlerts = value),
                onSyncChanged: (value) => setState(() => _syncAlerts = value),
              ),
              const SizedBox(height: 26),
              _LanguageCard(
                theme: theme,
                strings: strings,
                selectedLanguage: widget.selectedLanguage,
                onLanguageSelected: widget.onLanguageSelected,
              ),
              const SizedBox(height: 26),
              _AppearanceCard(
                theme: theme,
                strings: strings,
                selectedTheme: widget.selectedTheme,
                onThemeSelected: widget.onThemeSelected,
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _connectMt5() async {
    setState(() {
      _connectingMt5 = true;
      _accountMessage = strings.connectingMt5Message;
    });
    try {
      if (OnlineLicenseConfig.enabled) {
        final license = await _onlineLicenseService.bootstrap();
        if (!license.isLicensed) {
          if (!mounted) return;
          setState(() {
            _isLicenseActive = false;
            _licenseMessage = license.message;
            _connectingMt5 = false;
            _accountMessage = strings.isVietnamese
                ? 'Hay kich hoat license online truoc khi sync MT5.'
                : 'Activate your online license before syncing MT5.';
          });
          return;
        }

        if (mounted) {
          setState(() {
            _isLicenseActive = true;
            _licenseMessage = license.message;
          });
        }
      }

      final result = await _mt5BootstrapService.bootstrap();
      if (!mounted) return;
      setState(() {
        _connectingMt5 = false;
        _accountMessage = strings.connectedMt5Message(
          '${result['account_login']}',
        );
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _connectingMt5 = false;
        _accountMessage = strings.couldNotConnect(error);
      });
    }
  }

  Future<void> _createBackup() async {
    setState(() {
      _isBackingUp = true;
      _dataMessage = '';
    });
    try {
      final backupPath = await _dataManagementService.createBackup();
      if (!mounted) return;
      setState(() {
        _dataMessage = 'Backup created at:\n$backupPath';
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _dataMessage = 'Backup failed: $error';
      });
    } finally {
      if (mounted) {
        setState(() {
          _isBackingUp = false;
        });
      }
    }
  }

  Future<void> _restoreBackup() async {
    setState(() {
      _isRestoring = true;
      _dataMessage = '';
    });
    try {
      final backupPath = await _dataManagementService.restoreBackup();
      await _loadLicense();
      if (!mounted) return;
      setState(() {
        _dataMessage = 'Restore complete from:\n$backupPath';
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _dataMessage = 'Restore failed: $error';
      });
    } finally {
      if (mounted) {
        setState(() {
          _isRestoring = false;
        });
      }
    }
  }

  Future<void> _openBackupFolder() async {
    try {
      await _dataManagementService.openBackupFolder();
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _dataMessage = 'Could not open backup folder: $error';
      });
    }
  }
}

class _SettingsCard extends StatelessWidget {
  final AppThemePalette theme;
  final String title;
  final String subtitle;
  final Widget? trailing;
  final Widget child;

  const _SettingsCard({
    required this.theme,
    required this.title,
    required this.subtitle,
    this.trailing,
    required this.child,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(28, 26, 28, 28),
      decoration: BoxDecoration(
        color: theme.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: theme.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  title,
                  style: TextStyle(
                    color: theme.textPrimary,
                    fontSize: 16,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
              ?trailing,
            ],
          ),
          const SizedBox(height: 8),
          Text(
            subtitle,
            style: TextStyle(
              color: theme.textSecondary,
              fontSize: 14,
              fontWeight: FontWeight.w400,
            ),
          ),
          const SizedBox(height: 26),
          child,
        ],
      ),
    );
  }
}

class _AccountCard extends StatelessWidget {
  final AppThemePalette theme;
  final AppStrings strings;
  final bool connecting;
  final bool canSyncMt5;
  final String? message;
  final VoidCallback onSignIn;

  const _AccountCard({
    required this.theme,
    required this.strings,
    required this.connecting,
    required this.canSyncMt5,
    required this.message,
    required this.onSignIn,
  });

  @override
  Widget build(BuildContext context) {
    return _SettingsCard(
      theme: theme,
      title: strings.accountTitle,
      subtitle: strings.accountSubtitle,
      child: Column(
        children: [
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 16),
            decoration: BoxDecoration(
              color: theme.surfaceAlt,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: theme.border),
            ),
            child: Row(
              children: [
                Container(
                  width: 52,
                  height: 52,
                  decoration: BoxDecoration(
                    color: theme.primary,
                    borderRadius: BorderRadius.circular(14),
                  ),
                  alignment: Alignment.center,
                  child: const Icon(
                    FluentIcons.cube_shape,
                    size: 24,
                    color: Colors.white,
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        ActiveAccountSession.activeAccountLogin == null
                            ? strings.tradingDesk
                            : 'MT5 ${ActiveAccountSession.activeAccountLogin}',
                        style: TextStyle(
                          color: theme.textPrimary,
                          fontSize: 17,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        !canSyncMt5
                            ? (strings.isVietnamese
                                  ? 'Kich hoat license truoc khi sync MT5'
                                  : 'Activate license before syncing MT5')
                            : (ActiveAccountSession.activeAccountLogin == null
                                  ? strings.connectMt5
                                  : strings.readyToSync),
                        style: TextStyle(
                          color: theme.textSecondary,
                          fontSize: 12,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ],
                  ),
                ),
                GestureDetector(
                  onTap: connecting || !canSyncMt5 ? null : onSignIn,
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 160),
                    height: 48,
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    decoration: BoxDecoration(
                      color: connecting || !canSyncMt5
                          ? theme.hover
                          : theme.primary.withValues(alpha: 0.10),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                        color: connecting || !canSyncMt5
                            ? theme.border
                            : theme.primary.withValues(alpha: 0.22),
                      ),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          connecting
                              ? FluentIcons.sync
                              : (ActiveAccountSession.activeAccountLogin == null
                                    ? FluentIcons.signin
                                    : FluentIcons.sync),
                          size: 15,
                          color: canSyncMt5
                              ? theme.primary
                              : theme.textSecondary.withValues(alpha: 0.55),
                        ),
                        const SizedBox(width: 8),
                        Text(
                          !canSyncMt5
                              ? strings.activateLicense
                              : connecting
                              ? strings.connecting
                              : (ActiveAccountSession.activeAccountLogin == null
                                    ? strings.signIn
                                    : strings.syncMt5),
                          style: TextStyle(
                            color: canSyncMt5
                                ? theme.primary
                                : theme.textSecondary.withValues(alpha: 0.65),
                            fontSize: 14,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
          if (message != null) ...[
            const SizedBox(height: 12),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              decoration: BoxDecoration(
                color: theme.hover,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: theme.border),
              ),
              child: Text(
                message!,
                style: TextStyle(
                  color: theme.textSecondary,
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _LicenseCard extends StatelessWidget {
  final AppThemePalette theme;
  final AppStrings strings;
  final TextEditingController controller;
  final TextEditingController emailController;
  final TextEditingController passwordController;
  final bool onlineMode;
  final bool isLoading;
  final bool isActive;
  final bool isActivating;
  final String message;
  final VoidCallback onActivate;

  const _LicenseCard({
    required this.theme,
    required this.strings,
    required this.controller,
    required this.emailController,
    required this.passwordController,
    required this.onlineMode,
    required this.isLoading,
    required this.isActive,
    required this.isActivating,
    required this.message,
    required this.onActivate,
  });

  @override
  Widget build(BuildContext context) {
    return _SettingsCard(
      theme: theme,
      title: strings.licenseTitle,
      subtitle: onlineMode
          ? (strings.isVietnamese
                ? 'Dang nhap tai khoan va kich hoat license online.'
                : 'Sign in and activate your online license.')
          : strings.licenseSubtitle,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (onlineMode) ...[
            TextBox(
              controller: emailController,
              placeholder: 'Email',
              enabled: !isLoading && !isActivating,
            ),
            const SizedBox(height: 12),
            TextBox(
              controller: passwordController,
              placeholder: strings.isVietnamese ? 'Mat khau' : 'Password',
              enabled: !isLoading && !isActivating,
              obscureText: true,
            ),
            const SizedBox(height: 12),
          ],
          TextBox(
            controller: controller,
            placeholder: strings.licenseHint,
            enabled: !isLoading && !isActivating,
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(
                child: Text(
                  isActive
                      ? strings.licenseStatusActive
                      : strings.licenseStatusInactive,
                  style: TextStyle(
                    color: theme.textSecondary,
                    fontSize: 13,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),
              FilledButton(
                onPressed: isLoading || isActivating ? null : onActivate,
                child: Text(
                  isActivating
                      ? (strings.isVietnamese
                            ? 'Dang kich hoat...'
                            : 'Activating...')
                      : strings.activateLicense,
                ),
              ),
            ],
          ),
          if (message.isNotEmpty) ...[
            const SizedBox(height: 12),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              decoration: BoxDecoration(
                color: theme.hover,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: theme.border),
              ),
              child: Text(
                message,
                style: TextStyle(
                  color: theme.textSecondary,
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _DataManagementCard extends StatelessWidget {
  final AppThemePalette theme;
  final String storageSummary;
  final bool isBackingUp;
  final bool isRestoring;
  final String message;
  final Future<void> Function() onBackup;
  final Future<void> Function() onRestore;
  final Future<void> Function() onOpenBackupFolder;

  const _DataManagementCard({
    required this.theme,
    required this.storageSummary,
    required this.isBackingUp,
    required this.isRestoring,
    required this.message,
    required this.onBackup,
    required this.onRestore,
    required this.onOpenBackupFolder,
  });

  @override
  Widget build(BuildContext context) {
    final busy = isBackingUp || isRestoring;

    return _SettingsCard(
      theme: theme,
      title: 'Data Management',
      subtitle:
          'Back up and restore your local trading data and journal charts.',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: theme.surfaceAlt,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: theme.border),
            ),
            child: Text(
              storageSummary,
              style: TextStyle(
                color: theme.textSecondary,
                fontSize: 12,
                fontWeight: FontWeight.w600,
                height: 1.45,
              ),
            ),
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              FilledButton(
                onPressed: busy ? null : onBackup,
                child: Text(isBackingUp ? 'Creating Backup...' : 'Backup Now'),
              ),
              const SizedBox(width: 10),
              Button(
                onPressed: busy ? null : onRestore,
                child: Text(isRestoring ? 'Restoring...' : 'Restore Backup'),
              ),
              const SizedBox(width: 10),
              Button(
                onPressed: busy ? null : onOpenBackupFolder,
                child: const Text('Open Backup Folder'),
              ),
            ],
          ),
          if (message.isNotEmpty) ...[
            const SizedBox(height: 12),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              decoration: BoxDecoration(
                color: theme.hover,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: theme.border),
              ),
              child: Text(
                message,
                style: TextStyle(
                  color: theme.textSecondary,
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  height: 1.45,
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _AppearanceCard extends StatelessWidget {
  final AppThemePalette theme;
  final AppStrings strings;
  final AppThemePalette selectedTheme;
  final ValueChanged<AppThemePalette> onThemeSelected;

  const _AppearanceCard({
    required this.theme,
    required this.strings,
    required this.selectedTheme,
    required this.onThemeSelected,
  });

  @override
  Widget build(BuildContext context) {
    return _SettingsCard(
      theme: theme,
      title: strings.appearanceTitle,
      subtitle: strings.appearanceSubtitle,
      child: Column(
        children: AppThemePalettes.all
            .map(
              (preset) => Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: _ThemeOption(
                  shellTheme: theme,
                  strings: strings,
                  preset: preset,
                  selected: preset.name == selectedTheme.name,
                  onTap: () => onThemeSelected(preset),
                ),
              ),
            )
            .toList(),
      ),
    );
  }
}

class _LanguageCard extends StatelessWidget {
  final AppThemePalette theme;
  final AppStrings strings;
  final AppLanguage selectedLanguage;
  final ValueChanged<AppLanguage> onLanguageSelected;

  const _LanguageCard({
    required this.theme,
    required this.strings,
    required this.selectedLanguage,
    required this.onLanguageSelected,
  });

  @override
  Widget build(BuildContext context) {
    return _SettingsCard(
      theme: theme,
      title: strings.languageTitle,
      subtitle: strings.languageSubtitle,
      child: Row(
        children: [
          for (final language in AppLanguage.values) ...[
            Expanded(
              child: _LanguageOption(
                theme: theme,
                language: language,
                selected: language == selectedLanguage,
                onTap: () => onLanguageSelected(language),
              ),
            ),
            if (language != AppLanguage.values.last) const SizedBox(width: 12),
          ],
        ],
      ),
    );
  }
}

class _LanguageOption extends StatelessWidget {
  final AppThemePalette theme;
  final AppLanguage language;
  final bool selected;
  final VoidCallback onTap;

  const _LanguageOption({
    required this.theme,
    required this.language,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 160),
        height: 78,
        padding: const EdgeInsets.symmetric(horizontal: 18),
        decoration: BoxDecoration(
          color: selected
              ? theme.primary.withValues(alpha: 0.08)
              : theme.surface,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: selected ? theme.primary : theme.border,
            width: selected ? 1.5 : 1,
          ),
        ),
        child: Row(
          children: [
            Container(
              width: 42,
              height: 42,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: selected
                    ? theme.primary.withValues(alpha: 0.12)
                    : theme.surfaceAlt,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: theme.border),
              ),
              child: Text(
                language.code,
                style: TextStyle(
                  color: selected ? theme.primary : theme.textSecondary,
                  fontSize: 12,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    language.label,
                    style: TextStyle(
                      color: theme.textPrimary,
                      fontSize: 15,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const SizedBox(height: 5),
                  Text(
                    language.description,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: theme.textSecondary,
                      fontSize: 12,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ],
              ),
            ),
            if (selected)
              Container(
                width: 26,
                height: 26,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: theme.primary,
                  borderRadius: BorderRadius.circular(999),
                ),
                child: const Icon(
                  FluentIcons.check_mark,
                  size: 12,
                  color: Colors.white,
                ),
              )
            else
              Icon(
                FluentIcons.chevron_right,
                size: 14,
                color: theme.textSecondary.withValues(alpha: 0.45),
              ),
          ],
        ),
      ),
    );
  }
}

class _ThemeOption extends StatelessWidget {
  final AppThemePalette shellTheme;
  final AppStrings strings;
  final AppThemePalette preset;
  final bool selected;
  final VoidCallback onTap;

  const _ThemeOption({
    required this.shellTheme,
    required this.strings,
    required this.preset,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 160),
        height: 86,
        padding: const EdgeInsets.symmetric(horizontal: 20),
        decoration: BoxDecoration(
          color: selected
              ? preset.primary.withValues(alpha: 0.08)
              : shellTheme.surface,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: selected ? preset.primary : shellTheme.border,
            width: selected ? 1.5 : 1,
          ),
        ),
        child: Row(
          children: [
            _ThemeIcon(preset: preset),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    _themeLabel(preset, strings),
                    style: TextStyle(
                      color: shellTheme.textPrimary,
                      fontSize: 15,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const SizedBox(height: 5),
                  Text(
                    preset.description,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: shellTheme.textSecondary,
                      fontSize: 12,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ],
              ),
            ),
            if (selected)
              Container(
                width: 28,
                height: 28,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: preset.primary,
                  borderRadius: BorderRadius.circular(999),
                ),
                child: const Icon(
                  FluentIcons.check_mark,
                  size: 13,
                  color: Colors.white,
                ),
              )
            else
              Icon(
                FluentIcons.chevron_right,
                size: 14,
                color: shellTheme.textSecondary.withValues(alpha: 0.45),
              ),
          ],
        ),
      ),
    );
  }
}

class _ThemeIcon extends StatelessWidget {
  final AppThemePalette preset;

  const _ThemeIcon({required this.preset});

  @override
  Widget build(BuildContext context) {
    final dark = preset.mode == AppThemeMode.dark;
    return Container(
      width: 44,
      height: 44,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: dark ? const Color(0xFF0F172A) : Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: dark ? const Color(0xFF243149) : preset.border,
        ),
      ),
      child: Icon(
        dark ? FluentIcons.clear_night : FluentIcons.sunny,
        size: 17,
        color: dark ? const Color(0xFFBFD7FF) : preset.warning,
      ),
    );
  }
}

String _themeLabel(AppThemePalette preset, AppStrings strings) {
  return preset.mode == AppThemeMode.dark
      ? strings.darkTheme
      : strings.lightTheme;
}

class _NotificationCard extends StatelessWidget {
  final AppThemePalette theme;
  final AppStrings strings;
  final bool tradeBlockAlerts;
  final bool newsAlerts;
  final bool syncAlerts;
  final ValueChanged<bool> onTradeBlockChanged;
  final ValueChanged<bool> onNewsChanged;
  final ValueChanged<bool> onSyncChanged;

  const _NotificationCard({
    required this.theme,
    required this.strings,
    required this.tradeBlockAlerts,
    required this.newsAlerts,
    required this.syncAlerts,
    required this.onTradeBlockChanged,
    required this.onNewsChanged,
    required this.onSyncChanged,
  });

  @override
  Widget build(BuildContext context) {
    return _SettingsCard(
      theme: theme,
      title: strings.notificationsTitle,
      subtitle: strings.notificationsSubtitle,
      trailing: Text(
        strings.add,
        style: TextStyle(
          color: theme.textSecondary,
          fontSize: 12,
          fontWeight: FontWeight.w600,
        ),
      ),
      child: Column(
        children: [
          _ToggleRow(
            theme: theme,
            icon: FluentIcons.shield,
            title: strings.tradeBlockAlerts,
            subtitle: strings.tradeBlockAlertsSubtitle,
            value: tradeBlockAlerts,
            onChanged: onTradeBlockChanged,
          ),
          _ToggleRow(
            theme: theme,
            icon: FluentIcons.news,
            title: strings.redNewsAlerts,
            subtitle: strings.redNewsAlertsSubtitle,
            value: newsAlerts,
            onChanged: onNewsChanged,
          ),
          _ToggleRow(
            theme: theme,
            icon: FluentIcons.sync,
            title: strings.mt5SyncAlerts,
            subtitle: strings.mt5SyncAlertsSubtitle,
            value: syncAlerts,
            onChanged: onSyncChanged,
            bottomBorder: false,
          ),
        ],
      ),
    );
  }
}

class _ToggleRow extends StatelessWidget {
  final AppThemePalette theme;
  final IconData icon;
  final String title;
  final String subtitle;
  final bool value;
  final ValueChanged<bool> onChanged;
  final bool bottomBorder;

  const _ToggleRow({
    required this.theme,
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.value,
    required this.onChanged,
    this.bottomBorder = true,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 16),
      decoration: BoxDecoration(
        border: bottomBorder
            ? Border(bottom: BorderSide(color: theme.border))
            : null,
      ),
      child: Row(
        children: [
          Container(
            width: 44,
            height: 44,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: theme.hover,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(icon, size: 17, color: theme.primary),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: TextStyle(
                    color: theme.textPrimary,
                    fontSize: 15,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  subtitle,
                  style: TextStyle(
                    color: theme.textSecondary,
                    fontSize: 12,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ],
            ),
          ),
          ToggleSwitch(checked: value, onChanged: onChanged),
        ],
      ),
    );
  }
}
