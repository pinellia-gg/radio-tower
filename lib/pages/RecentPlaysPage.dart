import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:radio_tower/entity/RadioStation.dart';
import 'package:radio_tower/l10n/app_localizations.dart';
import 'package:radio_tower/provider/PlayerController.dart';
import 'package:radio_tower/provider/RecentPlayModel.dart';
import 'package:radio_tower/views/StationFavicon.dart';

class RecentPlaysPage extends StatelessWidget {
  const RecentPlaysPage({super.key});

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return Scaffold(
      appBar: AppBar(
        title: Text(l10n.recentPlays),
        actions: [
          Consumer<RecentPlayModel>(
            builder: (context, recentPlayModel, child) {
              return IconButton(
                tooltip: l10n.clearRecentPlays,
                onPressed:
                    recentPlayModel.stations.isEmpty
                        ? null
                        : () => _confirmClear(context, recentPlayModel),
                icon: const Icon(Icons.delete_sweep_outlined),
              );
            },
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: Consumer<RecentPlayModel>(
        builder: (context, recentPlayModel, child) {
          final playerController = context.read<PlayerController>();
          if (recentPlayModel.isLoading && recentPlayModel.stations.isEmpty) {
            return const Center(child: CircularProgressIndicator());
          }
          final stations = recentPlayModel.stations;
          if (stations.isEmpty) {
            return Center(child: Text(l10n.noRecentStations));
          }
          return ValueListenableBuilder(
            valueListenable: playerController.playInfoNotifier,
            builder:
                (context, playInfo, child) => ListView.builder(
                  padding: const EdgeInsets.all(16),
                  itemCount: stations.length,
                  itemBuilder: (context, index) {
                    final station = stations[index];
                    return _buildStationCard(
                      context,
                      station,
                      playInfo.radioStation?.stationuuid == station.stationuuid,
                      playerController,
                    );
                  },
                ),
          );
        },
      ),
    );
  }

  Widget _buildStationCard(
    BuildContext context,
    RadioStation station,
    bool isPlaying,
    PlayerController playerController,
  ) {
    final colorScheme = Theme.of(context).colorScheme;
    return Card(
      margin: const EdgeInsets.symmetric(vertical: 4),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: () {
          playerController.selectStation(station);
        },
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Row(
            children: [
              StationFavicon(
                imageUrl: station.favicon,
                size: 44,
                borderRadius: BorderRadius.circular(8),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      station.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontWeight: FontWeight.w600,
                        color: isPlaying ? Colors.green : null,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      [
                        if (station.country.isNotEmpty) station.country,
                        if (station.language.isNotEmpty) station.language,
                        if (station.bitrate > 0) '${station.bitrate}kbps',
                      ].join(' / '),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(color: colorScheme.onSurfaceVariant),
                    ),
                  ],
                ),
              ),
              Icon(
                isPlaying ? Icons.equalizer : Icons.play_arrow_rounded,
                color: isPlaying ? Colors.green : colorScheme.primary,
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _confirmClear(
    BuildContext context,
    RecentPlayModel recentPlayModel,
  ) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder:
          (context) => AlertDialog(
            title: Text(AppLocalizations.of(context)!.clearRecentPlays),
            content: Text(
              AppLocalizations.of(context)!.clearRecentPlaysConfirmation,
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: Text(AppLocalizations.of(context)!.cancel),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(context, true),
                child: Text(AppLocalizations.of(context)!.clear),
              ),
            ],
          ),
    );
    if (confirmed == true && context.mounted) {
      await recentPlayModel.clear();
    }
  }
}
