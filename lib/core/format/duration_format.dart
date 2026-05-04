/// Durata compatta per UI (es. 2g 3h 15m).
String formatDurationHuman(Duration d) {
  if (d.isNegative) return '—';
  final days = d.inDays;
  final hours = d.inHours.remainder(24);
  final minutes = d.inMinutes.remainder(60);
  if (days > 0) {
    return '${days}g ${hours}h ${minutes}m';
  }
  if (hours > 0) {
    return '${hours}h ${minutes}m';
  }
  if (minutes > 0) {
    return '${minutes}m';
  }
  if (d.inSeconds > 0) {
    return '${d.inSeconds}s';
  }
  return '0s';
}
