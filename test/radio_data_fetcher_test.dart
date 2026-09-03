import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:radio_tower/networks/RadioDataFetcher.dart';

void main() {
  test('stops after the configured number of empty DNS results', () async {
    var resolverCalls = 0;
    final fetcher = RadioDataFetcher(
      hostResolver: () async {
        resolverCalls++;
        return [];
      },
      maxDnsAttempts: 2,
      retryDelay: Duration.zero,
    );

    expect(await fetcher.ensureServer(), isFalse);
    expect(resolverCalls, 2);
  });

  test('bounds a hanging DNS lookup', () async {
    final resolverGate = Completer<List<String>>();
    final fetcher = RadioDataFetcher(
      hostResolver: () => resolverGate.future,
      maxDnsAttempts: 1,
      dnsTimeout: Duration.zero,
    );

    expect(await fetcher.ensureServer(), isFalse);
  });

  test('configures connection, send, and receive timeouts', () {
    final options = RadioDataFetcher().optionsForTesting;

    expect(options.connectTimeout, const Duration(seconds: 10));
    expect(options.sendTimeout, const Duration(seconds: 10));
    expect(options.receiveTimeout, const Duration(seconds: 20));
  });

  test('rejects lookalike hosts and rotates to a healthy API host', () async {
    final requestedUrls = <String>[];
    final fetcher = RadioDataFetcher(
      hostResolver:
          () async => [
            'evilradio-browser.info',
            'evil.example?.api.radio-browser.info',
            'first.api.radio-browser.info',
            'second.api.radio-browser.info',
          ],
      requestExecutor: (url, data) async {
        requestedUrls.add(url);
        if (url.contains('first.api')) {
          throw DioException(
            requestOptions: RequestOptions(path: url),
            type: DioExceptionType.connectionError,
          );
        }
        return Response<dynamic>(
          requestOptions: RequestOptions(path: url),
          statusCode: 200,
          data: const [],
        );
      },
      shuffleHosts: false,
    );

    expect(await fetcher.fetchRadioStationList(limit: 1), isEmpty);
    expect(requestedUrls, hasLength(2));
    expect(requestedUrls.first, contains('first.api.radio-browser.info'));
    expect(requestedUrls.last, contains('second.api.radio-browser.info'));
    expect(requestedUrls.join(), isNot(contains('evilradio-browser.info')));
    expect(
      requestedUrls.join(),
      isNot(contains('evil.example?.api.radio-browser.info')),
    );
  });

  test(
    're-resolves a bounded number of times before reporting failure',
    () async {
      var resolverCalls = 0;
      var requestCalls = 0;
      final fetcher = RadioDataFetcher(
        hostResolver: () async {
          resolverCalls++;
          return [
            'first.api.radio-browser.info',
            'second.api.radio-browser.info',
          ];
        },
        requestExecutor: (url, data) async {
          requestCalls++;
          return Response<dynamic>(
            requestOptions: RequestOptions(path: url),
            statusCode: 503,
          );
        },
        maxRequestRounds: 2,
        shuffleHosts: false,
      );

      await expectLater(
        fetcher.fetchRadioStationList(limit: 1),
        throwsA(isA<StationNetworkException>()),
      );
      expect(resolverCalls, 2);
      expect(requestCalls, 4);
    },
  );
}
