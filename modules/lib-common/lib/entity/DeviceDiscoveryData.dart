


class DeviceDiscoveryData {
  final String macAddress;
  final String ipAddress;
  final String packageName;
  final String versionName;

  DeviceDiscoveryData({
    required this.macAddress,
    required this.ipAddress,
    required this.packageName,
    required this.versionName,
  });

  factory DeviceDiscoveryData.fromJson(Map<String, dynamic> json) {
    return DeviceDiscoveryData(
      macAddress: json['macAddress'] as String,
      ipAddress: json['ipAddress'] as String,
      packageName: json['packageName'] as String,
      versionName: json['versionName'] as String,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'macAddress': macAddress,
      'ipAddress': ipAddress,
      'packageName': packageName,
      'versionName': versionName,
    };
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
          other is DeviceDiscoveryData &&
              runtimeType == other.runtimeType &&
              ipAddress == other.ipAddress &&
              macAddress == other.macAddress;

  @override
  int get hashCode => ipAddress.hashCode ^ macAddress.hashCode;
}
