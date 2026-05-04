// lib/presentation/widgets/live_quotation_card.dart
import 'package:flutter/material.dart';

import '../../core/theme/app_theme.dart';
import '../../core/trading/fx_pair_utils.dart';
import '../../data/models/quote_model.dart';

/// Card quotazione live (Capital.com `GET /markets/{epic}`): mid, bid/ask, spread, high/low.
/// Layout compatto in altezza come design UI.
class LiveQuotationCard extends StatelessWidget {
  static const Color _cardFill = Color(0xFF020617);
  static const Color _sellAccent = Color(0xFFFF7A8C);
  static const Color _sellBorder = Color(0x66FF4D6D);
  static const Color _midPriceColor = Color(0xFFCBD5E1);
  static const Color _buyFill = Color(0xFF052E14);

  final QuoteModel quote;

  const LiveQuotationCard({super.key, required this.quote});

  static const EdgeInsets _cardPadding =
      EdgeInsets.fromLTRB(AppSpacing.s4, AppSpacing.s3, AppSpacing.s4, AppSpacing.s3);

  String _readablePair(String epic) {
    if (epic.contains('.')) {
      final parts = epic.split('.');
      if (parts.length >= 3) {
        final currencyPair = parts[2];
        if (currencyPair.length == 6) {
          return '${currencyPair.substring(0, 3)}/${currencyPair.substring(3, 6)}';
        }
      }
    } else if (epic.length == 6) {
      return '${epic.substring(0, 3)}/${epic.substring(3, 6)}';
    }
    return epic;
  }

  String _updateLabel(DateTime updateTime) {
    final difference = DateTime.now().difference(updateTime);
    if (difference.inSeconds < 60) {
      return 'Aggiornato ora';
    }
    if (difference.inMinutes < 60) {
      final m = difference.inMinutes;
      return 'Aggiornato $m ${m == 1 ? 'minuto' : 'minuti'} fa';
    }
    if (difference.inHours < 24) {
      final h = difference.inHours;
      return 'Aggiornato $h ${h == 1 ? 'ora' : 'ore'} fa';
    }
    final d = difference.inDays;
    return 'Aggiornato $d ${d == 1 ? 'giorno' : 'giorni'} fa';
  }

  String _marketStatusLabel(String raw) {
    switch (raw.toUpperCase()) {
      case 'TRADEABLE':
        return 'APERTO';
      case 'CLOSED':
        return 'CHIUSO';
      case 'SUSPENDED':
        return 'SOSPESO';
      default:
        return raw.toUpperCase();
    }
  }

  bool get _isTradeable =>
      quote.marketStatus.toUpperCase() == 'TRADEABLE';

  /// Variazione % da `percentageChange` o stimata da `netChange` / mid.
  double? _effectivePercent() {
    final p = quote.percentageChange;
    if (p != null) return p;
    final n = quote.netChange;
    final mid = quote.price;
    if (n != null && mid.abs() > 1e-12) {
      return (n / mid) * 100.0;
    }
    return null;
  }

  String _percentLine() {
    final eff = _effectivePercent();
    if (eff == null) return '—';
    final sign = eff >= 0 ? '+' : '';
    return '$sign${eff.toStringAsFixed(2)}%';
  }

  bool _percentPositive() {
    final eff = _effectivePercent();
    if (eff == null) return true;
    return eff >= 0;
  }

  double _spreadPips() {
    return (quote.ofr - quote.bid) * pipMultiplierForPair(quote.epic);
  }

  TextStyle _tabular({
    required double fontSize,
    required FontWeight w,
    Color? color,
    double height = 1.05,
  }) {
    return TextStyle(
      fontSize: fontSize,
      fontWeight: w,
      color: color,
      height: height,
      fontFeatures: const [FontFeature.tabularFigures()],
    );
  }

  String _fmtPrice(double v) {
    return v.toStringAsFixed(quote.priceFractionDigits);
  }

