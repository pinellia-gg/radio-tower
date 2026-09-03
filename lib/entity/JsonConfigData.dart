import 'package:json_annotation/json_annotation.dart';

part 'JsonConfigData.g.dart';

@JsonSerializable()
class JsonConfigData {
  int lastUpdateTime = 0;

  JsonConfigData();

  factory JsonConfigData.fromJson(Map<String, dynamic> json) =>
      _$JsonConfigDataFromJson(json);

  Map<String, dynamic> toJson() => _$JsonConfigDataToJson(this);
}
