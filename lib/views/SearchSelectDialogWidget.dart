import 'package:flutter/material.dart';
import 'package:radio_tower/l10n/app_localizations.dart';

class SearchSelectDialogWidget extends StatefulWidget {
  final String _title;
  final List<String> _data;
  final int _requestCode;

  const SearchSelectDialogWidget(
    this._title,
    this._data,
    this._requestCode, {
    super.key,
  });

  @override
  State<StatefulWidget> createState() {
    return SearchSelectDialogWidgetState();
  }
}

class SearchSelectDialogWidgetState extends State<SearchSelectDialogWidget> {
  String _title = "";
  List<String> _rawdata = [];
  int _requestCode = 0;
  List<String> _filteredData = [];

  final TextEditingController _searchDialogEditController =
      TextEditingController();

  FocusNode focusNode = FocusNode();

  SearchSelectDialogWidgetState();

  @override
  void initState() {
    super.initState();

    _title = widget._title;
    _rawdata = widget._data;
    _requestCode = widget._requestCode;

    for (String item in _rawdata) {
      _filteredData.add(item);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    Dialog dialog = Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20.0)),
      elevation: 8.0,
      child: buildDialogContent(_title, _filteredData, l10n),
    );

    return dialog;
  }

  Widget buildDialogContent(
    String title,
    List<String> arrays,
    AppLocalizations l10n,
  ) {
    Text tipText = Text(title);

    Row firstRow = Row(
      children: [
        Expanded(
          child: TextField(
            maxLines: 1,
            controller: _searchDialogEditController,
            focusNode: focusNode,
            style: TextStyle(color: Color.fromARGB(255, 0, 0, 0)),
            cursorColor: Color.fromARGB(255, 0, 0, 0),
            decoration: InputDecoration(
              hintText: title,
              contentPadding: EdgeInsets.symmetric(
                horizontal: 8.0,
                vertical: 12.0,
              ), // Adjust padding
            ),
            onChanged: (value) {
              List<String> newFilterData = [];
              for (String item in _rawdata) {
                if (_displayValue(
                  item,
                  l10n,
                ).toLowerCase().contains(value.toLowerCase())) {
                  newFilterData.add(item);
                }
              }

              setState(() {
                _filteredData = newFilterData;
              });
            },
          ),
        ),
        TextButton(
          onPressed: () {
            String searchKey = _searchDialogEditController.text;
            if (searchKey == l10n.all) {
              searchKey = '';
            }
            if (_rawdata.contains(searchKey)) {
              Navigator.of(
                context,
              ).pop((code: _requestCode, result: searchKey));
            } else {
              showSnackBar(l10n.invalidSelection);
            }
          },
          child: Text(l10n.confirm),
          // child: Text(btnText),
        ),
      ],
    );

    var content = Container(
      padding: EdgeInsetsGeometry.all(20),
      width: 500,
      child: Column(
        children: [
          tipText,
          firstRow,
          Expanded(
            child: ListView.separated(
              itemCount: arrays.length,
              itemBuilder: (BuildContext context, int index) {
                return Container(
                  alignment: Alignment.centerLeft,
                  padding: EdgeInsetsGeometry.only(
                    left: 8,
                    right: 8,
                    top: 10,
                    bottom: 10,
                  ),
                  child: TextButton(
                    style: TextButton.styleFrom(
                      padding: EdgeInsets.zero,
                      minimumSize: Size(0, 0),
                      alignment: Alignment.centerLeft,
                    ),
                    onPressed: () {
                      _searchDialogEditController.text = _displayValue(
                        arrays[index],
                        l10n,
                      );
                    },
                    child: Text(_displayValue(arrays[index], l10n)),
                  ),
                );
              },
              separatorBuilder: (BuildContext context, int index) {
                return Divider(
                  color: Colors.grey,
                  height: 1,
                  thickness: 1,
                  indent: 8,
                  endIndent: 8,
                );
              },
            ),
          ),
        ],
      ),
    );

    return content;
  }

  void showSnackBar(String info) {
    final snackBar = SnackBar(content: Text(info));
    ScaffoldMessenger.of(context).showSnackBar(snackBar);
  }

  String _displayValue(String value, AppLocalizations l10n) {
    return value.isEmpty ? l10n.all : value;
  }
}
