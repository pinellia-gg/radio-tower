// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'RadioStation.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

RadioStation _$RadioStationFromJson(Map<String, dynamic> json) =>
    RadioStation()
      ..changeuuid = json['changeuuid'] as String
      ..stationuuid = json['stationuuid'] as String
      ..name = json['name'] as String
      ..url = json['url'] as String
      ..url_resolved = json['url_resolved'] as String
      ..homepage = json['homepage'] as String
      ..favicon = json['favicon'] as String
      ..tags = json['tags'] as String
      ..country = json['country'] as String
      ..countrycode = json['countrycode'] as String
      ..state = json['state'] as String
      ..language = json['language'] as String
      ..languagecodes = json['languagecodes'] as String
      ..votes = (json['votes'] as num).toInt()
      ..lastchangetime = JsonConverters.dateTimeFromNullableString(
        json['lastchangetime'] as String?,
      )
      ..lastchangetime_iso8601 = JsonConverters.dateTimeFromNullableString(
        json['lastchangetime_iso8601'] as String?,
      )
      ..codec = json['codec'] as String
      ..bitrate = (json['bitrate'] as num).toInt()
      ..hls = JsonConverters.boolFromInt((json['hls'] as num?)?.toInt())
      ..lastcheckok = JsonConverters.boolFromInt(
        (json['lastcheckok'] as num?)?.toInt(),
      )
      ..lastchecktime = JsonConverters.dateTimeFromNullableString(
        json['lastchecktime'] as String?,
      )
      ..lastchecktime_iso8601 = JsonConverters.dateTimeFromNullableString(
        json['lastchecktime_iso8601'] as String?,
      )
      ..lastcheckoktime = JsonConverters.dateTimeFromNullableString(
        json['lastcheckoktime'] as String?,
      )
      ..lastcheckoktime_iso8601 = JsonConverters.dateTimeFromNullableString(
        json['lastcheckoktime_iso8601'] as String?,
      )
      ..lastlocalchecktime = JsonConverters.dateTimeFromNullableString(
        json['lastlocalchecktime'] as String?,
      )
      ..lastlocalchecktime_iso8601 = JsonConverters.dateTimeFromNullableString(
        json['lastlocalchecktime_iso8601'] as String?,
      )
      ..clicktimestamp = JsonConverters.dateTimeFromNullableString(
        json['clicktimestamp'] as String?,
      )
      ..clicktimestamp_iso8601 = JsonConverters.dateTimeFromNullableString(
        json['clicktimestamp_iso8601'] as String?,
      )
      ..clickcount = (json['clickcount'] as num).toInt()
      ..clicktrend = (json['clicktrend'] as num).toInt()
      ..ssl_error = (json['ssl_error'] as num).toInt()
      ..geo_lat = (json['geo_lat'] as num?)?.toDouble()
      ..geo_long = (json['geo_long'] as num?)?.toDouble()
      ..has_extended_info = json['has_extended_info'] as bool
      ..started = json['started'] as bool? ?? false
      ..ID = (json['ID'] as num?)?.toInt() ?? 0
      ..imgLoadFailed = json['imgLoadFailed'] as bool? ?? false
      ..lastImgLoadFailedTimestamp =
          (json['lastImgLoadFailedTimestamp'] as num?)?.toInt() ?? 0;

Map<String, dynamic> _$RadioStationToJson(
  RadioStation instance,
) => <String, dynamic>{
  'changeuuid': instance.changeuuid,
  'stationuuid': instance.stationuuid,
  'name': instance.name,
  'url': instance.url,
  'url_resolved': instance.url_resolved,
  'homepage': instance.homepage,
  'favicon': instance.favicon,
  'tags': instance.tags,
  'country': instance.country,
  'countrycode': instance.countrycode,
  'state': instance.state,
  'language': instance.language,
  'languagecodes': instance.languagecodes,
  'votes': instance.votes,
  'lastchangetime': instance.lastchangetime?.toIso8601String(),
  'lastchangetime_iso8601': instance.lastchangetime_iso8601?.toIso8601String(),
  'codec': instance.codec,
  'bitrate': instance.bitrate,
  'hls': JsonConverters.boolToInt(instance.hls),
  'lastcheckok': JsonConverters.boolToInt(instance.lastcheckok),
  'lastchecktime': instance.lastchecktime?.toIso8601String(),
  'lastchecktime_iso8601': instance.lastchecktime_iso8601?.toIso8601String(),
  'lastcheckoktime': instance.lastcheckoktime?.toIso8601String(),
  'lastcheckoktime_iso8601':
      instance.lastcheckoktime_iso8601?.toIso8601String(),
  'lastlocalchecktime': instance.lastlocalchecktime?.toIso8601String(),
  'lastlocalchecktime_iso8601':
      instance.lastlocalchecktime_iso8601?.toIso8601String(),
  'clicktimestamp': instance.clicktimestamp?.toIso8601String(),
  'clicktimestamp_iso8601': instance.clicktimestamp_iso8601?.toIso8601String(),
  'clickcount': instance.clickcount,
  'clicktrend': instance.clicktrend,
  'ssl_error': instance.ssl_error,
  'geo_lat': instance.geo_lat,
  'geo_long': instance.geo_long,
  'has_extended_info': instance.has_extended_info,
  'started': instance.started,
  'ID': instance.ID,
  'imgLoadFailed': instance.imgLoadFailed,
  'lastImgLoadFailedTimestamp': instance.lastImgLoadFailedTimestamp,
};
