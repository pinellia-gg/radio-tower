import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:radio_tower/pages/MainLayout.dart';
import 'package:radio_tower/manger/AssetManager.dart';
import 'package:radio_tower/manger/AssetRes.dart';
import 'package:radio_tower/l10n/app_localizations.dart';
import 'package:radio_tower/player/WindowsMediaKeyService.dart';
import 'package:radio_tower/provider/AppLocaleProvider.dart';
import 'package:radio_tower/services/WindowsDesktopService.dart';

import '../manger/ConfigKeys.dart';
import '../manger/ConfigMgr.dart';

class LauncherPage extends StatelessWidget {
  const LauncherPage({super.key});

  @override
  Widget build(BuildContext context) {
    return _LauncherPageStatefulView();
  }
}

class _LauncherPageStatefulView extends StatefulWidget {
  @override
  State<StatefulWidget> createState() {
    return _LauncherPageStatefulViewState();
  }
}

class _LauncherPageStatefulViewState extends State<_LauncherPageStatefulView> {
  static const Duration _minimumSplashDuration = Duration(milliseconds: 350);

  @override
  Widget build(BuildContext context) {
    var image = AssetManager.loadImage(AssetRes.IC_LAUNCHER);

    return Scaffold(
      appBar: null,
      floatingActionButton: null,
      body: Center(child: image),
    );
  }

  @override
  void initState() {
    super.initState();
    startApp();
  }

  Future<void> startApp() async {
    final startedAt = DateTime.now();
    await ConfigMgr().init();
    if (!mounted || !context.mounted) {
      return;
    }
    await context.read<AppLocaleProvider>().load();
    await WidgetsBinding.instance.endOfFrame;
    if (!mounted || !context.mounted) {
      return;
    }
    await WindowsMediaKeyService.setGlobalMediaKeysEnabled(
      ConfigMgr().getBoolVal(ConfigKeys.KEY_GLOBAL_MEDIA_KEYS_ENABLED, false),
    );
    await WindowsDesktopService.instance.initialize(
      AppLocalizations.of(context)!,
    );
    final remainingDuration =
        _minimumSplashDuration - DateTime.now().difference(startedAt);
    if (!remainingDuration.isNegative) {
      await Future.delayed(remainingDuration);
    }
    navigateToMainLayout();
  }

  void navigateToMainLayout() {
    if (mounted) {
      // Check if the widget is still in the tree
      Navigator.pushReplacement(
        // Use pushReplacement to prevent going back to splash
        context,
        MaterialPageRoute(builder: (context) => const MainLayout()),
      );
    }
  }
}
