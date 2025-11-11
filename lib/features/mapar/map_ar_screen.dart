import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:sliding_up_panel2/sliding_up_panel2.dart';
import 'package:geolocator/geolocator.dart';

// ✅ AR IMPORTS RESTAURADOS
import 'package:ar_flutter_plugin/ar_flutter_plugin.dart';
import 'package:ar_flutter_plugin/managers/ar_session_manager.dart';
import 'package:ar_flutter_plugin/managers/ar_object_manager.dart';
import 'package:ar_flutter_plugin/managers/ar_anchor_manager.dart';
import 'package:ar_flutter_plugin/managers/ar_location_manager.dart';
import 'package:ar_flutter_plugin/datatypes/config_planedetection.dart';
import 'package:ar_flutter_plugin/datatypes/node_types.dart';
import 'package:ar_flutter_plugin/models/ar_node.dart';
import 'package:ar_flutter_plugin/models/ar_anchor.dart';
import 'package:vector_math/vector_math_64.dart' as vector;

import '../../services/ar_anchor_config.dart';

class MapArScreen extends StatefulWidget {
  const MapArScreen({super.key});
  @override
  State<MapArScreen> createState() => _MapArScreenState();
}

class _MapArScreenState extends State<MapArScreen> {
  GoogleMapController? _gmap;
  
  // ✅ AR MANAGERS RESTAURADOS
  ARSessionManager? _arSessionManager;
  ARObjectManager? _arObjectManager;
  ARAnchorManager? _arAnchorManager;
  
  bool _isARInitialized = false;
  String? _arError;
  Position? _currentPosition;
  
  final PanelController _panel = PanelController();
  final _initialCam = const CameraPosition(
    target: LatLng(-17.7833, -63.1821),
    zoom: 17.2,
  );

  @override
  void initState() {
    super.initState();
    _getCurrentLocation();
  }

  @override
  void dispose() {
    _arSessionManager?.dispose();
    _gmap?.dispose();
    super.dispose();
  }

