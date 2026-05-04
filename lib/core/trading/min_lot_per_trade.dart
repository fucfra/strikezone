/// Lotto minimo per operazione: stesso criterio per majors e croci JPY
/// (incremento 0.01 lot tipico dei conti standard; nessun minimo diverso implicito per JPY).
double effectiveMinLotPerTrade({
  required double configured,
  double absoluteFloor = 0.01,
}) {
  if (!configured.isFinite || configured <= 0) {
    return absoluteFloor;
  }
  return configured < absoluteFloor ? absoluteFloor : configured;
}
