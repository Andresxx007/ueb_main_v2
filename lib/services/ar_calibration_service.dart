// =====================================================
// 🧭 AR CALIBRATION SERVICE (RESTAURADO)
// =====================================================
import 'dart:async';
import 'package:flutter_compass/flutter_compass.dart';

class ARCalibrationService {
  StreamSubscription<CompassEvent>? _compassSubscription;
  bool _isCalibrated = false; // ✅ RESTAURADO: Falso por defecto
  
  final StreamController<bool> _calibrationController = 
      StreamController<bool>.broadcast();
  
  Stream<bool> get calibrationStream => _calibrationController.stream;
  bool get isCalibrated => _isCalibrated;

  // ✅ RESTAURADO: Monitoreo real de precisión
  void startMonitoring() {
    _compassSubscription?.cancel();
    
    _compassSubscription = FlutterCompass.events?.listen((event) {
      if (event.accuracy != null) {
        // ✅ LÓGICA REAL: Calibrado si precisión < 20 grados
        final wasCalibrated = _isCalibrated;
        _isCalibrated = event.accuracy! < 20.0;
        
        // Solo notificar si cambió el estado
        if (wasCalibrated != _isCalibrated) {
          _calibrationController.add(_isCalibrated);
          
          if (_isCalibrated) {
            print('✅ Brújula calibrada (precisión: ${event.accuracy}°)');
          } else {
            print('⚠️ Brújula requiere calibración (precisión: ${event.accuracy}°)');
          }
        }
      }
    });
  }

  void stopMonitoring() {
    _compassSubscription?.cancel();
    _compassSubscription = null;
  }

  // ✅ FORZAR CALIBRACIÓN (para testing)
  void forceCalibrated() {
    _isCalibrated = true;
    _calibrationController.add(true);
    print('🔧 Calibración forzada manualmente');
  }

  // ✅ RESETEAR CALIBRACIÓN
  void reset() {
    _isCalibrated = false;
    _calibrationController.add(false);
    print('🔄 Calibración reseteada');
  }

  void dispose() {
    stopMonitoring();
    _calibrationController.close();
  }
}