import 'dart:async';
import 'dart:io';
import 'dart:isolate';

import 'package:flutter/foundation.dart';

class Logger {
  static const String _defaultTag = 'App';
  static Directory? _logDirectory;
  static bool _fileLogEnabled = true;
  static Future<void> _writeQueue = Future.value();

  static bool get fileLogEnabled => _fileLogEnabled;

  static Directory get logDirectory => _logDirectory ?? _defaultLogDirectory;

  static String get currentLogFilePath {
    final now = DateTime.now();
    return '${logDirectory.path}${Platform.pathSeparator}${_formatDate(now)}.log';
  }

  static void configure({
    bool? fileLogEnabled,
    Directory? logDirectory,
    String? logDirectoryPath,
  }) {
    if (logDirectory != null) {
      _logDirectory = logDirectory;
    } else if (logDirectoryPath != null && logDirectoryPath.trim().isNotEmpty) {
      _logDirectory = Directory(logDirectoryPath);
    }

    if (fileLogEnabled != null) {
      _fileLogEnabled = fileLogEnabled;
    }
  }

  static void setFileLogEnabled(bool enabled) {
    _fileLogEnabled = enabled;
    iLog(_defaultTag, '文件日志已${enabled ? '开启' : '关闭'}');
  }

  static Future<void> flush() => _writeQueue;

  static String _buildMsg(
    _LogLevel logLevel,
    String tag,
    String msg, [
    Object? error,
    StackTrace? stackTrace,
  ]) {
    final isolateName = Isolate.current.debugName ?? 'main';
    final timeStr = _formatDateTime(DateTime.now());
    final safeTag = tag.trim().isEmpty ? _defaultTag : tag.trim();
    final buffer = StringBuffer(
      '$timeStr ${logLevel.value}/$safeTag [$isolateName]: $msg',
    );

    if (error != null) {
      buffer.write(' | error: $error');
    }

    if (stackTrace != null) {
      buffer.write('\n$stackTrace');
    }

    return buffer.toString();
  }

  static void vLog(String tag, String content) {
    _log(_LogLevel.VERBOSE, tag, content);
  }

  static void dLog(String tag, String content) {
    _log(_LogLevel.DEBUG, tag, content);
  }

  static void iLog(String tag, String content) {
    _log(_LogLevel.INFO, tag, content);
  }

  static void wLog(
    String tag,
    String content, {
    Object? error,
    StackTrace? stackTrace,
  }) {
    _log(_LogLevel.WARN, tag, content, error, stackTrace);
  }

  static void eLog(
    String tag,
    String content, {
    Object? error,
    StackTrace? stackTrace,
  }) {
    _log(_LogLevel.ERROR, tag, content, error, stackTrace);
  }

  static void assertLog(
    String tag,
    String content, {
    Object? error,
    StackTrace? stackTrace,
  }) {
    _log(_LogLevel.ASSERT, tag, content, error, stackTrace);
  }

  static void v(String tag, Object content) {
    _log(_LogLevel.VERBOSE, tag, content.toString());
  }

  static void d(String tag, Object content) {
    _log(_LogLevel.DEBUG, tag, content.toString());
  }

  static void i(String tag, Object content) {
    _log(_LogLevel.INFO, tag, content.toString());
  }

  static void w(
    String tag,
    Object content, {
    Object? error,
    StackTrace? stackTrace,
  }) {
    _log(_LogLevel.WARN, tag, content.toString(), error, stackTrace);
  }

  static void e(
    String tag,
    Object content, {
    Object? error,
    StackTrace? stackTrace,
  }) {
    _log(_LogLevel.ERROR, tag, content.toString(), error, stackTrace);
  }

  static void _log(
    _LogLevel logLevel,
    String tag,
    String content, [
    Object? error,
    StackTrace? stackTrace,
  ]) {
    final msg = _buildMsg(logLevel, tag, content, error, stackTrace);
    debugPrint(msg);

    if (_fileLogEnabled) {
      _enqueueFileLog(msg);
    }
  }

  static void _enqueueFileLog(String msg) {
    _writeQueue = _writeQueue.then((_) => _writeFileLog(msg)).catchError((
      Object error,
      StackTrace stackTrace,
    ) {
      debugPrint(
        _buildMsg(_LogLevel.ERROR, 'Logger', '写入文件日志失败', error, stackTrace),
      );
    });
  }

  static Future<void> _writeFileLog(String msg) async {
    final directory = logDirectory;
    if (!await directory.exists()) {
      await directory.create(recursive: true);
    }

    final file = File(currentLogFilePath);
    await file.writeAsString(
      '$msg${Platform.lineTerminator}',
      mode: FileMode.append,
    );
  }

  static Directory get _defaultLogDirectory {
    final executable = Platform.resolvedExecutable;
    final baseDirectory =
        executable.isEmpty ? Directory.current : File(executable).parent;
    return Directory('${baseDirectory.path}${Platform.pathSeparator}logs');
  }

  static String _formatDateTime(DateTime dateTime) {
    return '${_formatDate(dateTime)} '
        '${_twoDigits(dateTime.hour)}:${_twoDigits(dateTime.minute)}:'
        '${_twoDigits(dateTime.second)}.'
        '${dateTime.millisecond.toString().padLeft(3, '0')}';
  }

  static String _formatDate(DateTime dateTime) {
    return '${dateTime.year.toString().padLeft(4, '0')}-'
        '${_twoDigits(dateTime.month)}-${_twoDigits(dateTime.day)}';
  }

  static String _twoDigits(int value) => value.toString().padLeft(2, '0');
}

enum _LogLevel {
  VERBOSE('[V]'),
  DEBUG('[D]'),
  INFO('[I]'),
  WARN('[W]'),
  ERROR('[E]'),
  ASSERT('[A]');

  const _LogLevel(this.value);

  final String value;
}