  // ✅ OBTENER UBICACIÓN ACTUAL
  Future<void> _getCurrentLocation() async {
    try {
      _currentPosition = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.best,
        ),
      );
      setState(() {});
    } catch (e) {
      debugPrint('❌ Error obteniendo ubicación: $e');
    }
  }

  // ✅ AR INITIALIZATION RESTAURADO
  Future<void> _onARInit(
    ARSessionManager arSessionManager,
    ARObjectManager arObjectManager,
    ARAnchorManager arAnchorManager,
    ARLocationManager arLocationManager,
  ) async {
    try {
      setState(() {
        _arSessionManager = arSessionManager;
        _arObjectManager = arObjectManager;
        _arAnchorManager = arAnchorManager;
        _arError = null;
      });

      // Configuración ARCore/ARKit
      await _arSessionManager!.onInitialize(
        showFeaturePoints: false,
        showPlanes: true,
        showWorldOrigin: false,
        handlePans: true,
        handleRotation: true,
      );
      
      await _arObjectManager!.onInitialize();

      if (mounted) {
        setState(() => _isARInitialized = true);
        
        // ✅ COLOCAR ANCLAS EN POIs REALES
        await _placeARAnchors();
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _arError = 'Error inicializando AR: $e';
          _isARInitialized = false;
        });
      }
    }
  }

  // ✅ COLOCAR ANCLAS AR EN COORDENADAS REALES
  Future<void> _placeARAnchors() async {
    if (_arAnchorManager == null || _currentPosition == null) return;

    for (final poi in ArAnchorConfig.poiAnchors) {
      try {
        // Calcular posición relativa al usuario
        final distance = Geolocator.distanceBetween(
          _currentPosition!.latitude,
          _currentPosition!.longitude,
          poi.latitude,
          poi.longitude,
        );

        final bearing = Geolocator.bearingBetween(
          _currentPosition!.latitude,
          _currentPosition!.longitude,
          poi.latitude,
          poi.longitude,
        );

        // Convertir a coordenadas AR (x, y, z)
        final radians = bearing * (3.14159 / 180);
        final x = distance * vector.sin(radians);
        final z = -distance * vector.cos(radians);
        final y = poi.altitude ?? 0.0;

        // Crear nodo AR
        final node = ARNode(
          type: NodeType.webGLB,
          uri: 'https://raw.githubusercontent.com/KhronosGroup/glTF-Sample-Models/master/2.0/DamagedHelmet/glTF/DamagedHelmet.gltf',
          scale: vector.Vector3(0.5, 0.5, 0.5),
          position: vector.Vector3(x, y, z),
          rotation: vector.Vector4(1, 0, 0, 0),
        );

        // Crear ancla
        final anchor = ARPlaneAnchor(
          transformation: vector.Matrix4.identity()
            ..setTranslation(vector.Vector3(x, y, z)),
        );

        await _arAnchorManager!.addAnchorWithWorldPose(anchor);
        await _arObjectManager!.addNode(node, planeAnchor: anchor);

        debugPrint('✅ Ancla AR colocada en: ${poi.name} ($x, $y, $z)');
      } catch (e) {
        debugPrint('❌ Error colocando ancla ${poi.name}: $e');
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SlidingUpPanel(
        controller: _panel,
        minHeight: 68,
        maxHeight: MediaQuery.of(context).size.height * 0.95,
        parallaxEnabled: true,
        parallaxOffset: 0.2,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(16)),
        body: _buildMap(),
        panelBuilder: () => _buildARPanel(),
      ),
    );
  }

  Widget _buildMap() {
    return Stack(
      children: [
        GoogleMap(
          initialCameraPosition: _initialCam,
          onMapCreated: (GoogleMapController controller) {
            _gmap = controller;
          },
          myLocationEnabled: true,
          myLocationButtonEnabled: true,
          compassEnabled: true,
          polylines: ArAnchorConfig.debugRoute,
        ),
        
        // Header información
        Positioned(
          top: 40, left: 16, right: 16,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            decoration: BoxDecoration(
              color: Colors.red.shade700,
              borderRadius: BorderRadius.circular(12),
            ),
            child: const Text(
              'Hacia Laboratorios de Tecnología',
              style: TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ),
        
        // Botón abrir AR
        Positioned(
          right: 16, bottom: 90,
          child: FloatingActionButton.extended(
            backgroundColor: Colors.red,
            onPressed: () => _panel.open(),
            label: const Text('ABRIR CÁMARA AR'),
          ),
        ),
      ],
    );
  }

  Widget _buildARPanel() {
    return SafeArea(
      child: Column(
        children: [
          const SizedBox(height: 8),
          Container(
            width: 40,
            height: 5,
            decoration: BoxDecoration(
              color: Colors.black26,
              borderRadius: BorderRadius.circular(4),
            ),
          ),
          const SizedBox(height: 8),
          
          // Header panel
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Padding(
                padding: EdgeInsets.symmetric(horizontal: 16),
                child: Text(
                  'Vista AR • Laboratorios',
                  style: TextStyle(fontWeight: FontWeight.w600),
                ),
              ),
              TextButton(
                onPressed: () => _panel.close(),
                child: const Text('CERRAR'),
              ),
            ],
          ),
          const Divider(height: 1),
          
          // ✅ AR VIEW REAL
          Expanded(
            child: _isARInitialized
                ? _buildARView()
                : _buildARLoading(),
          ),
        ],
      ),
    );
  }

  // ✅ AR VIEW RESTAURADO
  Widget _buildARView() {
    return Stack(
      children: [
        ARView(
          onARViewCreated: _onARInit,
          planeDetectionConfig: PlaneDetectionConfig.horizontalAndVertical,
        ),
        
        // Error overlay
        if (_arError != null)
          Positioned.fill(
            child: Container(
              color: Colors.black54,
              child: Center(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Text(
                    _arError!,
                    style: const TextStyle(color: Colors.white),
                    textAlign: TextAlign.center,
                  ),
                ),
              ),
            ),
          ),
        
        // Instrucciones
        Positioned(
          top: 20,
          left: 20,
          right: 20,
          child: Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Colors.black.withOpacity(0.7),
              borderRadius: BorderRadius.circular(12),
            ),
            child: const Text(
              '📍 Mueve la cámara para ver objetos AR en ubicaciones reales',
              style: TextStyle(
                color: Colors.white,
                fontSize: 14,
              ),
              textAlign: TextAlign.center,
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildARLoading() {
    return const Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          CircularProgressIndicator(color: Colors.red),
          SizedBox(height: 16),
          Text('Inicializando AR...'),
          SizedBox(height: 8),
          Text(
            'Permite acceso a la cámara si se solicita',
            style: TextStyle(fontSize: 12, color: Colors.grey),
          ),
        ],
      ),
    );
  }
}
