import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:radio_tower/manger/ConfigKeys.dart';
import 'package:radio_tower/manger/ConfigMgr.dart';
import 'package:radio_tower/l10n/app_localizations.dart';
import 'package:radio_tower/player/WindowsMediaKeyService.dart';
import 'package:radio_tower/provider/AppLocaleProvider.dart';
import 'package:radio_tower/provider/StationModel.dart';
import 'package:radio_tower/services/WindowsDesktopService.dart';

class SettingsPage extends StatefulWidget {
  const SettingsPage({super.key});

  @override
  State<SettingsPage> createState() {
    return _SettingsPageState();
  }
}

class _SettingsPageState extends State<SettingsPage> {
  bool _globalMediaKeysEnabled = false;

  @override
  void initState() {
    super.initState();
    _globalMediaKeysEnabled = ConfigMgr().getBoolVal(
      ConfigKeys.KEY_GLOBAL_MEDIA_KEYS_ENABLED,
      false,
    );
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final l10n = AppLocalizations.of(context)!;

    return Scaffold(
      appBar: AppBar(title: Text(l10n.settings)),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          Text(
            l10n.keyboardSettings,
            style: Theme.of(
              context,
            ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 8),
          Card(
            margin: EdgeInsets.zero,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(8),
              side: BorderSide(
                color: colorScheme.outlineVariant.withValues(alpha: 0.45),
              ),
            ),
            child: SwitchListTile(
              value: _globalMediaKeysEnabled,
              onChanged: _setGlobalMediaKeysEnabled,
              secondary: const Icon(Icons.keyboard),
              title: Text(l10n.globalMediaKeys),
              subtitle: Text(l10n.globalMediaKeysDescription),
            ),
          ),
          const SizedBox(height: 24),
          Text(
            l10n.stationCatalog,
            style: Theme.of(
              context,
            ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 8),
          Card(
            margin: EdgeInsets.zero,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(8),
              side: BorderSide(
                color: colorScheme.outlineVariant.withValues(alpha: 0.45),
              ),
            ),
            child: Consumer<StationModel>(
              builder: (context, stationModel, child) {
                return SwitchListTile(
                  value: stationModel.hideOfflineStations,
                  onChanged: stationModel.setHideOfflineStations,
                  secondary: const Icon(Icons.cloud_off_outlined),
                  title: Text(l10n.hideOfflineStations),
                  subtitle: Text(l10n.hideOfflineStationsDescription),
                );
              },
            ),
          ),
          const SizedBox(height: 24),
          Text(
            l10n.appLanguage,
            style: Theme.of(
              context,
            ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 8),
          Card(
            margin: EdgeInsets.zero,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(8),
              side: BorderSide(
                color: colorScheme.outlineVariant.withValues(alpha: 0.45),
              ),
            ),
            child: Consumer<AppLocaleProvider>(
              builder: (context, localeProvider, child) {
                return ListTile(
                  leading: const Icon(Icons.language),
                  title: Text(l10n.appLanguage),
                  subtitle: Text(l10n.appLanguageDescription),
                  trailing: DropdownButtonHideUnderline(
                    child: DropdownButton<Locale>(
                      value: localeProvider.locale,
                      items: [
                        DropdownMenuItem(
                          value: const Locale('en'),
                          child: Text(l10n.english),
                        ),
                        DropdownMenuItem(
                          value: const Locale('zh'),
                          child: Text(l10n.simplifiedChinese),
                        ),
                      ],
                      onChanged: (locale) => _setLocale(context, locale),
                    ),
                  ),
                );
              },
            ),
          ),
          const SizedBox(height: 24),
          Text(
            l10n.about,
            style: Theme.of(
              context,
            ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 8),
          Card(
            margin: EdgeInsets.zero,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(8),
              side: BorderSide(
                color: colorScheme.outlineVariant.withValues(alpha: 0.45),
              ),
            ),
            child: Column(
              children: [
                ListTile(
                  leading: const Icon(Icons.person_outline),
                  title: Text(l10n.author),
                  trailing: const Text("pinellia"),
                ),
                const Divider(height: 1),
                ListTile(
                  leading: const Icon(Icons.email_outlined),
                  title: Text(l10n.email),
                  trailing: const Text("pinellia.gg@outlook.com"),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _setGlobalMediaKeysEnabled(bool enabled) async {
    setState(() {
      _globalMediaKeysEnabled = enabled;
    });

    ConfigMgr().put(ConfigKeys.KEY_GLOBAL_MEDIA_KEYS_ENABLED, enabled).save();
    await WindowsMediaKeyService.setGlobalMediaKeysEnabled(enabled);
  }

  Future<void> _setLocale(BuildContext context, Locale? locale) async {
    if (locale == null) {
      return;
    }
    await context.read<AppLocaleProvider>().setLocale(locale);
    if (!mounted) {
      return;
    }
    await WidgetsBinding.instance.endOfFrame;
    if (!mounted || !context.mounted) {
      return;
    }
    final localizations = AppLocalizations.of(context);
    if (localizations != null) {
      await WindowsDesktopService.instance.updateLocalizations(localizations);
    }
  }
}
