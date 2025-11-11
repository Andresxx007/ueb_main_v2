import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart' as gl;
import 'package:mapbox_maps_flutter/mapbox_maps_flutter.dart' as mp;

import '../pages/lugares_ueb.dart'; // lugaresUeb + (opcional) nodosUeb, conexionesUeb

class IndoorNavigationPage extends StatefulWidget {
  const IndoorNavigationPage({super.key});

  @override
  State<IndoorNavigationPage> createState() => _IndoorNavigationPageState();
}

class _IndoorNavigationPageState extends State<IndoorNavigationPage> {
  mp.MapboxMap? _map;
  mp.PolylineAnnotationManager? _polyMgr;
  mp.PolylineAnnotation? _route;

  // selección de usuario
  String? _origenNombre;
  String? _destinoNombre;

  // datos en vivo
  gl.Position? _pos;
  StreamSubscription<gl.Position>? _posStream;

  // ruta actual en coords (lon,lat) para poder recortarla
  List<mp.Position> _rutaCoords = [];

  bool _loading = false;
  bool _followUser = true;

  mp.PointAnnotationManager? _pinManager;
  mp.PointAnnotation? _pinA;
  mp.PointAnnotation? _pinB;

  @override
  void initState() {
    super.initState();
    _startPositionStream();
  }

  @override
  void dispose() {
    _posStream?.cancel();
    super.dispose();
  }

