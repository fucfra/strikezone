/// Converte mappe Firestore (`Map` dinamica) in `Map<String, dynamic>`.
Map<String, dynamic> stringKeyedMapFromFirestore(dynamic raw) {
  if (raw is Map<String, dynamic>) {
    return Map<String, dynamic>.from(raw);
  }
  if (raw is Map) {
    return raw.map((k, v) => MapEntry(k.toString(), v));
  }
  return const {};
}
