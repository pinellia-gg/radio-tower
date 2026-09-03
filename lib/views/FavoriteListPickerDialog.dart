import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:radio_tower/entity/FavoriteList.dart';
import 'package:radio_tower/entity/RadioStation.dart';
import 'package:radio_tower/l10n/app_localizations.dart';
import 'package:radio_tower/provider/FavoriteModel.dart';

Future<void> showFavoriteListPicker(
  BuildContext context,
  RadioStation station,
) async {
  final favoriteModel = Provider.of<FavoriteModel>(context, listen: false);
  await favoriteModel.ensureLoaded();

  if (!context.mounted || station.stationuuid.isEmpty) {
    return;
  }

  final selectedListIds = await showDialog<Set<int>>(
    context: context,
    builder: (dialogContext) {
      return FavoriteListPickerDialog(
        lists: favoriteModel.favoriteLists,
        initialSelectedListIds: favoriteModel.listIdsForStation(
          station.stationuuid,
        ),
      );
    },
  );

  if (selectedListIds != null) {
    await favoriteModel.setStationLists(station, selectedListIds);
  }
}

class FavoriteListPickerDialog extends StatefulWidget {
  final List<FavoriteList> lists;
  final Set<int> initialSelectedListIds;

  const FavoriteListPickerDialog({
    required this.lists,
    required this.initialSelectedListIds,
    super.key,
  });

  @override
  State<FavoriteListPickerDialog> createState() {
    return _FavoriteListPickerDialogState();
  }
}

class _FavoriteListPickerDialogState extends State<FavoriteListPickerDialog> {
  late final Set<int> _selectedListIds = Set.from(
    widget.initialSelectedListIds,
  );

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return AlertDialog(
      title: Text(l10n.addToFavoriteList),
      content: SizedBox(
        width: 420,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxHeight: 420),
          child: ListView.separated(
            shrinkWrap: true,
            itemCount: widget.lists.length,
            separatorBuilder: (context, index) => const Divider(height: 1),
            itemBuilder: (context, index) {
              final list = widget.lists[index];
              return CheckboxListTile(
                value: _selectedListIds.contains(list.id),
                onChanged: (checked) {
                  setState(() {
                    if (checked == true) {
                      _selectedListIds.add(list.id);
                    } else {
                      _selectedListIds.remove(list.id);
                    }
                  });
                },
                title: Text(
                  list.isDefault ? l10n.defaultFavorites : list.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                subtitle: list.isDefault ? Text(l10n.defaultList) : null,
                secondary: Icon(
                  list.isDefault ? Icons.favorite : Icons.list_alt,
                  color: list.isDefault ? Colors.redAccent : null,
                ),
                controlAffinity: ListTileControlAffinity.trailing,
              );
            },
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(l10n.cancel),
        ),
        FilledButton(
          onPressed: () => Navigator.of(context).pop(_selectedListIds),
          child: Text(l10n.save),
        ),
      ],
    );
  }
}
