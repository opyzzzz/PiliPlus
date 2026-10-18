import 'dart:convert';
import 'dart:io';

import 'package:PiliPlus/services/logger.dart';
import 'package:catcher_2/catcher_2.dart';
import 'package:PiliPlus/utils/storage_pref.dart';

class JsonFileHandler extends ReportHandler {
  final bool enableDeviceParameters;
  final bool enableApplicationParameters;
  final bool enableStackTrace;
  final bool enableCustomParameters;
  final bool printLogs;
  final bool handleWhenRejected;

  static Future<RandomAccessFile> _future = LoggerUtils.getLogsPath()
      .then((file) => file.open(mode: FileMode.writeOnlyAppend))
      .then((raf) => raf.writeFrom(const []))
      .then(_flush);

  JsonFileHandler._({
    this.enableDeviceParameters = true,
    this.enableApplicationParameters = true,
    this.enableStackTrace = true,
    this.enableCustomParameters = true,
    this.printLogs = false,
    this.handleWhenRejected = false,
  });

  static Future<JsonFileHandler?> init({
    bool enableDeviceParameters = true,
    bool enableApplicationParameters = true,
    bool enableStackTrace = true,
    bool enableCustomParameters = true,
    bool printLogs = false,
    bool handleWhenRejected = false,
  }) async {
    try {
      await _future;
      return JsonFileHandler._(
        enableDeviceParameters: enableDeviceParameters,
        enableApplicationParameters: enableApplicationParameters,
        enableStackTrace: enableStackTrace,
        enableCustomParameters: enableCustomParameters,
        printLogs: printLogs,
        handleWhenRejected: handleWhenRejected,
      );
    } catch (e, s) {
      logger.e('Init log file', error: e, stackTrace: s);
      return null;
    }
  }

  /// Writes a lightweight diagnostic entry into Settings > Logs.
  /// Respects the app's log collection setting and never interrupts input handling.
  static Future<void> addDiagnostic(String message) async {
    if (!Pref.enableLog) return;
    try {
      final report = Report(
        '[ShortcutTrace] $message',
        null,
        DateTime.now(),
        const {},
        const {},
        const {},
        null,
      );
      final json = report.toJson(
        enableDeviceParameters: false,
        enableApplicationParameters: false,
        enableStackTrace: false,
        enableCustomParameters: false,
      );
      await add((raf) => raf.writeString('${jsonEncode(json)}\n'));
    } catch (_) {
      // Diagnostics must never interfere with key-event processing.
    }
  }

  static Future<RandomAccessFile> _flush(RandomAccessFile raf) => raf.flush();

  static Future<RandomAccessFile> add(
    Future<RandomAccessFile> Function(RandomAccessFile) onValue,
  ) {
    return _future = _future.then(onValue).then(_flush);
  }

  @override
  Future<bool> handle(Report report) async {
    try {
      await _processReport(report);
      return true;
    } catch (exc, stackTrace) {
      logger.e(
        'Write Json Exception occurred',
        error: exc,
        stackTrace: stackTrace,
      );
      return false;
    }
  }

  Future<void> _processReport(Report report) {
    if (printLogs) {
      logger.d('Writing report to file');
    }
    final json = report.toJson(
      enableDeviceParameters: enableDeviceParameters,
      enableApplicationParameters: enableApplicationParameters,
      enableStackTrace: enableStackTrace,
      enableCustomParameters: enableCustomParameters,
    );
    return add((raf) => raf.writeString('${jsonEncode(json)}\n'));
  }
}
