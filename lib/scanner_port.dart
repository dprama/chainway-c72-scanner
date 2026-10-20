import 'package:flutter/services.dart';

abstract interface class ScannerPort {
  Stream<Object?> get events;
  Future<T?> invoke<T>(String method, [Map<String, Object?>? arguments]);
}

class AndroidScannerPort implements ScannerPort {
  static const _methods = MethodChannel('chainway_c72/methods');
  static const _events = EventChannel('chainway_c72/events');
  @override
  Stream<Object?> get events => _events.receiveBroadcastStream();
  @override
  Future<T?> invoke<T>(String method, [Map<String, Object?>? arguments]) =>
      _methods.invokeMethod<T>(method, arguments);
}
