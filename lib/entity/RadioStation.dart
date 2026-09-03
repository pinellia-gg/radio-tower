import 'dart:core';

import 'package:json_annotation/json_annotation.dart';
import 'package:objectbox/objectbox.dart';

import '../utils/JsonCoverters.dart';

part 'RadioStation.g.dart'; // You need this line

@JsonSerializable()
@Entity()
class RadioStation {
  String changeuuid = "";
  @Index()
  String stationuuid = "";
  @Index()
  String name = "";
  String url = "";
  String url_resolved = "";
  String homepage = "";
  String favicon = "";
  @Index()
  String tags = "";
  @Index()
  String country = "";
  @Index()
  String countrycode = "";
  String state = "";
  @Index()
  String language = "";
  String languagecodes = "";
  int votes = 0;
  @JsonKey(
    defaultValue: null,
    fromJson: JsonConverters.dateTimeFromNullableString,
  )
  DateTime? lastchangetime;
  @JsonKey(
    defaultValue: null,
    fromJson: JsonConverters.dateTimeFromNullableString,
  )
  DateTime? lastchangetime_iso8601;
  String codec = "";
  int bitrate = 0;
  @JsonKey(
    name: "hls",
    fromJson: JsonConverters.boolFromInt,
    toJson: JsonConverters.boolToInt,
  )
  bool hls = false;
  @JsonKey(
    name: "lastcheckok",
    fromJson: JsonConverters.boolFromInt,
    toJson: JsonConverters.boolToInt,
  )
  bool lastcheckok = false;
  @JsonKey(
    defaultValue: null,
    fromJson: JsonConverters.dateTimeFromNullableString,
  )
  DateTime? lastchecktime;
  @JsonKey(
    defaultValue: null,
    fromJson: JsonConverters.dateTimeFromNullableString,
  )
  DateTime? lastchecktime_iso8601;
  @JsonKey(
    defaultValue: null,
    fromJson: JsonConverters.dateTimeFromNullableString,
  )
  DateTime? lastcheckoktime;
  @JsonKey(
    defaultValue: null,
    fromJson: JsonConverters.dateTimeFromNullableString,
  )
  DateTime? lastcheckoktime_iso8601;
  @JsonKey(
    defaultValue: null,
    fromJson: JsonConverters.dateTimeFromNullableString,
  )
  DateTime? lastlocalchecktime;
  @JsonKey(
    defaultValue: null,
    fromJson: JsonConverters.dateTimeFromNullableString,
  )
  DateTime? lastlocalchecktime_iso8601;
  @JsonKey(
    defaultValue: null,
    fromJson: JsonConverters.dateTimeFromNullableString,
  )
  DateTime? clicktimestamp;
  @JsonKey(
    defaultValue: null,
    fromJson: JsonConverters.dateTimeFromNullableString,
  )
  DateTime? clicktimestamp_iso8601;
  int clickcount = 0;
  int clicktrend = 0;
  int ssl_error = 0;
  double? geo_lat = 0.0;
  double? geo_long = 0.0;
  bool has_extended_info = false;
  @Deprecated("可能造成与收藏夹数据不一致，应停用")
  @JsonKey(name: "started", defaultValue: false)
  bool started = false;
  @JsonKey(name: "ID", defaultValue: 0)
  @Id()
  int ID = 0;
  @Index()
  @JsonKey(includeFromJson: false, includeToJson: false)
  bool isActive = true;
  @Index()
  @JsonKey(includeFromJson: false, includeToJson: false)
  int lastSeenFullSyncGeneration = 0;
  @JsonKey(includeFromJson: false, includeToJson: false)
  bool syncStateInitialized = true;
  @JsonKey(defaultValue: false)
  @Transient()
  bool imgLoadFailed = false;
  @JsonKey(defaultValue: 0)
  @Transient()
  int lastImgLoadFailedTimestamp = 0;

  //constructor
  RadioStation();

  // Factory constructor that uses the generated `_$RadioStationFromJson`
  factory RadioStation.fromJson(Map<String, dynamic> json) =>
      _$RadioStationFromJson(json);

  // Method that uses the generated `_$RadioStationToJson`
  Map<String, dynamic> toJson() => _$RadioStationToJson(this);
}
