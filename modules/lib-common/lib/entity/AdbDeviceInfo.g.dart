// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'AdbDeviceInfo.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

AdbDeviceInfo _$AdbDeviceInfoFromJson(Map<String, dynamic> json) =>
    AdbDeviceInfo(
      json['deviceName'] as String,
      json['packageName'] as String,
      json['versionName'] as String,
      json['macAddress'] as String,
      json['foundInUdpBroadcast'] as bool,
      (json['lastFoundInUdpTimeMs'] as num).toInt(),
      json['foundInCmd'] as bool,
      (json['lastFoundInCmdTimeMs'] as num).toInt(),
      json['connectStatus'] as String,
    );

Map<String, dynamic> _$AdbDeviceInfoToJson(AdbDeviceInfo instance) =>
    <String, dynamic>{
      'deviceName': instance.deviceName,
      'packageName': instance.packageName,
      'versionName': instance.versionName,
      'macAddress': instance.macAddress,
      'foundInUdpBroadcast': instance.foundInUdpBroadcast,
      'lastFoundInUdpTimeMs': instance.lastFoundInUdpTimeMs,
      'foundInCmd': instance.foundInCmd,
      'lastFoundInCmdTimeMs': instance.lastFoundInCmdTimeMs,
      'connectStatus': instance.connectStatus,
    };
