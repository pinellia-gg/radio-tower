import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/widget_previews.dart';
import 'package:lib_common/log/Logger.dart';
import 'package:provider/provider.dart';
import 'package:radio_tower/manger/ConfigKeys.dart';
import 'package:radio_tower/manger/ConfigMgr.dart';
import 'package:radio_tower/l10n/app_localizations.dart';
import 'package:radio_tower/provider/FavoriteModel.dart';
import 'package:radio_tower/provider/PlayerController.dart';
import 'package:radio_tower/provider/StationModel.dart';
import 'package:radio_tower/repository/station_repository.dart';
import 'package:radio_tower/services/station_sync_service.dart';
import 'package:radio_tower/views/FavoriteListPickerDialog.dart';
import 'package:radio_tower/views/SearchSelectDialogWidget.dart';
import 'package:radio_tower/views/StationFavicon.dart';

import '../entity/RadioStation.dart';

typedef SearchResult = ({int code, String result});

class RadioStationsPage extends StatelessWidget {
  const RadioStationsPage({super.key});

  @override
  Widget build(BuildContext context) {
    return const _RadioStationsView();
  }
}

class _RadioStationsView extends StatefulWidget {
  const _RadioStationsView();

  @override
  State<StatefulWidget> createState() {
    return _RadioStationsViewState();
  }
}

class _RadioStationsViewState extends State<_RadioStationsView> {
  final String _tag = "RadioStationsPage";

  static const int _stationPageSize = 50;
  static const Duration _searchDebounceDuration = Duration(milliseconds: 250);
  final TextEditingController _searchController = TextEditingController();
  final ScrollController _stationListController = ScrollController();
  late final StationModel _stationModel;
  late final PlayerController _playerController;

  List<String> _countryList = [];

  List<String> _languageList = [];

  List<String> _tagList = [];

  final List<RadioStation> _stations = [];
  Timer? _searchDebounce;
  int _stationQueryVersion = 0;
  bool _isLoadingFirstPage = false;
  bool _isLoadingMoreStations = false;
  bool _hasMoreStations = true;
  bool _hideOfflineStations = true;

  void onQueryChanged(String query) {
    _updateSearchContent(query);
  }

  void _updateSearchContent(String searchKey) {
    setState(() {
      _filterName = searchKey;
    });
    _searchDebounce?.cancel();
    _searchDebounce = Timer(_searchDebounceDuration, () {
      updateStationDataView(reset: true);
    });
  }

  static const int SEARCH_TYPE_COUNTRY = 0;
  static const int SEARCH_TYPE_LANGUAGE = 1;
  static const int SEARCH_TYPE_TAG = 2;

  @override
  Widget build(BuildContext context) {
    final body = Row(
      children: [
        _buildFilterPane(context),
        const VerticalDivider(width: 1, thickness: 1),
        Expanded(child: _buildListView()),
      ],
    );

    return Scaffold(appBar: null, body: body);
  }

