import 'dart:async';
import 'dart:io';
import 'dart:math';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:lib_common/log/Logger.dart';
import 'package:radio_tower/networks/NetworkLogInterceptor.dart';

import '../entity/RadioStation.dart';

typedef HostResolver = Future<List<String>> Function();
typedef StationRequestExecutor =
    Future<Response<dynamic>> Function(String url, Map<String, dynamic> data);

abstract interface class StationRemoteSource {
  Future<bool> ensureServer();

  Future<List<RadioStation>> fetchRadioStationList({
    int offset,
    int limit,
    bool reverse,
    bool hidebroken,
    String order,
  });

  Future<List<RadioStation>> fetchChangedStations({
    int offset,
    int limit,
    bool hidebroken,
  });
}

class StationNetworkException implements Exception {
  StationNetworkException(this.message, [this.cause]);

  final String message;
  final Object? cause;

  @override
  String toString() => 'StationNetworkException: $message';
}

class RadioDataFetcher implements StationRemoteSource {
  RadioDataFetcher({
    Dio? dio,
    HostResolver? hostResolver,
    StationRequestExecutor? requestExecutor,
    Random? random,
    this.maxDnsAttempts = 3,
    this.maxRequestRounds = 2,
    this.dnsTimeout = const Duration(seconds: 5),
    this.retryDelay = const Duration(milliseconds: 500),
    this.shuffleHosts = true,
  }) : _dio = dio ?? _createDio(),
       _hostResolver = hostResolver ?? _discoverHosts,
       _requestExecutor = requestExecutor,
       _random = random ?? Random() {
    if (dio == null) {
      _dio.interceptors.add(NetworkLogInterceptor());
    }
  }

  static const String _tag = 'RadioDataFetcher';
  static const String _initialHost = 'all.api.radio-browser.info';
  static const String _hostSuffix = '.radio-browser.info';
  static final RegExp _apiHostPattern = RegExp(
    r'^[a-z0-9-]+\.api\.radio-browser\.info$',
  );
  static const Map<String, String> _defaultHeaders = {
    'Accept': 'application/json',
    'User-Agent': 'radio-tower/0.1.1',
  };

  final Dio _dio;
  final HostResolver _hostResolver;
  final StationRequestExecutor? _requestExecutor;
  final Random _random;
  final int maxDnsAttempts;
  final int maxRequestRounds;
  final Duration dnsTimeout;
  final Duration retryDelay;
  final bool shuffleHosts;

  final List<String> _serverHosts = [];
  int _nextHostIndex = 0;

  bool get hasServer => _serverHosts.isNotEmpty;

  @visibleForTesting
  BaseOptions get optionsForTesting => _dio.options;

  static Dio _createDio() {
    return Dio(
      BaseOptions(
        method: 'POST',
        connectTimeout: const Duration(seconds: 10),
        sendTimeout: const Duration(seconds: 10),
        receiveTimeout: const Duration(seconds: 20),
        headers: _defaultHeaders,
      ),
    );
  }

  @override
  Future<bool> ensureServer() async {
    if (hasServer) {
      return true;
    }

    for (var attempt = 0; attempt < maxDnsAttempts; attempt++) {
      try {
        final hosts = await _hostResolver().timeout(dnsTimeout);
        final verifiedHosts =
            hosts
                .map((host) => host.trim().toLowerCase())
                .where(_isSupportedHost)
                .toSet()
                .toList();
        if (verifiedHosts.isNotEmpty) {
          if (shuffleHosts) {
            verifiedHosts.shuffle(_random);
          }
          _serverHosts
            ..clear()
            ..addAll(verifiedHosts);
          _nextHostIndex = 0;
          Logger.dLog(_tag, '可用 Radio Browser 节点：$_serverHosts');
          return true;
        }
      } catch (error, stackTrace) {
        Logger.wLog(
          _tag,
          '解析 Radio Browser 节点失败，attempt=${attempt + 1}/$maxDnsAttempts',
          error: error,
          stackTrace: stackTrace,
        );
      }

      if (attempt + 1 < maxDnsAttempts && retryDelay > Duration.zero) {
        await Future<void>.delayed(retryDelay);
      }
    }
    return false;
  }