  // ===========================
  // UI
  // ===========================
  @override
  Widget build(BuildContext context) {
    final nombres = (lugaresUeb.map((e) => e['nombre'] as String).toList()
      ..sort());

    return Scaffold(
      appBar: AppBar(
        title: const Text('Navegación interna UEB'),
        backgroundColor: Colors.redAccent,
        foregroundColor: Colors.white,
      ),
      body: Stack(
        children: [
          mp.MapWidget(
            onMapCreated: _onMapCreated,
            styleUri: mp.MapboxStyles.MAPBOX_STREETS,
          ),

          // Panel rojo superior con selección y acciones
          SafeArea(
            child: Container(
              margin: const EdgeInsets.all(12),
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.redAccent,
                borderRadius: BorderRadius.circular(14),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.25),
                    offset: const Offset(0, 3),
                    blurRadius: 8,
                  ),
                ],
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // Origen
                  Row(
                    children: [
                      const Icon(Icons.my_location, color: Colors.white),
                      const SizedBox(width: 8),
                      Expanded(
                        child: DropdownButtonFormField<String>(
                          initialValue: _origenNombre,
                          isExpanded: true,
                          dropdownColor: Colors.white,
                          decoration: _inpDecoration('Estoy en...'),
                          items: nombres
                              .map((n) => DropdownMenuItem(value: n, child: Text(n)))
                              .toList(),
                          onChanged: (v) => setState(() => _origenNombre = v),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),

                  // Destino
                  Row(
                    children: [
                      const Icon(Icons.flag, color: Colors.white),
                      const SizedBox(width: 8),
                      Expanded(
                        child: DropdownButtonFormField<String>(
                          initialValue: _destinoNombre,
                          isExpanded: true,
                          dropdownColor: Colors.white,
                          decoration: _inpDecoration('Quiero ir a...'),
                          items: nombres
                              .map((n) => DropdownMenuItem(value: n, child: Text(n)))
                              .toList(),
                          onChanged: (v) => setState(() => _destinoNombre = v),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),

                  // Botones
                  Row(
                    children: [
                      Expanded(
                        child: ElevatedButton.icon(
                          onPressed: _loading ? null : _trazarRuta,
                          icon: const Icon(Icons.alt_route),
                          label: const Text('Iniciar recorrido'),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.white,
                            foregroundColor: Colors.redAccent,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(10),
                            ),
                            padding: const EdgeInsets.symmetric(vertical: 12),
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      IconButton.filled(
                        onPressed: _loading ? null : _limpiarRuta,
                        style: IconButton.styleFrom(
                          backgroundColor: Colors.white.withValues(alpha: 0.9),
                          foregroundColor: Colors.redAccent,
                        ),
                        icon: const Icon(Icons.delete_outline),
                        tooltip: 'Limpiar ruta',
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),

          if (_loading)
            const Center(child: CircularProgressIndicator(color: Colors.redAccent)),
        ],
      ),
    );
  }

  InputDecoration _inpDecoration(String hint) => InputDecoration(
        hintText: hint,
        filled: true,
        fillColor: Colors.white,
        contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: BorderSide.none,
        ),
      );

  // ===========================
  // MAPA + POSICIÓN
  // ===========================
  Future<void> _onMapCreated(mp.MapboxMap map) async {
    _map = map;

    await _map!.location.updateSettings(
      mp.LocationComponentSettings(
        enabled: true,
        pulsingEnabled: true,
        showAccuracyRing: false,
      ),
    );

    await _map!.gestures.updateSettings(
      mp.GesturesSettings(
        pinchToZoomEnabled: true,
        rotateEnabled: true,
        pitchEnabled: true,
        scrollEnabled: true,
      ),
    );

    _polyMgr = await _map!.annotations.createPolylineAnnotationManager();
    _pinManager = await _map!.annotations.createPointAnnotationManager();

    // centra donde estés, o al centro del campus
    try {
      _pos ??= await gl.Geolocator.getCurrentPosition(
       locationSettings: const gl.LocationSettings(accuracy: gl.LocationAccuracy.best),
      );
    } catch (_) {}

    final lat = _pos?.latitude ?? -17.8355;
    final lon = _pos?.longitude ?? -63.2046;

    await _map!.flyTo(
      mp.CameraOptions(
        center: mp.Point(coordinates: mp.Position(lon, lat)),
        zoom: 18.5, // indoor
        pitch: 0,
        bearing: 0,
      ),
      mp.MapAnimationOptions(duration: 800),
    );
  }

  // ===========================
  // POSICIÓN EN TIEMPO REAL
  // ===========================
  Future<void> _startPositionStream() async {
    await _ensureLocationPermission();
    await _posStream?.cancel();

    const settings = gl.LocationSettings(
      accuracy: gl.LocationAccuracy.best,
      distanceFilter: 2, // indoor = más sensible
    );

    _posStream = gl.Geolocator.getPositionStream(locationSettings: settings)
        .listen((gl.Position p) async {
      _pos = p;

      // seguir usuario si está activo
      if (_followUser && _map != null) {
        try {
          await _map!.easeTo(
            mp.CameraOptions(
              center: mp.Point(coordinates: mp.Position(p.longitude, p.latitude)),
              zoom: 18.6,
            ),
            mp.MapAnimationOptions(duration: 300),
          );
        } catch (_) {}
      }

      // recorte visual de la línea (se acorta mientras caminas)
      await _recortarRutaConPosicionActual();
    });
  }

  Future<void> _ensureLocationPermission() async {
    final enabled = await gl.Geolocator.isLocationServiceEnabled();
    if (!enabled) return;
    var perm = await gl.Geolocator.checkPermission();
    if (perm == gl.LocationPermission.denied) {
      await gl.Geolocator.requestPermission();
    }
  }

  // ===========================
  // RUTA: cálculo + pintado + pines + ajuste de cámara
  // ===========================
  Future<void> _trazarRuta() async {
    if (_origenNombre == null || _destinoNombre == null) {
      _snack('Elegí origen y destino.');
      return;
    }
    if (_origenNombre == _destinoNombre) {
      _snack('Origen y destino no pueden ser iguales.');
      return;
    }
    setState(() => _loading = true);

    try {
      final origen = lugaresUeb.firstWhere((e) => e['nombre'] == _origenNombre);
      final destino = lugaresUeb.firstWhere((e) => e['nombre'] == _destinoNombre);

      final oLat = (origen['lat'] as num).toDouble();
      final oLon = (origen['lon'] as num).toDouble();
      final dLat = (destino['lat'] as num).toDouble();
      final dLon = (destino['lon'] as num).toDouble();

      // Pines A y B
      await _mostrarPines(oLat, oLon, dLat, dLon);

      // Si definiste nodosUeb + conexionesUeb en lugares_ueb.dart, usa Dijkstra.
      // Si no, dibuja línea directa A->B (fallback).
      List<mp.Position> coords;

      final hasGraph = (typeofNodos() && typeofConexiones());
      if (hasGraph) {
        final mapNodos = {for (var n in nodosUeb) n['id'] as String: n};
        final graph = <String, List<_Edge>>{};
        for (final c in conexionesUeb) {
          final a = c[0], b = c[1];
          final aNode = mapNodos[a]!, bNode = mapNodos[b]!;
          final w = _dist(aNode['lat'], aNode['lon'], bNode['lat'], bNode['lon']);
          graph.putIfAbsent(a, () => []).add(_Edge(b, w));
          graph.putIfAbsent(b, () => []).add(_Edge(a, w));
        }
        final oNearest = _nearestNodeId(oLat, oLon, mapNodos);
        final dNearest = _nearestNodeId(dLat, dLon, mapNodos);
        final rutaNodoIds = _dijkstra(graph, oNearest, dNearest);

        coords = [
          mp.Position(oLon, oLat),
          ...rutaNodoIds.map((nid) {
            final n = mapNodos[nid]!;
            return mp.Position((n['lon'] as num).toDouble(), (n['lat'] as num).toDouble());
          }),
          mp.Position(dLon, dLat),
        ];
      } else {
        coords = [mp.Position(oLon, oLat), mp.Position(dLon, dLat)];
      }

      // pintar polyline
      await _polyMgr?.deleteAll();
      _route = await _polyMgr!.create(
        mp.PolylineAnnotationOptions(
          geometry: mp.LineString(coordinates: coords),
          lineWidth: 6,
          lineColor: 0xFFFF3B30, // rojo fuerte
        ),
      );
      _rutaCoords = coords;

      // AJUSTAR CÁMARA A TODA LA RUTA (auto-centrado real)
      await _fitCameraToPositions(coords, padding: 80);

      _followUser = true; // que empiece siguiendo al usuario
      _snack('Ruta lista. ¡A caminar! 🔴');
    } catch (e) {
      _snack('Error al trazar ruta: $e');
    } finally {
      setState(() => _loading = false);
    }
  }

  Future<void> _mostrarPines(double oLat, double oLon, double dLat, double dLon) async {
    await _pinManager?.deleteAll();

    final bytes = await DefaultAssetBundle.of(context)
        .load('assets/icons/punto_mapa_rojo_f.png');
    final data = bytes.buffer.asUint8List();

    _pinA = await _pinManager!.create(
      mp.PointAnnotationOptions(
        geometry: mp.Point(coordinates: mp.Position(oLon, oLat)),
        image: data,
        iconSize: 0.35,
        textField: "A",
        textHaloColor: Colors.black.value,
        textHaloBlur: 0.5,
        textHaloWidth: 0.8,
        textSize: 16,
        textColor: Colors.white.value,
      ),
    );

    _pinB = await _pinManager!.create(
      mp.PointAnnotationOptions(
        geometry: mp.Point(coordinates: mp.Position(dLon, dLat)),
        image: data,
        iconSize: 0.35,
        textField: "B",
        textHaloColor: Colors.black.value,
        textHaloBlur: 0.5,
        textHaloWidth: 0.8,
        textSize: 16,
        textColor: Colors.white.value,
      ),
    );
  }

  Future<void> _limpiarRuta() async {
    await _polyMgr?.deleteAll();
    await _pinManager?.deleteAll();
    _route = null;
    _rutaCoords.clear();
    _followUser = false;
    _snack('Ruta eliminada.');
  }

  // ===========================
  // RECORTAR LÍNEA SEGÚN POSICIÓN
  // ===========================
  Future<void> _recortarRutaConPosicionActual() async {
    if (_pos == null || _rutaCoords.length < 2 || _route == null) return;

    // si ya estás muy cerca del destino, finaliza
    final last = _rutaCoords.last;
    final distFin = _dist(_pos!.latitude, _pos!.longitude, last.lat.toDouble(), last.lng.toDouble());
    if (distFin < 5) {
      await _limpiarRuta();
      _snack('🎯 Llegaste al destino');
      return;
    }

    // reemplaza el primer punto por tu posición actual para que la línea se acorte
    _rutaCoords[0] = mp.Position(_pos!.longitude, _pos!.latitude);

    // elimina vértices "consumidos"
    while (_rutaCoords.length > 2) {
      final next = _rutaCoords[1];
      final dNext = _dist(_pos!.latitude, _pos!.longitude, next.lat.toDouble(), next.lng.toDouble());
      if (dNext < 3) {
        _rutaCoords.removeAt(0);
      } else {
        break;
      }
    }

    // actualizar polyline
    await _polyMgr?.update(_route!..geometry = mp.LineString(coordinates: _rutaCoords));
  }

  // ===========================
  // AJUSTE DE CÁMARA A BOUNDS
  // ===========================
  Future<void> _fitCameraToPositions(List<mp.Position> coords, {double padding = 60}) async {
    if (_map == null || coords.isEmpty) return;

    // bounds
    double minLat = coords.first.lat.toDouble();
    double maxLat = coords.first.lat.toDouble();
    double minLon = coords.first.lng.toDouble();
    double maxLon = coords.first.lng.toDouble();

    for (final p in coords) {
      final lat = p.lat.toDouble();
      final lon = p.lng.toDouble();
      if (lat < minLat) minLat = lat;
      if (lat > maxLat) maxLat = lat;
      if (lon < minLon) minLon = lon;
      if (lon > maxLon) maxLon = lon;
    }

    final centerLat = (minLat + maxLat) / 2;
    final centerLon = (minLon + maxLon) / 2;

    // zoom heurístico según la extensión del recorrido
    final latSpan = (maxLat - minLat).abs();
    final lonSpan = (maxLon - minLon).abs();
    final span = math.max(latSpan, lonSpan);

    double zoom;
    if (span < 0.00025) {
      zoom = 19.2;
    } else if (span < 0.0006) {
      zoom = 18.8;
    } else if (span < 0.0012) {
      zoom = 18.2;
    } else {
      zoom = 17.5;
    }

    await _map!.flyTo(
  mp.CameraOptions(
    center: mp.Point(coordinates: mp.Position(centerLon, centerLat)),
    zoom: zoom,
    pitch: 0,
    bearing: 0,
    padding: mp.MbxEdgeInsets(
      top: padding,
      left: padding,
      bottom: padding,
      right: padding,
    ),
  ),
  mp.MapAnimationOptions(duration: 700),
);

  }

  // ===========================
  // UTIL: Dijkstra + distancias
  // ===========================
  bool typeofNodos() {
    try {
      // si no están definidos, esto tira
      final _ = nodosUeb;
      return true;
    } catch (_) {
      return false;
    }
  }

  bool typeofConexiones() {
    try {
      final _ = conexionesUeb;
      return true;
    } catch (_) {
      return false;
    }
  }

  String _nearestNodeId(double lat, double lon, Map<String, dynamic> mapNodos) {
    String? bestId;
    double best = double.infinity;
    mapNodos.forEach((id, n) {
      final d = _dist(
        lat,
        lon,
        (n['lat'] as num).toDouble(),
        (n['lon'] as num).toDouble(),
      );
      if (d < best) {
        best = d;
        bestId = id;
      }
    });
    return bestId!;
  }

  // distancia en metros (Haversine)
  double _dist(double lat1, double lon1, double lat2, double lon2) {
    const R = 6371000.0;
    final dLat = _deg2rad(lat2 - lat1);
    final dLon = _deg2rad(lon2 - lon1);
    final a = math.sin(dLat / 2) * math.sin(dLat / 2) +
        math.cos(_deg2rad(lat1)) *
            math.cos(_deg2rad(lat2)) *
            math.sin(dLon / 2) *
            math.sin(dLon / 2);
    final c = 2 * math.atan2(math.sqrt(a), math.sqrt(1 - a));
    return R * c;
  }

  double _deg2rad(double d) => d * math.pi / 180.0;

  List<String> _dijkstra(Map<String, List<_Edge>> g, String start, String goal) {
    final dist = <String, double>{};
    final prev = <String, String?>{};
    final unvisited = <String>{};

    // init
    for (final n in g.keys) {
      dist[n] = double.infinity;
      prev[n] = null;
      unvisited.add(n);
    }
    dist[start] = 0;

    while (unvisited.isNotEmpty) {
      // nodo con menor distancia
      String u = unvisited.first;
      for (final x in unvisited) {
        if ((dist[x] ?? double.infinity) < (dist[u] ?? double.infinity)) {
          u = x;
        }
      }
      unvisited.remove(u);

      if (u == goal) break;
      if ((dist[u] ?? double.infinity) == double.infinity) break;

      for (final e in g[u] ?? const []) {
        final alt = (dist[u] ?? double.infinity) + e.w;
        if (alt < (dist[e.v] ?? double.infinity)) {
          dist[e.v] = alt;
          prev[e.v] = u;
        }
      }
    }

    // reconstruir ruta
    final path = <String>[];
    String? u = goal;
    if ((prev[u] != null) || u == start) {
      while (u != null) {
        path.insert(0, u);
        u = prev[u];
      }
    }
    return path;
  }

  void _snack(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(msg), behavior: SnackBarBehavior.floating),
    );
  }
}

class _Edge {
  final String v;
  final double w;
  _Edge(this.v, this.w);
}

