/// Chiave epic tipo `EURUSD` da `EUR/USD`, `eurusd`, ecc.
String normalizedPairEpic(String pair) {
  return pair.toUpperCase().replaceAll(RegExp(r'[^A-Z]'), '');
}

/// Pips non realizzati rispetto a [entry], lato mercato coerente con chiusura.
/// Buy: valutazione al bid; Sell: valutazione all'ask ([ofr]).
double floatingPipsFromQuote({
  required String pair,
  required bool isBuy,
  required double entryPrice,
  required double bid,
  required double ofr,
}) {
  final mult = pipMultiplierForPair(pair);
  if (isBuy) {
    return (bid - entryPrice) * mult;
  }
  return (entryPrice - ofr) * mult;
}

/// Dimensione di 1 pip in prezzo (non-JPY: 0.0001; JPY: 0.01).
double pipSizeForPair(String pair) {
  final p = pair.toUpperCase().replaceAll(RegExp(r'[^A-Z]'), '');
  if (p.length == 6 && p.substring(3, 6) == 'JPY') {
    return 0.01;
  }
  return 0.0001;
}

/// Moltiplicatore prezzo → pips (1 pip = 0.0001 o 0.01 per quotazione JPY).
double pipMultiplierForPair(String pair) {
  return 1.0 / pipSizeForPair(pair);
}
