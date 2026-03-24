class LocationRecord {
  final int? id;
  final double lat;
  final double lng;
  final double accuracy;
  final double altitude;
  final double speed;
  final int timestamp; // Unix ms
  final bool synced;

  const LocationRecord({
    this.id,
    required this.lat,
    required this.lng,
    required this.accuracy,
    required this.altitude,
    required this.speed,
    required this.timestamp,
    this.synced = false,
  });

  Map<String, dynamic> toMap() => {
        if (id != null) 'id': id,
        'lat': lat,
        'lng': lng,
        'accuracy': accuracy,
        'altitude': altitude,
        'speed': speed,
        'timestamp': timestamp,
        'synced': synced ? 1 : 0,
      };

  factory LocationRecord.fromMap(Map<String, dynamic> map) => LocationRecord(
        id: map['id'] as int?,
        lat: (map['lat'] as num).toDouble(),
        lng: (map['lng'] as num).toDouble(),
        accuracy: (map['accuracy'] as num).toDouble(),
        altitude: (map['altitude'] as num).toDouble(),
        speed: (map['speed'] as num).toDouble(),
        timestamp: map['timestamp'] as int,
        synced: (map['synced'] as int) == 1,
      );

  Map<String, dynamic> toJson() => {
        'lat': lat,
        'lng': lng,
        'accuracy': accuracy,
        'altitude': altitude,
        'speed': speed,
        'timestamp': timestamp,
      };
}
