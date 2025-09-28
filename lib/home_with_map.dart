import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:geocalendar_gt/task_provider.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:geocalendar_gt/location.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:google_sign_in/google_sign_in.dart';

class HomeWithMap extends StatelessWidget {
  const HomeWithMap({super.key});

  Future<void> _signOut() async {
    await FirebaseAuth.instance.signOut();
    try {
      await GoogleSignIn().signOut();
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    final tasks = context.watch<TaskProvider>().tasks;

    return LayoutBuilder(
      builder: (context, constraints) {
        final isWide = constraints.maxWidth >= 1000; // breakpoint

        if (isWide) {
          // -------- DESKTOP/TABLET LANDSCAPE (WIDE) --------
          final rightPanelWidth = constraints.maxWidth * 0.28;
          final clampedRight = rightPanelWidth.clamp(320.0, 420.0);

          return Scaffold(
            body: SafeArea(
              child: Row(
                children: [
                  // Left navigation rail
                  NavigationRail(
                    backgroundColor: const Color(0xFF071023),
                    selectedIndex: 0,
                    onDestinationSelected: (_) {},
                    labelType: NavigationRailLabelType.all,
                    destinations: const [
                      NavigationRailDestination(
                        icon: Icon(Icons.map),
                        label: Text('Map'),
                      ),
                      NavigationRailDestination(
                        icon: Icon(Icons.list),
                        label: Text('Tasks'),
                      ),
                      NavigationRailDestination(
                        icon: Icon(Icons.settings),
                        label: Text('Settings'),
                      ),
                    ],
                  ),

                  // Middle: map view
                  Expanded(
                    child: Padding(
                      padding: const EdgeInsets.all(12.0),
                      child: Card(
                        color: const Color(0xFF0B1220),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                        elevation: 8,
                        child: Stack(
                          children: [
                            Positioned.fill(child: GoogleMapWidget(tasks: tasks)),
                            const _MyLocationFab(),
                          ],
                        ),
                      ),
                    ),
                  ),

                  // Right: task panel
                  Container(
                    width: clampedRight.toDouble(),
                    color: const Color(0xFF071226),
                    child: Column(
                      children: [
                        Padding(
                          padding: const EdgeInsets.all(12.0),
                          child: Row(
                            children: [
                              const Expanded(
                                child: Text(
                                  'Tasks',
                                  style: TextStyle(
                                    fontSize: 18,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              ),
                              IconButton(
                                tooltip: 'Add Task',
                                onPressed: () => Navigator.pushNamed(context, '/add'),
                                icon: const Icon(Icons.add_circle_outline),
                              ),
                              IconButton(
                                tooltip: 'Sign out',
                                onPressed: _signOut,
                                icon: const Icon(Icons.logout),
                              ),
                            ],
                          ),
                        ),
                        const Divider(color: Colors.white12),
                        Expanded(child: _TasksList(tasks: tasks)),
                        Padding(
                          padding: const EdgeInsets.all(12.0),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              const Text('Quick Add (NLP)',
                                  style: TextStyle(fontWeight: FontWeight.bold)),
                              const SizedBox(height: 8),
                              ElevatedButton.icon(
                                onPressed: () => Navigator.pushNamed(context, '/add'),
                                icon: const Icon(Icons.chat_bubble_outline),
                                label: const Text('Open NLP Composer'),
                              ),
                              const SizedBox(height: 12),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          );
        }

        // -------- PHONE/PORTRAIT (COMPACT) --------
        return Scaffold(
          appBar: AppBar(
            title: const Text('GeoRemind'),
            actions: [
              IconButton(
                tooltip: 'Add Task',
                onPressed: () => Navigator.pushNamed(context, '/add'),
                icon: const Icon(Icons.add_circle_outline),
              ),
              IconButton(
                tooltip: 'Sign out',
                onPressed: _signOut,
                icon: const Icon(Icons.logout),
              ),
            ],
          ),
          body: Stack(
            children: [
              Positioned.fill(child: GoogleMapWidget(tasks: tasks)),
              // Draggable bottom sheet for tasks
              DraggableScrollableSheet(
                initialChildSize: 0.25,
                minChildSize: 0.18,
                maxChildSize: 0.85,
                builder: (context, scrollController) {
                  return Container(
                    decoration: const BoxDecoration(
                      color: Color(0xFF071226),
                      borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
                    ),
                    child: Column(
                      children: [
                        const SizedBox(height: 8),
                        Container(
                          width: 40,
                          height: 4,
                          decoration: BoxDecoration(
                            color: Colors.white24,
                            borderRadius: BorderRadius.circular(2),
                          ),
                        ),
                        const SizedBox(height: 8),
                        const Padding(
                          padding: EdgeInsets.symmetric(horizontal: 12.0),
                          child: Align(
                            alignment: Alignment.centerLeft,
                            child: Text(
                              'Tasks',
                              style: TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                        ),
                        const Divider(color: Colors.white12, height: 16),
                        Expanded(
                          child: _TasksList(
                            tasks: tasks,
                            controller: scrollController,
                          ),
                        ),
                        Padding(
                          padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
                          child: ElevatedButton.icon(
                            onPressed: () => Navigator.pushNamed(context, '/add'),
                            icon: const Icon(Icons.chat_bubble_outline),
                            label: const Text('Open NLP Composer'),
                          ),
                        ),
                      ],
                    ),
                  );
                },
              ),
              const _MyLocationFab(),
            ],
          ),
        );
      },
    );
  }
}

class _MyLocationFab extends StatelessWidget {
  const _MyLocationFab();

  @override
  Widget build(BuildContext context) {
    return Positioned(
      right: 12,
      bottom: 12,
      child: FloatingActionButton(
        onPressed: () async {
          final pos = await LocationService().getCurrentPosition();
          final mapState = context.findAncestorStateOfType<_GoogleMapWidgetState>();
          if (pos != null && mapState?.controller != null) {
            mapState!.controller!.animateCamera(
              CameraUpdate.newLatLng(LatLng(pos.latitude, pos.longitude)),
            );
          }
        },
        child: const Icon(Icons.my_location),
      ),
    );
  }
}

class _TasksList extends StatelessWidget {
  final List tasks;
  final ScrollController? controller;
  const _TasksList({super.key, required this.tasks, this.controller});

  @override
  Widget build(BuildContext context) {
    return ListView.builder(
      controller: controller,
      padding: const EdgeInsets.all(8),
      itemCount: tasks.length,
      itemBuilder: (c, i) {
        final t = tasks[i];
        String initials = '';
        if (t.title.trim().isNotEmpty) {
          final parts = t.title.trim().split(RegExp(r'\s+'));
          initials = parts.take(2).map((s) => s.isNotEmpty ? s[0].toUpperCase() : '').join();
        }
        return Card(
          color: const Color(0xFF0E1622),
          margin: const EdgeInsets.symmetric(vertical: 6),
          child: InkWell(
            onTap: () {
              showModalBottomSheet(
                context: context,
                isScrollControlled: true,
                backgroundColor: const Color(0xFF0B1220),
                shape: const RoundedRectangleBorder(
                  borderRadius: BorderRadius.vertical(top: Radius.circular(12)),
                ),
                builder: (sheetCtx) {
                  final titleCtrl = TextEditingController(text: t.title);
                  final locCtrl = TextEditingController(text: t.locationText);
                  return Padding(
                    padding: EdgeInsets.only(
                      bottom: MediaQuery.of(sheetCtx).viewInsets.bottom,
                    ),
                    child: Padding(
                      padding: const EdgeInsets.all(12.0),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            'Edit task',
                            style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                          ),
                          const SizedBox(height: 12),
                          TextField(
                            controller: titleCtrl,
                            decoration: const InputDecoration(labelText: 'Title'),
                          ),
                          const SizedBox(height: 8),
                          TextField(
                            controller: locCtrl,
                            decoration: const InputDecoration(labelText: 'Location'),
                          ),
                          const SizedBox(height: 12),
                          Row(
                            children: [
                              ElevatedButton.icon(
                                onPressed: () {
                                  context.read<TaskProvider>().updateTask(
                                        t.id,
                                        title: titleCtrl.text.trim(),
                                        locationText: locCtrl.text.trim(),
                                      );
                                  Navigator.of(sheetCtx).pop();
                                },
                                icon: const Icon(Icons.save),
                                label: const Text('Save'),
                              ),
                              const SizedBox(width: 12),
                              OutlinedButton.icon(
                                onPressed: () {
                                  context.read<TaskProvider>().removeTask(t.id);
                                  Navigator.of(sheetCtx).pop();
                                },
                                icon: const Icon(Icons.delete_outline),
                                label: const Text('Delete'),
                                style: OutlinedButton.styleFrom(
                                  foregroundColor: Colors.redAccent,
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 8),
                          Text(
                            'Coordinates: ${t.lat.toStringAsFixed(6)}, ${t.lng.toStringAsFixed(6)}',
                            style: const TextStyle(color: Colors.white70),
                          ),
                          const SizedBox(height: 8),
                        ],
                      ),
                    ),
                  );
                },
              );
            },
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 8),
              child: Row(
                children: [
                  CircleAvatar(
                    radius: 20,
                    backgroundColor: Colors.deepPurpleAccent.shade200,
                    child: Text(
                      initials,
                      style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(t.title,
                            style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600)),
                        const SizedBox(height: 4),
                        Text(
                          t.locationText.isNotEmpty ? t.locationText : 'No location',
                          style: const TextStyle(color: Colors.white70, fontSize: 13),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 8),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(
                      color: Colors.white12,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(
                      '${t.lat.toStringAsFixed(3)}, ${t.lng.toStringAsFixed(3)}',
                      style: const TextStyle(fontSize: 12, color: Colors.white70),
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}

class GoogleMapWidget extends StatefulWidget {
  final List tasks;
  const GoogleMapWidget({super.key, required this.tasks});

  @override
  State<GoogleMapWidget> createState() => _GoogleMapWidgetState();
}

class _GoogleMapWidgetState extends State<GoogleMapWidget> {
  GoogleMapController? controller;

  static const CameraPosition _initialCamera = CameraPosition(
    target: LatLng(33.7756, -84.398),
    zoom: 15.0,
  );

  Set<Marker> _markersFromTasks() {
    final markers = <Marker>{};
    for (var t in widget.tasks) {
      markers.add(
        Marker(
          markerId: MarkerId(t.id),
          position: LatLng(t.lat, t.lng),
          infoWindow: InfoWindow(title: t.title, snippet: t.locationText),
        ),
      );
    }
    return markers;
  }

  @override
  Widget build(BuildContext context) {
    return GoogleMap(
      initialCameraPosition: _initialCamera,
      onMapCreated: (c) => controller = c,
      myLocationEnabled: true,
      markers: _markersFromTasks(),
    );
  }
}