  @override
  Future<List<RadioStation>> fetchRadioStationList({
    int offset = 0,
    int limit = 0,
    bool reverse = false,
    bool hidebroken = false,
    String order = ApiListOrder.BY_NAME,
  }) {
    return _fetchStations('stations', {
      'offset': offset,
      'limit': limit,
      'reverse': reverse,
      'hidebroken': hidebroken,
      'order': order,
    });
  }

  @override
  Future<List<RadioStation>> fetchChangedStations({
    int offset = 0,
    int limit = 0,
    bool hidebroken = false,
  }) {
    return _fetchStations('stations/lastchange', {
      'offset': offset,
      'limit': limit,
      'hidebroken': hidebroken,
    });
  }

  Future<String> clickStation(String stationUuid) async {
    final response = await _request('url/$stationUuid', const {});
    if (response.data is String) {
      return response.data as String;
    }
    throw StationNetworkException('点击电台接口返回了无效数据');
  }

  Future<List<RadioStation>> _fetchStations(
    String path,
    Map<String, dynamic> data,
  ) async {
    final response = await _request(path, data);
    final responseData = response.data;
    if (responseData is! List) {
      throw StationNetworkException('$path 接口返回了无效数据');
    }

    return responseData
        .map((item) {
          if (item is! Map) {
            throw StationNetworkException('$path 接口包含无效电台记录');
          }
          return RadioStation.fromJson(Map<String, dynamic>.from(item));
        })
        .toList(growable: false);
  }

  Future<Response<dynamic>> _request(
    String path,
    Map<String, dynamic> data,
  ) async {
    Object? lastError;
    for (var round = 0; round < maxRequestRounds; round++) {
      if (!await ensureServer()) {
        lastError = StationNetworkException('没有可用的 Radio Browser 节点');
        continue;
      }

      final attempts = _serverHosts.length;
      for (var attempt = 0; attempt < attempts; attempt++) {
        final host = _nextServerHost();
        final url = 'https://$host/json/$path';
        try {
          final response =
              _requestExecutor != null
                  ? await _requestExecutor(url, data)
                  : await _dio.post<dynamic>(url, data: data);
          if (response.statusCode == 200) {
            return response;
          }
          lastError = StateError('HTTP ${response.statusCode}');
        } catch (error, stackTrace) {
          lastError = error;
          Logger.wLog(
            _tag,
            '请求 $url 失败，尝试切换节点',
            error: error,
            stackTrace: stackTrace,
          );
        }
      }

      _serverHosts.clear();
      _nextHostIndex = 0;
    }

    throw StationNetworkException('请求 Radio Browser 接口失败', lastError);
  }

  String _nextServerHost() {
    final host = _serverHosts[_nextHostIndex % _serverHosts.length];
    _nextHostIndex = (_nextHostIndex + 1) % _serverHosts.length;
    return host;
  }

  static bool _isSupportedHost(String host) {
    return host.endsWith(_hostSuffix) && _apiHostPattern.hasMatch(host);
  }

  static Future<List<String>> _discoverHosts() async {
    final addresses = await InternetAddress.lookup(
      _initialHost,
      type: InternetAddressType.IPv4,
    );
    final hosts = await Future.wait(
      addresses.map((address) => address.reverse().then((entry) => entry.host)),
    );
    return hosts;
  }
}

class ApiListOrder {
  static const String BY_NAME = "name";

  static const String BY_STATION_COUNT = "stationcount";

  static const String BY_URL = "url";

  static const String BY_HOMEPAGE = "homepage";

  static const String BY_FAVICON = "favicon";

  static const String BY_TAGS = "tags";

  static const String BY_COUNTRY = "country";

  static const String BY_STATE = "state";

  static const String BY_LANGUAGE = "language";

  static const String BY_VOTES = "votes";

  static const String BY_CODEC = "codec";

  static const String BY_BITRATE = "bitrate";

  static const String BY_LAST_CHECK_OK = "lastcheckok";

  static const String BY_LAST_CHECK_TIME = "lastchecktime";

  static const String BY_CLICK_TIMESTAMP = "clicktimestamp";

  static const String BY_CLICK_COUNT = "clickcount";

  static const String BY_CLICK_TREND = "clicktrend";

  static const String BY_CHANGE_TIMESTAMP = "changetimestamp";

  static const String BY_RANDOM = "random";
}
