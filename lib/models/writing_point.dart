class WritingPoint {
  final double x;
  final double y;
  final int time;

  const WritingPoint({
    required this.x,
    required this.y,
    required this.time,
  });

  factory WritingPoint.fromOffset({
    required double x,
    required double y,
    required int time,
  }) {
    return WritingPoint(
      x: x,
      y: y,
      time: time,
    );
  }

  @override
  String toString() {
    return 'WritingPoint(x: $x, y: $y, time: $time)';
  }
}