import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:radio_tower/common/extensions/StringEx.dart';
import 'package:radio_tower/entity/RadioStation.dart';
import 'package:radio_tower/l10n/app_localizations.dart';
import 'package:radio_tower/manger/AssetManager.dart';
import 'package:radio_tower/player/MediaKitPlayer.dart';
import 'package:radio_tower/provider/FavoriteModel.dart';
import 'package:radio_tower/provider/PlayerController.dart';
import 'package:radio_tower/views/FavoriteListPickerDialog.dart';
import 'package:radio_tower/views/StationFavicon.dart';
import 'package:url_launcher/url_launcher.dart';

import '../manger/AssetRes.dart';

class PlaybackBar extends StatefulWidget {
  const PlaybackBar({super.key});

  @override
  State<StatefulWidget> createState() {
    return _PlaybackBarState();
  }
}

class _PlaybackBarState extends State<PlaybackBar>
    with SingleTickerProviderStateMixin {
  static const double _collapsedBarHeight = 76.0;

  late final PlayerController _playerController;
  bool _isExpanded = false;
  OverlayEntry? _expandedOverlayEntry;
  late TabController _tabController;
  int _lastShownErrorSequence = 0;
  ScaffoldFeatureController<SnackBar, SnackBarClosedReason>?
  _playbackErrorSnackBar;

  RadioStation? get _station => _playerController.station;
  String get _musicInfo => _playerController.musicInfo;
  double get _currentVolume => _playerController.currentVolume;
  bool get _isMuted => _playerController.isMuted;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _playerController = context.read<PlayerController>();
    _playerController.addListener(_onPlayerControllerChanged);
  }

  @override
  void dispose() {
    _removeExpandedOverlay(updateState: false);
    _tabController.dispose();
    _playerController.removeListener(_onPlayerControllerChanged);
    super.dispose();
  }

  void _onPlayerControllerChanged() {
    if (!mounted) {
      return;
    }

    final playbackError = _playerController.playbackError;
    if (playbackError != null &&
        playbackError.sequence > _lastShownErrorSequence) {
      _lastShownErrorSequence = playbackError.sequence;
      _showPlaybackError(playbackError);
    }
    setState(() {});
    _expandedOverlayEntry?.markNeedsBuild();
  }

  void _showPlaybackError(PlaybackError playbackError) {
    // 连续的底层播放错误会在自动恢复期间快速上报。ScaffoldMessenger
    // 会把每次 showSnackBar 调用排队，导致用户需要逐个关闭重复提示。
    if (_playbackErrorSnackBar != null) {
      return;
    }

    late final ScaffoldFeatureController<SnackBar, SnackBarClosedReason>
    snackBarController;
    snackBarController = ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          _playbackErrorMessage(AppLocalizations.of(context)!, playbackError),
        ),
        duration: const Duration(seconds: 6),
        action: SnackBarAction(
          label: AppLocalizations.of(context)!.retry,
          onPressed: () {
            _playerController.requestPlayback(true, forceReload: true);
          },
        ),
      ),
    );
    _playbackErrorSnackBar = snackBarController;
    snackBarController.closed.whenComplete(() {
      if (identical(_playbackErrorSnackBar, snackBarController)) {
        _playbackErrorSnackBar = null;
      }
    });
  }

  void _togglePlayPause() {
    _playerController.togglePlayPause();
  }

  String _playbackErrorMessage(
    AppLocalizations l10n,
    PlaybackError playbackError,
  ) {
    switch (playbackError.kind) {
      case PlaybackErrorKind.noPlayableUrl:
        return l10n.playbackNoUrl;
      case PlaybackErrorKind.reconnecting:
        return l10n.playbackReconnecting;
    }
  }

  void _toggleMute() {
    _playerController.toggleMute();
  }

  void _setVolume(double volume, {bool? muted}) {
    _playerController.setVolume(volume, muted: muted);
  }

  IconData get _volumeIcon {
    if (_isMuted || _currentVolume == 0) {
      return Icons.volume_off;
    }
    if (_currentVolume < 50) {
      return Icons.volume_down;
    }
    return Icons.volume_up;
  }

  @override
  Widget build(BuildContext context) {
    return Material(
      elevation: 10,
      color: Theme.of(context).colorScheme.surface,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [const Divider(height: 1), _buildCompactBar()],
      ),
    );
  }

  void _toggleExpandedOverlay() {
    if (_isExpanded) {
      _removeExpandedOverlay();
      return;
    }

    final overlay = Overlay.of(context, rootOverlay: true);
    _expandedOverlayEntry = OverlayEntry(
      builder:
          (overlayContext) =>
              Positioned.fill(child: _buildExpandedOverlay(overlayContext)),
    );
    overlay.insert(_expandedOverlayEntry!);
    setState(() {
      _isExpanded = true;
    });
  }

  void _removeExpandedOverlay({bool updateState = true}) {
    _expandedOverlayEntry?.remove();
    _expandedOverlayEntry = null;
    if (updateState && mounted && _isExpanded) {
      setState(() {
        _isExpanded = false;
      });
    } else {
      _isExpanded = false;
    }
  }

  Widget _buildExpandedOverlay(BuildContext context) {
    return Material(
      elevation: 18,
      color: Theme.of(context).colorScheme.surface,
      child: Column(
        children: [
          Expanded(
            child: Column(
              children: [
                TabBar(
                  controller: _tabController,
                  labelColor: Theme.of(context).primaryColor,
                  unselectedLabelColor: Colors.grey,
                  tabs: [
                    Tab(text: AppLocalizations.of(context)!.nowPlaying),
                    Tab(text: AppLocalizations.of(context)!.stationInfo),
                  ],
                ),
                Expanded(
                  child: TabBarView(
                    controller: _tabController,
                    children: [_buildPlayerTab(), _buildInfoTab()],
                  ),
                ),
              ],
            ),
          ),
          const Divider(height: 1),
          _buildCompactBar(onTap: _removeExpandedOverlay),
        ],
      ),
    );
  }

  Widget _buildCompactBar({VoidCallback? onTap}) {
    return SizedBox(
      height: _collapsedBarHeight,
      child: InkWell(
        onTap: onTap ?? _toggleExpandedOverlay,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: LayoutBuilder(
            builder: (context, constraints) {
              final targetVolumeWidth =
                  constraints.maxWidth < 720 ? 148.0 : 220.0;
              final sideWidth = (constraints.maxWidth - 72) / 2;
              final volumeWidth =
                  sideWidth < targetVolumeWidth
                      ? sideWidth.clamp(44.0, targetVolumeWidth).toDouble()
                      : targetVolumeWidth;
              return Row(
                children: [
                  Expanded(child: _buildCompactStationSummary()),
                  SizedBox(
                    width: 72,
                    child: Center(
                      child: _buildPlayPauseButton(size: 52, iconSize: 34),
                    ),
                  ),
                  Expanded(
                    child: Align(
                      alignment: Alignment.centerRight,
                      child: SizedBox(
                        width: volumeWidth,
                        child: _buildVolumeControl(),
                      ),
                    ),
                  ),
                ],
              );
            },
          ),
        ),
      ),
    );
  }

  Widget _buildCompactStationSummary() {
    final station = _station;
    final stationName =
        station?.name.orEmpty().isNotEmpty == true
            ? station!.name
            : AppLocalizations.of(context)!.noStationPlaying;
    final badges = _buildStationFormatBadges(station);

    return Row(
      children: [
        _buildStationArtwork(48, borderRadius: 8, fallbackIconSize: 26),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      stationName,
                      style: const TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w600,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  if (badges.isNotEmpty) ...[
                    const SizedBox(width: 8),
                    ...badges,
                  ],
                ],
              ),
              if (_musicInfo.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(top: 2),
                  child: Text(
                    _musicInfo,
                    style: TextStyle(fontSize: 12, color: Colors.grey[600]),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
            ],
          ),
        ),
        const SizedBox(width: 8),
        _buildFavoriteButton(size: 44, iconSize: 24, showBackground: false),
      ],
    );
  }

  List<Widget> _buildStationFormatBadges(RadioStation? station) {
    if (station == null) {
      return const [];
    }

    return [
      if (station.bitrate > 0)
        _buildStationFormatBadge("${station.bitrate}kbps", Colors.blue),
      if (station.hls) _buildStationFormatBadge("HLS", Colors.orange),
    ];
  }

  Widget _buildStationFormatBadge(String text, Color color) {
    return Container(
      margin: const EdgeInsets.only(left: 4),
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Text(
        text,
        style: TextStyle(
          fontSize: 12,
          color: color,
          fontWeight: FontWeight.w500,
        ),
      ),
    );
  }

  Widget _buildStationArtwork(
    double size, {
    required double borderRadius,
    required double fallbackIconSize,
  }) {
    final iconUrl = _station?.favicon.orEmpty() ?? "";
    return StationFavicon(
      imageUrl: iconUrl,
      size: size,
      borderRadius: BorderRadius.circular(borderRadius),
      fallbackIconSize: fallbackIconSize,
    );
  }

  Widget _buildPlayPauseButton({
    required double size,
    required double iconSize,
  }) {
    final playPauseImage =
        _playerController.isPlaying
            ? AssetManager.loadImage(AssetRes.IC_PAUSE)
            : AssetManager.loadImage(AssetRes.IC_PLAY);

    return SizedBox(
      width: size,
      height: size,
      child: Tooltip(
        message:
            _playerController.isPlaying
                ? AppLocalizations.of(context)!.pause
                : AppLocalizations.of(context)!.play,
        child: IconButton(
          onPressed:
              _station == null && !_playerController.isPlaying
                  ? null
                  : _togglePlayPause,
          icon: playPauseImage,
          iconSize: iconSize,
          padding: EdgeInsets.zero,
          style: IconButton.styleFrom(
            backgroundColor: Theme.of(
              context,
            ).primaryColor.withValues(alpha: 0.1),
          ),
        ),
      ),
    );
  }

  Widget _buildVolumeControl() {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        SizedBox(
          width: 44,
          height: 44,
          child: Tooltip(
            message:
                _isMuted
                    ? AppLocalizations.of(context)!.unmute
                    : AppLocalizations.of(context)!.mute,
            child: IconButton(
              onPressed: _toggleMute,
              icon: Icon(_volumeIcon),
              color: _isMuted ? Colors.redAccent : null,
              padding: EdgeInsets.zero,
            ),
          ),
        ),
        Expanded(
          child: Slider(
            value: _currentVolume,
            min: 0,
            max: 100,
            onChanged:
                (newVolume) => _setVolume(newVolume, muted: newVolume == 0),
          ),
        ),
      ],
    );
  }

  Widget _buildPlayerTab() {
    String name = (_station?.name).orEmpty();
    if (name.isEmpty) {
      name = AppLocalizations.of(context)!.noStationPlaying;
    }

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Column(
        children: [
          Expanded(
            child: LayoutBuilder(
              builder: (context, constraints) {
                final maxSize = constraints.maxHeight * 0.75;
                final iconSize = maxSize > 300 ? 300.0 : maxSize;
                return SingleChildScrollView(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const SizedBox(height: 16),
                      ClipRRect(
                        borderRadius: BorderRadius.circular(16),
                        child: SizedBox(
                          width: iconSize,
                          height: iconSize,
                          child: _buildStationArtwork(
                            iconSize,
                            borderRadius: 16,
                            fallbackIconSize: 100,
                          ),
                        ),
                      ),
                      const SizedBox(height: 16),
                      Text(
                        name,
                        style: const TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                        ),
                        textAlign: TextAlign.center,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                      if (_musicInfo.isNotEmpty)
                        Padding(
                          padding: const EdgeInsets.only(top: 4),
                          child: Text(
                            _musicInfo,
                            style: TextStyle(
                              fontSize: 14,
                              color: Colors.grey[600],
                            ),
                            textAlign: TextAlign.center,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                    ],
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildFavoriteButton({
    double size = 48,
    double iconSize = 28,
    bool showBackground = true,
  }) {
    return Consumer<FavoriteModel>(
      builder: (context, favoriteModel, child) {
        final station = _station;
        final isFavorite = favoriteModel.isInDefaultList(station);
        return SizedBox(
          width: size,
          height: size,
          child: Tooltip(
            message:
                isFavorite
                    ? AppLocalizations.of(context)!.favorited
                    : AppLocalizations.of(context)!.addToFavorites,
            child: IconButton(
              onPressed:
                  station == null
                      ? null
                      : () {
                        showFavoriteListPicker(context, station);
                      },
              icon: Icon(
                isFavorite ? Icons.favorite : Icons.favorite_border,
                size: iconSize,
              ),
              color: isFavorite ? Colors.redAccent : Colors.grey[500],
              style:
                  showBackground
                      ? IconButton.styleFrom(
                        backgroundColor:
                            isFavorite
                                ? Colors.redAccent.withValues(alpha: 0.12)
                                : Colors.grey.withValues(alpha: 0.08),
                      )
                      : null,
            ),
          ),
        );
      },
    );
  }

  Widget _buildInfoTab() {
    if (_station == null) {
      return Center(child: Text(AppLocalizations.of(context)!.noStationInfo));
    }

    final station = _station!;

    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildInfoHeader(station),
          const Divider(height: 32),
          _buildInfoSection(AppLocalizations.of(context)!.basicInformation, [
            _buildInfoRow(
              AppLocalizations.of(context)!.stationName,
              station.name,
            ),
            _buildInfoRow(
              AppLocalizations.of(context)!.stationId,
              station.stationuuid,
            ),
            if (station.country.isNotEmpty)
              _buildInfoRow(
                AppLocalizations.of(context)!.country,
                '${station.country}${station.countrycode.isNotEmpty ? ' (${station.countrycode})' : ''}',
              ),
            if (station.state.isNotEmpty)
              _buildInfoRow(
                AppLocalizations.of(context)!.stateProvince,
                station.state,
              ),
            if (station.language.isNotEmpty)
              _buildInfoRow(
                AppLocalizations.of(context)!.language,
                station.language,
              ),
          ]),
          const SizedBox(height: 16),
          _buildInfoSection(AppLocalizations.of(context)!.streamInformation, [
            _buildCopyableInfoRow(
              AppLocalizations.of(context)!.streamUrl,
              _resolveCopyableStreamUrl(station),
            ),
            _buildInfoRow(AppLocalizations.of(context)!.codec, station.codec),
            _buildInfoRow(
              AppLocalizations.of(context)!.bitrate,
              '${station.bitrate} kbps',
            ),
            _buildInfoRow(
              AppLocalizations.of(context)!.hlsStream,
              station.hls
                  ? AppLocalizations.of(context)!.yes
                  : AppLocalizations.of(context)!.no,
            ),
          ]),
          const SizedBox(height: 16),
          _buildInfoSection(AppLocalizations.of(context)!.statistics, [
            _buildInfoRow(
              AppLocalizations.of(context)!.clickCount,
              station.clickcount.toString(),
            ),
            _buildInfoRow(
              AppLocalizations.of(context)!.voteCount,
              station.votes.toString(),
            ),
            _buildInfoRow(
              AppLocalizations.of(context)!.clickTrend,
              station.clicktrend.toString(),
            ),
          ]),
          if (station.homepage.isNotEmpty) ...[
            const SizedBox(height: 16),
            _buildInfoSection(AppLocalizations.of(context)!.links, [
              _buildLinkRow(
                AppLocalizations.of(context)!.officialWebsite,
                station.homepage,
              ),
            ]),
          ],
          if (station.tags.isNotEmpty) ...[
            const SizedBox(height: 16),
            _buildInfoSection(AppLocalizations.of(context)!.tag, [
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children:
                    station.tags
                        .split(',')
                        .where((tag) => tag.trim().isNotEmpty)
                        .map((tag) {
                          return Chip(
                            label: Text(tag.trim()),
                            backgroundColor: Theme.of(
                              context,
                            ).primaryColor.withValues(alpha: 0.1),
                            labelStyle: TextStyle(
                              color: Theme.of(context).primaryColor,
                              fontSize: 12,
                            ),
                          );
                        })
                        .toList(),
              ),
            ]),
          ],
        ],
      ),
    );
  }

  Widget _buildInfoHeader(RadioStation station) {
    return Row(
      children: [
        StationFavicon(
          imageUrl: station.favicon,
          size: 80,
          borderRadius: BorderRadius.circular(12),
          fallbackIconSize: 40,
        ),
        const SizedBox(width: 16),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                station.name,
                style: const TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                ),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
              const SizedBox(height: 4),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color:
                      station.lastcheckok
                          ? Colors.green.withValues(alpha: 0.1)
                          : Colors.red.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Text(
                  station.lastcheckok
                      ? AppLocalizations.of(context)!.online
                      : AppLocalizations.of(context)!.offline,
                  style: TextStyle(
                    color: station.lastcheckok ? Colors.green : Colors.red,
                    fontSize: 12,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildInfoSection(String title, List<Widget> children) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 8),
        Card(
          margin: EdgeInsets.zero,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Column(children: children),
          ),
        ),
      ],
    );
  }

  Widget _buildInfoRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 80,
            child: Text(
              label,
              style: TextStyle(color: Colors.grey[600], fontSize: 14),
            ),
          ),
          Expanded(
            child: Text(
              value.isNotEmpty ? value : '-',
              style: const TextStyle(fontSize: 14),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCopyableInfoRow(String label, String value) {
    final streamUrl = value.trim();
    final hasStreamUrl = _isValidStreamUrl(streamUrl);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 80,
            child: Text(
              label,
              style: TextStyle(color: Colors.grey[600], fontSize: 14),
            ),
          ),
          Expanded(
            child: InkWell(
              onTap: hasStreamUrl ? () => _copyStreamUrl(streamUrl) : null,
              borderRadius: BorderRadius.circular(4),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
                child: Text(
                  hasStreamUrl ? streamUrl : '-',
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: 14),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _copyStreamUrl(String streamUrl) async {
    try {
      await Clipboard.setData(ClipboardData(text: streamUrl));
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(
          SnackBar(
            content: Text(AppLocalizations.of(context)!.streamUrlCopied),
          ),
        );
    } catch (_) {
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(
          SnackBar(
            content: Text(AppLocalizations.of(context)!.copyStreamUrlFailed),
          ),
        );
    }
  }

  String _resolveCopyableStreamUrl(RadioStation station) {
    for (final candidate in [station.url_resolved, station.url]) {
      final streamUrl = candidate.trim();
      if (_isValidStreamUrl(streamUrl)) {
        return streamUrl;
      }
    }
    return '';
  }

  bool _isValidStreamUrl(String streamUrl) {
    final uri = Uri.tryParse(streamUrl);
    return uri != null && uri.hasScheme && uri.host.isNotEmpty;
  }

  Widget _buildLinkRow(String label, String url) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 80,
            child: Text(
              label,
              style: TextStyle(color: Colors.grey[600], fontSize: 14),
            ),
          ),
          Expanded(
            child: GestureDetector(
              onTap: () => _launchUrl(url),
              child: Text(
                url,
                style: TextStyle(
                  fontSize: 14,
                  color: Theme.of(context).primaryColor,
                  decoration: TextDecoration.underline,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _launchUrl(String url) async {
    final uri = Uri.parse(url);
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri);
    }
  }
}