  Widget _buildFilterPane(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final l10n = AppLocalizations.of(context)!;
    return Container(
      width: 260,
      color: colorScheme.surface,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 18, 16, 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Text(
                  l10n.filter,
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
                ),
                const Spacer(),
                PopupMenuButton<StationSort>(
                  tooltip: l10n.sort,
                  initialValue: _stationSort,
                  onSelected: _updateStationSort,
                  itemBuilder:
                      (context) => [
                        PopupMenuItem(value: StationSort.name, child: Text(l10n.sortByName)),
                        PopupMenuItem(value: StationSort.popularity, child: Text(l10n.sortByPopularity)),
                        PopupMenuItem(value: StationSort.votes, child: Text(l10n.sortByVotes)),
                        PopupMenuItem(value: StationSort.clickTrend, child: Text(l10n.sortByClickTrend)),
                      ],
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 8),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [const Icon(Icons.sort, size: 18), const SizedBox(width: 4), Text(l10n.sort)],
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 14),
            _buildNameSearchField(),
            const SizedBox(height: 18),
            _buildFilterButton(
              context: context,
              icon: Icons.public,
              label: l10n.country,
              value: _filterCountry.isEmpty ? l10n.all : _filterCountry,
              onPressed: () => showSearchDialog(l10n.selectCountry, _countryList, SEARCH_TYPE_COUNTRY),
            ),
            const SizedBox(height: 10),
            _buildFilterButton(
              context: context,
              icon: Icons.language,
              label: l10n.language,
              value: _filterLanguage.isEmpty ? l10n.all : _filterLanguage,
              onPressed: () => showSearchDialog(l10n.selectLanguage, _languageList, SEARCH_TYPE_LANGUAGE),
            ),
            const SizedBox(height: 10),
            _buildFilterButton(
              context: context,
              icon: Icons.sell_outlined,
              label: l10n.tag,
              value: _filterTag.isEmpty ? l10n.all : _filterTag,
              onPressed: () => showSearchDialog(l10n.selectTag, _tagList, SEARCH_TYPE_TAG),
            ),
            const SizedBox(height: 12),
            Consumer<StationModel>(
              builder: (context, stationModel, child) {
                if (stationModel.isSyncing) {
                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const LinearProgressIndicator(),
                      const SizedBox(height: 6),
                      Text(l10n.updatingStationCatalog),
                    ],
                  );
                }
                if (stationModel.syncState.status == StationSyncStatus.failed) {
                  return OutlinedButton.icon(
                    onPressed: _retrySync,
                    icon: const Icon(Icons.refresh),
                    label: Text(l10n.catalogUpdateFailedRetry),
                  );
                }
                return const SizedBox.shrink();
              },
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildNameSearchField() {
    final l10n = AppLocalizations.of(context)!;
    return TextField(
      controller: _searchController,
      onChanged: onQueryChanged,
      decoration: InputDecoration(
        labelText: l10n.searchByName,
        prefixIcon: const Icon(Icons.search),
        border: const OutlineInputBorder(),
        isDense: true,
        suffixIcon:
            _filterName.isEmpty
                ? null
                : IconButton(
                  tooltip: l10n.clearSearch,
                  onPressed: () {
                    _searchController.clear();
                    _updateSearchContent("");
                  },
                  icon: const Icon(Icons.clear),
                ),
      ),
    );
  }

