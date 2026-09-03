import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:lib_common/log/Logger.dart';
import 'package:media_kit/media_kit.dart';
import 'package:provider/provider.dart';
import 'package:radio_tower/common/CustomCrollBehavior.dart';
import 'package:radio_tower/l10n/app_localizations.dart';
import 'package:radio_tower/pages/LauncherPage.dart';
import 'package:radio_tower/provider/AppLocaleProvider.dart';
import 'package:radio_tower/provider/FavoriteModel.dart';
import 'package:radio_tower/provider/PlayerController.dart';
import 'package:radio_tower/provider/RecentPlayModel.dart';
import 'package:radio_tower/provider/StationModel.dart';
import 'package:radio_tower/views/AppWindowFrame.dart';
import 'package:window_manager/window_manager.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await _configureWindow();
  _configureLogger();
  MediaKit.ensureInitialized();
  runApp(
    MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (context) => StationModel()),
        ChangeNotifierProvider(
          create: (context) => FavoriteModel(),
          lazy: false,
        ),
        ChangeNotifierProvider(create: (context) => RecentPlayModel()),
        ChangeNotifierProvider(
          create: (context) => PlayerController(),
          lazy: false,
        ),
      ],
      child: const MyApp(),
    ),
  );
}

Future<void> _configureWindow() async {
  if (kIsWeb || defaultTargetPlatform != TargetPlatform.windows) {
    return;
  }

  await windowManager.ensureInitialized();
  const windowOptions = WindowOptions(
    minimumSize: Size(900, 620),
    title: 'Radio Tower',
    titleBarStyle: TitleBarStyle.hidden,
    windowButtonVisibility: false,
  );

  await windowManager.waitUntilReadyToShow(windowOptions, () async {
    await windowManager.show();
    await windowManager.focus();
  });
}

void _configureLogger() {
  Logger.configure(fileLogEnabled: true);
  Logger.iLog('MainApp', 'Radio Tower 启动，日志目录: ${Logger.logDirectory.path}');
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  // This widget is the root of your application.
  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider(
      create: (context) => AppLocaleProvider(),
      child: const _AppView(),
    );
  }
}

class _AppView extends StatelessWidget {
  const _AppView();

  @override
  Widget build(BuildContext context) {
    final locale = context.watch<AppLocaleProvider>().locale;
    return MaterialApp(
      //是否显示Debug标志
      debugShowCheckedModeBanner: false,
      scrollBehavior: CustomScrollBehavior(),
      locale: locale,
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocaleProvider.supportedLocales,
      onGenerateTitle: (context) => AppLocalizations.of(context)!.appTitle,
      theme: ThemeData(
        // This is the theme of your application.
        //
        // TRY THIS: Try running your application with "flutter run". You'll see
        // the application has a purple toolbar. Then, without quitting the radio_tower,
        // try changing the seedColor in the colorScheme below to Colors.green
        // and then invoke "hot reload" (save your changes or press the "hot
        // reload" button in a Flutter-supported IDE, or press "r" if you used
        // the command line to start the radio_tower).
        //
        // Notice that the counter didn't reset back to zero; the application
        // state is not lost during the reload. To reset the state, use hot
        // restart instead.
        //
        // This works for code too, not just values: Most code changes can be
        // tested with just a hot reload.
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.deepPurple),
        // The app targets Windows and primarily displays Chinese. Use its UI
        // font instead of letting individual glyphs fall back from Segoe UI.
        fontFamily: 'Microsoft YaHei UI',
      ),
      builder: (context, child) {
        return AppWindowFrame(child: child ?? const SizedBox.shrink());
      },
      // home: HomePage2().build(context),
      // home: const HomePage(title: "小工具"),
      home: const LauncherPage(),
    );
  }
}
