import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:radio_tower/entity/RadioStation.dart';
import 'package:radio_tower/l10n/app_localizations.dart';
import 'package:radio_tower/manger/ConfigKeys.dart';
import 'package:radio_tower/manger/ConfigMgr.dart';
import 'package:radio_tower/pages/FavoritesPage.dart';
import 'package:radio_tower/pages/RadioStationsPage.dart';
import 'package:radio_tower/pages/RecentPlaysPage.dart';
import 'package:radio_tower/pages/SettingsPage.dart';
import 'package:radio_tower/player/PlayInfo.dart';
import 'package:radio_tower/provider/PlayerController.dart';
import 'package:radio_tower/provider/RecentPlayModel.dart';
import 'package:radio_tower/services/WindowsDesktopService.dart';
import 'package:radio_tower/views/PlaybackBar.dart';

class MainLayout extends StatefulWidget {
  const MainLayout({super.key});

  @override
  State<StatefulWidget> createState() {
    return _MainLayoutState();
  }
}

class _MainLayoutState extends State<MainLayout> {
  int _selectedIndex = 0;

  late final PlayerController _playerController;
  late final ValueNotifier<PlayInfo> _playInfoNotifier;
  late final List<Widget> _pages;
  String? _lastRememberedStationUuid;
  String? _lastWindowsStationUuid;
  bool? _lastWindowsIsPlaying;

  @override
  void initState() {
    super.initState();
    final initialPlayInfo = _createInitialPlayInfo();
    _playerController = context.read<PlayerController>();
    _playInfoNotifier = _playerController.playInfoNotifier;
    _lastRememberedStationUuid = initialPlayInfo.radioStation?.stationuuid;
    _playInfoNotifier.addListener(_rememberLastPlayedStation);
    _playerController.addListener(_updateWindowsPlaybackState);
    // Initializing updates Provider listeners. Run it after the first frame so
    // the provider scope is no longer being built when it dispatches.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        _playerController.initialize(initialPlayInfo);
      }
    });
    _pages = [
      const RadioStationsPage(),
      const FavoritesPage(),
      const RecentPlaysPage(),
      const SettingsPage(),
    ];
  }

  @override
  void dispose() {
    _playInfoNotifier.removeListener(_rememberLastPlayedStation);
    _playerController.removeListener(_updateWindowsPlaybackState);
    super.dispose();
  }

  PlayInfo _createInitialPlayInfo() {
    final stationJson = ConfigMgr().getMapVal(
      ConfigKeys.KEY_LAST_PLAYED_STATION,
      {},
    );
    if (stationJson.isEmpty) {
      return createEmptyPlayInfo();
    }

    try {
      return (
        radioStation: RadioStation.fromJson(
          Map<String, dynamic>.from(stationJson),
        ),
        musicInfo: "",
        needPlay: false,
      );
    } catch (_) {
      return createEmptyPlayInfo();
    }
  }

  void _rememberLastPlayedStation() {
    final playInfo = _playInfoNotifier.value;
    final station = playInfo.radioStation;
    if (station == null || station.stationuuid.isEmpty) {
      return;
    }

    if (playInfo.needPlay) {
      unawaited(context.read<RecentPlayModel>().recordStation(station));
    }

    if (_lastRememberedStationUuid == station.stationuuid) {
      return;
    }

    _lastRememberedStationUuid = station.stationuuid;
    ConfigMgr()
        .put(ConfigKeys.KEY_LAST_PLAYED_STATION, station.toJson())
        .save();
  }

  void _updateWindowsPlaybackState() {
    final station = _playerController.station;
    final isPlaying = _playerController.isPlaying;
    if (_lastWindowsStationUuid == station?.stationuuid &&
        _lastWindowsIsPlaying == isPlaying) {
      return;
    }
    _lastWindowsStationUuid = station?.stationuuid;
    _lastWindowsIsPlaying = isPlaying;
    unawaited(
      WindowsDesktopService.instance.updateNowPlaying(
        station,
        isPlaying: isPlaying,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final showPlayerBar = _selectedIndex != 3;
    final l10n = AppLocalizations.of(context)!;

    return Scaffold(
      body: Row(
        children: [
          // 左侧导航栏
          Container(
            width: 70,
            color: Theme.of(context).colorScheme.surface,
            child: Column(
              children: [
                // 顶部导航项
                _buildNavItem(0, Icons.radio, Icons.radio, l10n.stations),
                _buildNavItem(
                  1,
                  Icons.favorite_border,
                  Icons.favorite,
                  l10n.favorites,
                ),
                _buildNavItem(2, Icons.history, Icons.history, l10n.recent),
                // 中间空白区域
                const Spacer(),
                // 底部设置按钮
                _buildNavItem(
                  3,
                  Icons.settings_outlined,
                  Icons.settings,
                  l10n.settings,
                ),
                const SizedBox(height: 16),
              ],
            ),
          ),
          const VerticalDivider(thickness: 1, width: 1),
          // 右侧内容区域（使用IndexedStack保持页面状态）
          Expanded(
            child: Column(
              children: [
                Expanded(
                  child: IndexedStack(index: _selectedIndex, children: _pages),
                ),
                Visibility(
                  visible: showPlayerBar,
                  maintainState: true,
                  child: const PlaybackBar(),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildNavItem(
    int index,
    IconData icon,
    IconData selectedIcon,
    String label,
  ) {
    final isSelected = _selectedIndex == index;
    return InkWell(
      onTap: () {
        setState(() {
          _selectedIndex = index;
        });
      },
      child: Container(
        width: 80,
        padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 8),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              isSelected ? selectedIcon : icon,
              color: isSelected ? Theme.of(context).primaryColor : Colors.grey,
              size: 24,
            ),
            const SizedBox(height: 4),
            Text(
              label,
              style: TextStyle(
                fontSize: 12,
                color:
                    isSelected ? Theme.of(context).primaryColor : Colors.grey,
                fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
              ),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }
}
