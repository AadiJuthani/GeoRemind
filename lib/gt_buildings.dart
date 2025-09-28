class GTBuilding {
  final String name;
  final double lat;
  final double lng;
  const GTBuilding(this.name, this.lat, this.lng);
}

// Canonical list of allowed Georgia Tech campus buildings for selection.
const List<GTBuilding> kGtBuildings = [
  GTBuilding('Klaus Advanced Computing Building', 33.7774, -84.3973),
  GTBuilding('Clough Commons', 33.7746, -84.3964),
  GTBuilding('Student Center', 33.7738, -84.3988),
  GTBuilding('Tech Tower', 33.7726, -84.3947),
  GTBuilding('Price Gilbert Library', 33.7745, -84.3951),
  GTBuilding('Campus Recreation Center (CRC)', 33.7754, -84.4037),
  GTBuilding('Howey Physics Building', 33.7770, -84.3982),
  GTBuilding('CODA Building', 33.7767, -84.3899),
  GTBuilding('North Avenue Dining Hall', 33.7705, -84.3915),
  GTBuilding('West Village Dining Commons', 33.7786, -84.4049),
  GTBuilding('Marcus Nanotechnology Center', 33.7779, -84.4022),
  GTBuilding('Biotech Quad', 33.7781, -84.4004),
];