  Widget _buildFilterButton({
    required BuildContext context,
    required IconData icon,
    required String label,
    required String value,
    required VoidCallback onPressed,
  }) {
    final colorScheme = Theme.of(context).colorScheme;
    return SizedBox(
      height: 48,
      child: OutlinedButton(
        onPressed: onPressed,
        style: OutlinedButton.styleFrom(
          alignment: Alignment.centerLeft,
          padding: const EdgeInsets.symmetric(horizontal: 12),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
        ),
        child: Row(
          children: [
            Icon(icon, size: 20),
            const SizedBox(width: 10),
            Text(label, overflow: TextOverflow.ellipsis),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                value,
                textAlign: TextAlign.right,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(color: colorScheme.onSurfaceVariant),
              ),
            ),
            const SizedBox(width: 4),
            const Icon(Icons.arrow_drop_down, size: 20),
          ],
        ),
      ),
    );
  }

  @override
  void initState() {
    super.initState();
    Logger.dLog(_tag, "initState");
    _playerController = context.read<PlayerController>();
    _playerController.playInfoNotifier.addListener(_onPlayInfoChanged);
    _stationListController.addListener(_onStationListScrolled);
    _stationModel = context.read<StationModel>();
    _stationModel.addListener(_onStationModelChanged);
    initData();
  }

  @override
  void dispose() {
    _playerController.playInfoNotifier.removeListener(_onPlayInfoChanged);
    _stationListController.removeListener(_onStationListScrolled);
    _stationModel.removeListener(_onStationModelChanged);
    _stationListController.dispose();
    _searchDebounce?.cancel();
    _searchController.dispose();
    super.dispose();
  }

  void _onPlayInfoChanged() {
    setState(() {});
  }

  void _onStationModelChanged() {
    final hideOfflineStations = _stationModel.hideOfflineStations;
    if (_hideOfflineStations == hideOfflineStations) {
      return;
    }
    setState(() {
      _hideOfflineStations = hideOfflineStations;
    });
    unawaited(updateStationDataView(reset: true));
  }

  void _onStationListScrolled() {
    if (!_stationListController.hasClients || _isLoadingFirstPage || _isLoadingMoreStations || !_hasMoreStations) {
      return;
    }

    final position = _stationListController.position;
    if (position.pixels >= position.maxScrollExtent - 240) {
      updateStationDataView(reset: false);
    }
  }

  void initData() async {
    final stationModel = _stationModel;
    await stationModel.initialize();
    _hideOfflineStations = stationModel.hideOfflineStations;
    await initDb(stationModel);
    if (!mounted) {
      return;
    }

    String filterCountry = ConfigMgr().getStringVal(ConfigKeys.KEY_LAST_SEL_COUNTRY, "");
    String filterLanguage = ConfigMgr().getStringVal(ConfigKeys.KEY_LAST_SEL_LANG, "");
    String filterTag = ConfigMgr().getStringVal(ConfigKeys.KEY_LAST_SEL_TAG, "");
    updateFilterUi(filterCountry, filterLanguage, filterTag);
    unawaited(_syncInBackground(stationModel));
  }

  Future<void> initDb(StationModel stationModel) async {
    Logger.dLog(_tag, "start initDb");
    Logger.dLog(_tag, "finish initDb");

    _countryList = await stationModel.queryDistinctCountry();
    _languageList = await stationModel.queryDistinctLanguage();
    _tagList = await stationModel.queryDistinctTag();
  }

  Future<void> _syncInBackground(StationModel stationModel) async {
    final result = await stationModel.syncIfNeeded();
    if (!mounted || !result.isSuccess) return;
    await initDb(stationModel);
    if (!mounted) return;
    await updateStationDataView(reset: true);
  }

  Future<void> _retrySync() async {
    final stationModel = context.read<StationModel>();
    final result = await stationModel.retry();
    if (!mounted) return;
    if (result.isSuccess) {
      await initDb(stationModel);
      if (!mounted) return;
      await updateStationDataView(reset: true);
    }
  }

  void showSearchDialog(String title, List<String> arrays, int searchType) async {
    SearchResult? result = await showDialog<SearchResult>(
      context: context,
      builder: (BuildContext context) {
        return SearchSelectDialogWidget(title, ['', ...arrays], searchType);
      },
      barrierDismissible: true,
    );

    if (result != null) {
      int code = result.code;
      String searchKey = result.result;

      if (code == SEARCH_TYPE_COUNTRY) {
        updateFilterUi(searchKey, _filterLanguage, _filterTag);
        ConfigMgr().put(ConfigKeys.KEY_LAST_SEL_COUNTRY, searchKey).save();
      } else if (searchType == SEARCH_TYPE_LANGUAGE) {
        updateFilterUi(_filterCountry, searchKey, _filterTag);
        ConfigMgr().put(ConfigKeys.KEY_LAST_SEL_LANG, searchKey).save();
      } else if (searchType == SEARCH_TYPE_TAG) {
        updateFilterUi(_filterCountry, _filterLanguage, searchKey);
        ConfigMgr().put(ConfigKeys.KEY_LAST_SEL_TAG, searchKey).save();
      }
    }
  }

  void updateFilterUi(String filterCountry, String filterLang, String filterTag) {
    Logger.dLog(
      _tag,
      "updateFilterUi filterCountry:$filterCountry, "
      "filterLang:$filterLang, filterTag:$filterTag",
    );
    _filterCountry = filterCountry;
    _filterLanguage = filterLang;
    _filterTag = filterTag;
    _searchDebounce?.cancel();
    setState(() {});

    updateStationDataView(reset: true);
  }

  Widget _buildListView() {
    if (_stations.isEmpty && _isLoadingFirstPage) {
      return const Center(child: CircularProgressIndicator());
    }

    return ListView.builder(
      controller: _stationListController,
      physics: const BouncingScrollPhysics(),
      padding: const EdgeInsets.symmetric(vertical: 4, horizontal: 8),
      itemCount: _stations.length + (_isLoadingMoreStations ? 1 : 0),
      itemBuilder: (BuildContext context, int index) {
        if (index >= _stations.length) {
          return const Padding(
            padding: EdgeInsets.symmetric(vertical: 16),
            child: Center(child: CircularProgressIndicator()),
          );
        }

        final station = _stations[index];
        final isPlaying = _playerController.station?.stationuuid == station.stationuuid;

        return Card(
          margin: const EdgeInsets.symmetric(vertical: 4),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
          child: InkWell(
            borderRadius: BorderRadius.circular(8),
            onTap: () {
              Logger.dLog(_tag, "点击了${station.name}");
              _playerController.selectStation(station);
            },
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  StationFavicon(imageUrl: station.favicon, size: 40, fallbackIconSize: 24),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Expanded(
                              child: Text(
                                station.name,
                                style: TextStyle(
                                  fontSize: 16,
                                  fontWeight: FontWeight.w500,
                                  color: isPlaying ? Colors.green : null,
                                ),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                            if (station.bitrate > 0)
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                margin: const EdgeInsets.only(left: 8),
                                decoration: BoxDecoration(
                                  color: Colors.blue.withValues(alpha: 0.1),
                                  borderRadius: BorderRadius.circular(4),
                                ),
                                child: Text(
                                  '${station.bitrate}kbps',
                                  style: const TextStyle(fontSize: 12, color: Colors.blue),
                                ),
                              ),
                            if (station.hls)
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                margin: const EdgeInsets.only(left: 4),
                                decoration: BoxDecoration(
                                  color: Colors.orange.withValues(alpha: 0.1),
                                  borderRadius: BorderRadius.circular(4),
                                ),
                                child: const Text('HLS', style: TextStyle(fontSize: 12, color: Colors.orange)),
                              ),
                          ],
                        ),
                        if (station.tags.isNotEmpty)
                          Padding(
                            padding: const EdgeInsets.only(top: 6),
                            child: Text(
                              station.tags,
                              style: TextStyle(fontSize: 13, color: Colors.grey[600]),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 8),
                  Consumer<FavoriteModel>(
                    builder: (context, favoriteModel, child) {
                      final isFavorite = favoriteModel.isInDefaultList(station);
                      final l10n = AppLocalizations.of(context)!;
                      return Tooltip(
                        message: isFavorite ? l10n.favorited : l10n.addToFavorites,
                        child: IconButton(
                          onPressed: () {
                            showFavoriteListPicker(context, station);
                          },
                          icon: Icon(isFavorite ? Icons.favorite : Icons.favorite_border),
                          color: isFavorite ? Colors.redAccent : Colors.grey[500],
                        ),
                      );
                    },
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  String _filterName = "";
  String _filterCountry = "";
  String _filterLanguage = "";
  String _filterTag = "";
  StationSort _stationSort = StationSort.name;

  void _updateStationSort(StationSort stationSort) {
    if (_stationSort == stationSort) {
      return;
    }
    setState(() {
      _stationSort = stationSort;
    });
    updateStationDataView(reset: true);
  }

  Future<void> updateStationDataView({required bool reset}) async {
    final queryVersion = reset ? ++_stationQueryVersion : _stationQueryVersion;

    if (!reset && (_isLoadingFirstPage || _isLoadingMoreStations || !_hasMoreStations)) {
      return;
    }

    final offset = reset ? 0 : _stations.length;

    if (mounted) {
      setState(() {
        if (reset) {
          _isLoadingFirstPage = true;
          _isLoadingMoreStations = false;
          _hasMoreStations = true;
        } else {
          _isLoadingMoreStations = true;
        }
      });
    }

    late final List<RadioStation> stations;
    try {
      stations = await context.read<StationModel>().queryStations(
        StationQueryParams(
          filterName: _filterName,
          filterCountry: _filterCountry,
          filterLanguage: _filterLanguage,
          filterTag: _filterTag,
          hideOfflineStations: _hideOfflineStations,
          sort: _stationSort,
          offset: offset,
          limit: _stationPageSize,
        ),
      );
    } catch (error, stackTrace) {
      Logger.eLog(_tag, "查询电台失败", error: error, stackTrace: stackTrace);
      if (mounted && queryVersion == _stationQueryVersion) {
        setState(() {
          _isLoadingFirstPage = false;
          _isLoadingMoreStations = false;
        });
        showSnackBar(AppLocalizations.of(context)!.stationQueryFailed);
      }
      return;
    }

    if (!mounted || queryVersion != _stationQueryVersion) {
      return;
    }

    setState(() {
      if (reset) {
        _stations.clear();
      }
      _stations.addAll(stations);
      _hasMoreStations = stations.length == _stationPageSize;
      _isLoadingFirstPage = false;
      _isLoadingMoreStations = false;
    });
  }

  void showSnackBar(String info) {
    final snackBar = SnackBar(content: Text(info));
    ScaffoldMessenger.of(context).showSnackBar(snackBar);
  }
}