  @override
  Widget build(BuildContext context) {
    final pairName = _readablePair(quote.epic);
    final d = quote.priceFractionDigits;
    final statusColor = _isTradeable ? AppTheme.accentGreen : AppTheme.accentRed;
    final statusText = _marketStatusLabel(quote.marketStatus);
    final hasPct = _effectivePercent() != null;
    final pctPositive = _percentPositive();
    final pctColor = !hasPct
        ? AppTheme.secondaryText
        : (pctPositive ? AppTheme.accentGreen : AppTheme.accentRed);

    return Container(
      decoration: BoxDecoration(
        color: _cardFill,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
          color: AppTheme.panelBorderMuted.withValues(alpha: 0.65),
          width: 1,
        ),
      ),
      child: Padding(
        padding: _cardPadding,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Text(
                    pairName,
                    style: const TextStyle(
                      fontSize: 17,
                      fontWeight: FontWeight.w800,
                      color: AppTheme.primaryText,
                      letterSpacing: 0.15,
                    ),
                  ),
                ),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      quote.price.toStringAsFixed(d),
                      style: _tabular(
                        fontSize: 20,
                        w: FontWeight.w700,
                        color: _midPriceColor,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        if (hasPct)
                          Icon(
                            pctPositive
                                ? Icons.arrow_drop_up_rounded
                                : Icons.arrow_drop_down_rounded,
                            size: 20,
                            color: pctColor,
                          ),
                        Text(
                          _percentLine(),
                          style: _tabular(
                            fontSize: 12,
                            w: FontWeight.w700,
                            color: pctColor,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ],
            ),
            SizedBox(height: AppSpacing.s2),
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: AppSpacing.s2,
                    vertical: AppSpacing.s1,
                  ),
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(4),
                    border: Border.all(
                      color: statusColor.withValues(alpha: 0.85),
                      width: 1,
                    ),
                  ),
                  child: Text(
                    statusText,
                    style: TextStyle(
                      fontSize: 10,
                      fontWeight: FontWeight.w800,
                      letterSpacing: 0.6,
                      color: statusColor,
                    ),
                  ),
                ),
                SizedBox(width: AppSpacing.s3),
                Icon(
                  Icons.schedule_rounded,
                  size: 13,
                  color: AppTheme.secondaryText.withValues(alpha: 0.88),
                ),
                SizedBox(width: AppSpacing.s1),
                Expanded(
                  child: Text(
                    _updateLabel(quote.updateTime),
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w500,
                      color: AppTheme.secondaryText.withValues(alpha: 0.9),
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
            SizedBox(height: AppSpacing.s3),
            Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                Expanded(
                  child: _compactSideRow(
                    label: 'BUY',
                    price: quote.ofr,
                    decimals: d,
                    labelColor: AppTheme.accentGreen,
                    priceColor: AppTheme.accentGreen,
                    borderColor: AppTheme.accentGreen.withValues(alpha: 0.55),
                    fillColor: _buyFill.withValues(alpha: 0.55),
                  ),
                ),
                SizedBox(width: AppSpacing.s2),
                Expanded(
                  child: _compactSideRow(
                    label: 'SELL',
                    price: quote.bid,
                    decimals: d,
                    labelColor: _sellAccent.withValues(alpha: 0.95),
                    priceColor: _sellAccent,
                    borderColor: _sellBorder,
                    fillColor: AppTheme.inputFillColor.withValues(alpha: 0.35),
                  ),
                ),
              ],
            ),
            Padding(
              padding: const EdgeInsets.symmetric(vertical: AppSpacing.s2),
              child: Divider(
                height: 1,
                thickness: 1,
                color: AppTheme.panelBorderMuted.withValues(alpha: 0.45),
              ),
            ),
            Row(
              children: [
                Expanded(
                  child: _bottomStat(
                    title: 'SPREAD',
                    value: '${_spreadPips().toStringAsFixed(1)} Pips',
                    valueColor: AppTheme.primaryText,
                  ),
                ),
                _vDivider(),
                Expanded(
                  child: _bottomStat(
                    title: 'HIGH',
                    value: quote.high != null ? _fmtPrice(quote.high!) : '—',
                    valueColor: AppTheme.primaryText,
                  ),
                ),
                _vDivider(),
                Expanded(
                  child: _bottomStat(
                    title: 'LOW',
                    value: quote.low != null ? _fmtPrice(quote.low!) : '—',
                    valueColor: AppTheme.primaryText,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _vDivider() {
    return Container(
      width: 1,
      height: 28,
      color: AppTheme.panelBorderMuted.withValues(alpha: 0.45),
    );
  }

  Widget _bottomStat({
    required String title,
    required String value,
    required Color valueColor,
  }) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Text(
          title,
          textAlign: TextAlign.center,
          style: TextStyle(
            fontSize: 9,
            fontWeight: FontWeight.w700,
            letterSpacing: 0.9,
            color: AppTheme.secondaryText.withValues(alpha: 0.88),
          ),
        ),
        const SizedBox(height: AppSpacing.s1),
        Text(
          value,
          textAlign: TextAlign.center,
          style: _tabular(
            fontSize: 12,
            w: FontWeight.w600,
            color: valueColor,
          ),
        ),
      ],
    );
  }

  Widget _compactSideRow({
    required String label,
    required double price,
    required int decimals,
    required Color labelColor,
    required Color priceColor,
    required Color borderColor,
    required Color fillColor,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.s3,
        vertical: AppSpacing.s2 + 2,
      ),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: borderColor, width: 1),
        color: fillColor,
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Text(
            label,
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w800,
              letterSpacing: 0.8,
              color: labelColor,
            ),
          ),
          Flexible(
            child: Text(
              price.toStringAsFixed(decimals),
              textAlign: TextAlign.end,
              style: _tabular(
                fontSize: 17,
                w: FontWeight.w800,
                color: priceColor,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
