enum DestinationSource { search, map }

enum FixedRole { none, origin, destination }

class Destination {
  Destination({
    required this.id,
    required this.name,
    required this.latitude,
    required this.longitude,
    this.source = DestinationSource.search,
    this.fixedRole = FixedRole.none,
  });

  final String id;
  final String name;
  final double latitude;
  final double longitude;
  final DestinationSource source;
  final FixedRole fixedRole;
}

