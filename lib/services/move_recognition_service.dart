import 'dart:async';
import 'package:sensors_plus/sensors_plus.dart';
import '../models/move_event_record.dart';

/// 通过加速度计步频 + GPS 速度融合识别用户活动状态。
/// 仅在状态发生转换时 emit 一条 [MoveEventRecord]，每天约 20–100 条。
///
/// 使用 Android 内置 SensorManager（无需 Google Play Services）。
class MoveRecognitionService {
  static final MoveRecognitionService _instance = MoveRecognitionService._internal();
  factory MoveRecognitionService() => _instance;
  MoveRecognitionService._internal();

  // ── 步频检测（平方量级，避免 sqrt） ────────────────────────────────────────
  // 对应阈值：高 12.0 m/s² → 144.0，低 9.5 m/s² → 90.25
  static const double _stepThreshHigh = 144.0;
  static const double _stepThreshLow  =  90.25;
  static const int _sampleWindow = 50; // ~1s at 50 Hz

  final _magnitudeBuffer = <double>[];
  bool _aboveThreshold = false;
  int _stepCountInWindow = 0;
  int _windowStartMs = 0;
  double _currentCadence = 0; // 步/分

  // ── GPS 速度（由外部注入） ─────────────────────────────────────────────────
  double _lastGpsSpeedMs = 0;

  // ── 活动状态机 ─────────────────────────────────────────────────────────────
  String _currentMoveType = 'UNKNOWN';
  int _stillSinceMs = 0;

  // ── 流 & 订阅 ──────────────────────────────────────────────────────────────
  StreamSubscription<AccelerometerEvent>? _accelSub;
  final _moveController = StreamController<MoveEventRecord>.broadcast();

  Stream<MoveEventRecord> get moveStream => _moveController.stream;

  // ── 公共 API ───────────────────────────────────────────────────────────────

  void start() {
    _windowStartMs = DateTime.now().millisecondsSinceEpoch;
    _accelSub = accelerometerEventStream(
      samplingPeriod: const Duration(milliseconds: 20),
    ).listen(_onAccelerometer, onError: (_) {});
  }

  void stop() {
    _accelSub?.cancel();
    _accelSub = null;
  }

  /// 由 background_service.dart 的 location stream 回调调用，注入最新 GPS 速度。
  void updateGpsSpeed(double speedMs) {
    _lastGpsSpeedMs = speedMs < 0 ? 0 : speedMs;
  }

  void dispose() {
    stop();
    _moveController.close();
  }

  // ── 内部逻辑 ───────────────────────────────────────────────────────────────

  void _onAccelerometer(AccelerometerEvent event) {
    final mag = event.x * event.x + event.y * event.y + event.z * event.z;
    _magnitudeBuffer.add(mag);

    // 上升沿过阈检测步频
    if (!_aboveThreshold && mag > _stepThreshHigh) {
      _aboveThreshold = true;
      _stepCountInWindow++;
    } else if (_aboveThreshold && mag < _stepThreshLow) {
      _aboveThreshold = false;
    }

    if (_magnitudeBuffer.length >= _sampleWindow) {
      final nowMs = DateTime.now().millisecondsSinceEpoch;
      final elapsedSec = (nowMs - _windowStartMs) / 1000.0;
      _currentCadence = elapsedSec > 0 ? (_stepCountInWindow / elapsedSec) * 60 : 0;

      _magnitudeBuffer.clear();
      _stepCountInWindow = 0;
      _windowStartMs = nowMs;

      _classifyAndEmit(nowMs);
    }
  }

  void _classifyAndEmit(int nowMs) {
    final moveType = _classify();

    if (moveType == 'STILL') {
      if (_stillSinceMs == 0) _stillSinceMs = nowMs;
      // 静止状态需持续 30s 才确认，避免短暂停顿产生误报
      if (nowMs - _stillSinceMs < 30000) return;
    } else {
      _stillSinceMs = 0;
    }

    if (moveType == _currentMoveType) return; // 无状态转换，不 emit

    _currentMoveType = moveType;

    final confidence = _computeConfidence(moveType);
    final recordKey = '${moveType}_${nowMs}';

    _moveController.add(MoveEventRecord(
      recordKey: recordKey,
      moveType: moveType,
      confidence: confidence,
      occurredAtMs: nowMs,
    ));
  }

  String _classify() {
    final speed = _lastGpsSpeedMs;
    final cadence = _currentCadence;

    if (speed > 4.17) return 'IN_VEHICLE';              // > 15 km/h
    if (speed > 1.39 && cadence < 30) return 'ON_BICYCLE'; // 5–15 km/h 且无步频
    if (cadence >= 160) return 'RUNNING';
    if (cadence >= 30) return 'WALKING';
    return 'STILL';
  }

  double? _computeConfidence(String moveType) {
    switch (moveType) {
      case 'IN_VEHICLE':
        return ((_lastGpsSpeedMs - 4.17).clamp(0, 10) * 5 + 50).clamp(0, 100);
      case 'RUNNING':
        return ((_currentCadence - 160) / 40 * 50 + 50).clamp(0, 100);
      case 'WALKING':
        return ((_currentCadence - 30) / 130 * 50 + 50).clamp(0, 100);
      case 'STILL':
        return 90;
      case 'ON_BICYCLE':
        return 70;
      default:
        return null;
    }
  }
}
