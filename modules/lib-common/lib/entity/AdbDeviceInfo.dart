import 'package:json_annotation/json_annotation.dart';

part 'AdbDeviceInfo.g.dart';

enum DeviceConnectionStatus { disconnected, connected, offline }

@JsonSerializable()
class AdbDeviceInfo {
  String deviceName = "";
  String packageName;
  String versionName;
  String macAddress;
  bool foundInUdpBroadcast = false;
  var lastFoundInUdpTimeMs = 0;
  bool foundInCmd = false;
  var lastFoundInCmdTimeMs = 0;
  String connectStatus = "";

  AdbDeviceInfo(
    this.deviceName,
    this.packageName,
    this.versionName,
    this.macAddress,
    this.foundInUdpBroadcast,
    this.lastFoundInUdpTimeMs,
    this.foundInCmd,
    this.lastFoundInCmdTimeMs,
    this.connectStatus,
  );

  AdbDeviceInfo.opt({
    required this.deviceName,
    this.packageName = "",
    this.versionName = "",
    this.macAddress = "",
    this.foundInUdpBroadcast = false,
    this.lastFoundInUdpTimeMs = 0,
    this.foundInCmd = false,
    this.lastFoundInCmdTimeMs = 0,
    this.connectStatus = "",
  });

  DeviceConnectionStatus get connectionStatus {
    if (connectStatus == "device") {
      return DeviceConnectionStatus.connected;
    } else if (connectStatus == "offline") {
      return DeviceConnectionStatus.offline;
    }
    return DeviceConnectionStatus.disconnected;
  }

  bool get isWirelessDevice {
    return deviceName.startsWith('192.') ||
        deviceName.startsWith('172.') ||
        deviceName.startsWith('10.');
  }

  // 2. 连接生成的 fromJson
  factory AdbDeviceInfo.fromJson(Map<String, dynamic> json) =>
      _$AdbDeviceInfoFromJson(json);

  // 3. 连接生成的 toJson
  Map<String, dynamic> toJson() => _$AdbDeviceInfoToJson(this);

  @override
  int get hashCode {
    return deviceName.hashCode;
  }

  @override
  bool operator ==(Object other) {
    return (identical(this, other)) ||
        (other is AdbDeviceInfo && other.deviceName == deviceName);
  }
}
