import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:radio_tower/entity/FavoriteList.dart';
import 'package:radio_tower/entity/RadioStation.dart';
import 'package:radio_tower/l10n/app_localizations.dart';
import 'package:radio_tower/provider/FavoriteModel.dart';
import 'package:radio_tower/provider/PlayerController.dart';
import 'package:radio_tower/views/FavoriteListPickerDialog.dart';
import 'package:radio_tower/views/StationFavicon.dart';

enum _FavoriteListMenuAction { rename, delete }

class FavoritesPage extends StatefulWidget {
  const FavoritesPage({super.key});

  @override
  State<FavoritesPage> createState() {
    return _FavoritesPageState();
  }
}

class _FavoritesPageState extends State<FavoritesPage> {
  int _selectedListId = 0;
  late final PlayerController _playerController;

  @override
  void initState() {
    super.initState();
    _playerController = context.read<PlayerController>();
    _playerController.playInfoNotifier.addListener(_onPlayInfoChanged);
  }

  @override
  void dispose() {
    _playerController.playInfoNotifier.removeListener(_onPlayInfoChanged);
    super.dispose();
  }

  void _onPlayInfoChanged() {
    if (mounted) {
      setState(() {});
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return Scaffold(
      appBar: AppBar(title: Text(l10n.favorites)),
      body: Consumer<FavoriteModel>(
        builder: (context, favoriteModel, child) {
          final lists = favoriteModel.favoriteLists;
          if (favoriteModel.isLoading && lists.isEmpty) {
            return const Center(child: CircularProgressIndicator());
          }

          final selectedList = _resolveSelectedList(lists);
          final stations =
              selectedList == null
                  ? <RadioStation>[]
                  : favoriteModel.stationsForList(selectedList.id);

          return Row(
            children: [
              _buildFavoriteLists(context, favoriteModel, lists, selectedList),
              const VerticalDivider(width: 1, thickness: 1),
              Expanded(
                child: _buildStationPane(
                  context,
                  favoriteModel,
                  selectedList,
                  stations,
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  FavoriteList? _resolveSelectedList(List<FavoriteList> lists) {
    if (lists.isEmpty) {
      return null;
    }

    for (final list in lists) {
      if (list.id == _selectedListId) {
        return list;
      }
    }

    for (final list in lists) {
      if (list.isDefault) {
        return list;
      }
    }

    return lists.first;
  }

  Widget _buildFavoriteLists(
    BuildContext context,
    FavoriteModel favoriteModel,
    List<FavoriteList> lists,
    FavoriteList? selectedList,
  ) {
    final colorScheme = Theme.of(context).colorScheme;
    return Container(
      width: 260,
      color: colorScheme.surface,
      child: Column(
        children: [
          Expanded(
            child: ListView.separated(
              padding: const EdgeInsets.all(12),
              itemCount: lists.length,
              separatorBuilder: (context, index) => const SizedBox(height: 8),
              itemBuilder: (context, index) {
                final list = lists[index];
                final isSelected = selectedList?.id == list.id;
                final stationCount =
                    favoriteModel.stationsForList(list.id).length;
                return _buildFavoriteListCard(
                  context,
                  favoriteModel,
                  list,
                  stationCount,
                  isSelected,
                );
              },
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 4, 12, 14),
            child: Align(
              alignment: Alignment.center,
              child: Tooltip(
                message: AppLocalizations.of(context)!.newFavoriteList,
                child: IconButton.filledTonal(
                  onPressed: () => _createList(context, favoriteModel),
                  icon: const Icon(Icons.add),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildFavoriteListCard(
    BuildContext context,
    FavoriteModel favoriteModel,
    FavoriteList list,
    int stationCount,
    bool isSelected,
  ) {
    final colorScheme = Theme.of(context).colorScheme;
    return Card(
      margin: EdgeInsets.zero,
      elevation: isSelected ? 2 : 0,
      color:
          isSelected
              ? colorScheme.primary.withValues(alpha: 0.10)
              : colorScheme.surface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(8),
        side: BorderSide(
          color:
              isSelected
                  ? colorScheme.primary.withValues(alpha: 0.42)
                  : colorScheme.outlineVariant.withValues(alpha: 0.45),
        ),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(8),
        onSecondaryTapDown:
            (details) => _showFavoriteListMenu(
              context,
              favoriteModel,
              list,
              details.globalPosition,
            ),
        onTap: () {
          setState(() {
            _selectedListId = list.id;
          });
        },
        // onLongPress: () => _confirmDeleteList(context, favoriteModel, list),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          child: Row(
            children: [
              Icon(
                list.isDefault ? Icons.favorite : Icons.list_alt,
                color: list.isDefault ? Colors.redAccent : colorScheme.primary,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      _displayListName(context, list),
                      style: TextStyle(
                        fontWeight:
                            isSelected ? FontWeight.w700 : FontWeight.w500,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 2),
                    Text(
                      AppLocalizations.of(context)!.stationCount(stationCount),
                      style: TextStyle(
                        fontSize: 12,
                        color: colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildFavoriteListMenuItem(
    BuildContext context,
    IconData icon,
    String label,
    bool enabled,
    Color? enabledColor,
  ) {
    final color =
        enabled
            ? enabledColor ?? Theme.of(context).colorScheme.onSurface
            : Theme.of(context).disabledColor;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 18, color: color),
        const SizedBox(width: 10),
        Text(label, style: TextStyle(color: color)),
      ],
    );
  }

  Future<void> _showFavoriteListMenu(
    BuildContext context,
    FavoriteModel favoriteModel,
    FavoriteList favoriteList,
    Offset position,
  ) async {
    final overlayBox = Overlay.of(context).context.findRenderObject();
    if (overlayBox is! RenderBox) {
      return;
    }

    final canModify = !favoriteList.isDefault;
    final selectedAction = await showMenu<_FavoriteListMenuAction>(
      context: context,
      position: RelativeRect.fromRect(
        position & const Size(1, 1),
        Offset.zero & overlayBox.size,
      ),
      items: [
        PopupMenuItem<_FavoriteListMenuAction>(
          value: _FavoriteListMenuAction.rename,
          enabled: canModify,
          child: _buildFavoriteListMenuItem(
            context,
            Icons.edit_outlined,
            AppLocalizations.of(context)!.rename,
            canModify,
            null,
          ),
        ),
        PopupMenuItem<_FavoriteListMenuAction>(
          value: _FavoriteListMenuAction.delete,
          enabled: canModify,
          child: _buildFavoriteListMenuItem(
            context,
            Icons.delete_rounded,
            AppLocalizations.of(context)!.delete,
            canModify,
            Theme.of(context).colorScheme.error,
          ),
        ),
      ],
    );

    if (!mounted || !context.mounted || selectedAction == null) {
      return;
    }

    switch (selectedAction) {
      case _FavoriteListMenuAction.rename:
        await _renameList(context, favoriteModel, favoriteList);
      case _FavoriteListMenuAction.delete:
        await _confirmDeleteList(context, favoriteModel, favoriteList);
    }
  }

  Widget _buildStationPane(
    BuildContext context,
    FavoriteModel favoriteModel,
    FavoriteList? selectedList,
    List<RadioStation> stations,
  ) {
    if (selectedList == null) {
      return Center(child: Text(AppLocalizations.of(context)!.noFavoriteLists));
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 8),
          child: Row(
            children: [
              Icon(
                selectedList.isDefault ? Icons.favorite : Icons.list_alt,
                color:
                    selectedList.isDefault
                        ? Colors.redAccent
                        : Theme.of(context).colorScheme.primary,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  _displayListName(context, selectedList),
                  style: const TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              Text(
                AppLocalizations.of(context)!.stationCount(stations.length),
                style: TextStyle(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
        ),
        Expanded(
          child:
              stations.isEmpty
                  ? _buildEmptyState(context)
                  : ListView.builder(
                    padding: const EdgeInsets.fromLTRB(16, 4, 16, 16),
                    itemCount: stations.length,
                    itemBuilder: (context, index) {
                      return _buildStationCard(
                        context,
                        favoriteModel,
                        stations[index],
                      );
                    },
                  ),
        ),
      ],
    );
  }

  Widget _buildEmptyState(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            Icons.favorite_border,
            size: 56,
            color: Theme.of(context).colorScheme.outline,
          ),
          const SizedBox(height: 12),
          Text(
            AppLocalizations.of(context)!.noStationsInList,
            style: TextStyle(color: Theme.of(context).colorScheme.outline),
          ),
        ],
      ),
    );
  }

  Widget _buildStationCard(
    BuildContext context,
    FavoriteModel favoriteModel,
    RadioStation radioStation,
  ) {
    final isPlaying =
        _playerController.station?.stationuuid == radioStation.stationuuid;
    final isFavorite = favoriteModel.isInDefaultList(radioStation);
    final colorScheme = Theme.of(context).colorScheme;

    return Card(
      margin: const EdgeInsets.symmetric(vertical: 5),
      clipBehavior: Clip.antiAlias,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(8),
        side: BorderSide(
          color:
              isPlaying
                  ? Colors.green.withValues(alpha: 0.7)
                  : colorScheme.outlineVariant.withValues(alpha: 0.35),
        ),
      ),
      child: InkWell(
        onTap: () {
          _playerController.selectStation(radioStation);
        },
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Row(
            children: [
              _buildStationImage(radioStation),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      radioStation.name,
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                        color: isPlaying ? Colors.green : null,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 5),
                    Text(
                      _buildStationMeta(context, radioStation),
                      style: TextStyle(
                        fontSize: 13,
                        color: colorScheme.onSurfaceVariant,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    if (radioStation.tags.isNotEmpty)
                      Padding(
                        padding: const EdgeInsets.only(top: 5),
                        child: Text(
                          radioStation.tags,
                          style: TextStyle(
                            fontSize: 12,
                            color: colorScheme.outline,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Tooltip(
                message:
                    isFavorite
                        ? AppLocalizations.of(context)!.favorited
                        : AppLocalizations.of(context)!.addToFavorites,
                child: IconButton(
                  onPressed: () {
                    showFavoriteListPicker(context, radioStation);
                  },
                  icon: Icon(
                    isFavorite ? Icons.favorite : Icons.favorite_border,
                  ),
                  color: isFavorite ? Colors.redAccent : Colors.grey[500],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildStationImage(RadioStation station) {
    return StationFavicon(
      imageUrl: station.favicon,
      size: 44,
      fallbackIconSize: 24,
    );
  }

  String _displayListName(BuildContext context, FavoriteList list) {
    return list.isDefault
        ? AppLocalizations.of(context)!.defaultFavorites
        : list.name;
  }

  String _buildStationMeta(BuildContext context, RadioStation station) {
    final parts = <String>[
      if (station.country.isNotEmpty) station.country,
      if (station.language.isNotEmpty) station.language,
      if (station.bitrate > 0) "${station.bitrate}kbps",
      if (station.hls) "HLS",
    ];

    return parts.isEmpty
        ? AppLocalizations.of(context)!.noAdditionalInfo
        : parts.join(" / ");
  }

  Future<void> _createList(
    BuildContext context,
    FavoriteModel favoriteModel,
  ) async {
    final name = await _showListNameDialog(
      context: context,
      title: AppLocalizations.of(context)!.newFavoriteList,
      confirmText: AppLocalizations.of(context)!.create,
    );

    if (name == null || name.trim().isEmpty) {
      return;
    }

    final list = await favoriteModel.createList(name);
    if (!mounted) {
      return;
    }

    if (list != null) {
      setState(() {
        _selectedListId = list.id;
      });
    }
  }

  Future<void> _renameList(
    BuildContext context,
    FavoriteModel favoriteModel,
    FavoriteList favoriteList,
  ) async {
    if (favoriteList.isDefault) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            AppLocalizations.of(context)!.defaultListCannotBeRenamed,
          ),
        ),
      );
      return;
    }

    final name = await _showListNameDialog(
      context: context,
      title: AppLocalizations.of(context)!.renameFavoriteList,
      confirmText: AppLocalizations.of(context)!.save,
      initialName: favoriteList.name,
    );

    if (name == null || name.trim().isEmpty) {
      return;
    }

    final renamed = await favoriteModel.renameList(favoriteList, name);
    if (!mounted || !context.mounted) {
      return;
    }

    if (renamed) {
      setState(() {
        _selectedListId = favoriteList.id;
      });
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(AppLocalizations.of(context)!.renameFailedNameExists),
        ),
      );
    }
  }

  Future<String?> _showListNameDialog({
    required BuildContext context,
    required String title,
    required String confirmText,
    String initialName = "",
  }) async {
    final controller = TextEditingController(text: initialName);
    controller.selection = TextSelection(
      baseOffset: 0,
      extentOffset: controller.text.length,
    );

    final name = await showDialog<String>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          title: Text(title),
          content: TextField(
            controller: controller,
            autofocus: true,
            decoration: InputDecoration(
              labelText: AppLocalizations.of(context)!.listName,
              border: const OutlineInputBorder(),
            ),
            onSubmitted:
                (value) => Navigator.of(dialogContext).pop(value.trim()),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(),
              child: Text(AppLocalizations.of(context)!.cancel),
            ),
            FilledButton(
              onPressed:
                  () => Navigator.of(dialogContext).pop(controller.text.trim()),
              child: Text(confirmText),
            ),
          ],
        );
      },
    );
    controller.dispose();

    return name;
  }

  Future<void> _confirmDeleteList(
    BuildContext context,
    FavoriteModel favoriteModel,
    FavoriteList favoriteList,
  ) async {
    if (favoriteList.isDefault) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            AppLocalizations.of(context)!.defaultListCannotBeDeleted,
          ),
        ),
      );
      return;
    }

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          title: Text(AppLocalizations.of(context)!.deleteFavoriteList),
          content: Text(
            AppLocalizations.of(context)!.deleteFavoriteListConfirmation(
              _displayListName(context, favoriteList),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(false),
              child: Text(AppLocalizations.of(context)!.cancel),
            ),
            FilledButton(
              onPressed: () => Navigator.of(dialogContext).pop(true),
              child: Text(AppLocalizations.of(context)!.delete),
            ),
          ],
        );
      },
    );

    if (confirmed != true) {
      return;
    }

    final deleted = await favoriteModel.deleteList(favoriteList);
    if (!mounted || !context.mounted) {
      return;
    }

    if (deleted) {
      setState(() {
        _selectedListId = favoriteModel.defaultList?.id ?? 0;
      });
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            AppLocalizations.of(context)!.favoriteListCannotBeDeleted,
          ),
        ),
      );
    }
  }
}
