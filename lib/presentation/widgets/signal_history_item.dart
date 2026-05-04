import 'dart:ui' show ImageFilter;

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../core/format/duration_format.dart';
import '../../core/theme/app_theme.dart';
import '../../core/trading/fx_pair_utils.dart';
import '../../data/models/quote_model.dart';
import '../../data/models/signal_model.dart';
import 'star_rating.dart';

class SignalHistoryItem extends StatelessWidget {
  final SignalModel signal;
  final QuoteModel? liveQuote;
  final VoidCallback? onTap;
  /// Apertura dettaglio / indicatori (se non si usano i pulsanti dedicati).
  final VoidCallback? onShowIndicators;
  /// Modifica manuale campi esecuzione reale (solo collezione `signals`).
  final VoidCallback? onEditRealSignal;
  /// Alone sfocato attorno al bordo colorato (buy/sell).
  final bool edgeBorderBlur;

  const SignalHistoryItem({
    super.key,
    required this.signal,
    this.liveQuote,
    this.onTap,
    this.onShowIndicators,
    this.onEditRealSignal,
    this.edgeBorderBlur = true,
  });

  static final DateFormat _absoluteTimeFormat = DateFormat('dd/MM/yyyy, HH:mm');

  int get starRating {
    return (signal.score / 20).round().clamp(1, 5);
  }

  bool get _isOpen => !signal.isClosed;

  Color get _typeColor =>
      signal.type == SignalType.buy ? AppTheme.accentGreen : AppTheme.accentRed;

  String get _typeText => signal.type == SignalType.buy ? 'BUY' : 'SELL';

  int _priceDecimals() {
    final p = normalizedPairEpic(signal.pair);
    if (p.length == 6 && p.substring(3, 6) == 'JPY') {
      return 3;
    }
    return 5;
  }

  String _formatPips(double pips) {
    final s = pips.toStringAsFixed(1);
    if (pips > 0) return '+$s';
    return s;
  }

  String _formatEuro(double eur) {
    final s = eur.toStringAsFixed(2);
    if (eur > 0) return '+$s €';
    if (eur < 0) return '$s €';
    return '$s €';
  }

  static String _displayPair(String pair) {
    final e = normalizedPairEpic(pair);
    if (e.length == 6) {
      return '${e.substring(0, 3)}/${e.substring(3, 6)}';
    }
    return pair;
  }

  static bool _stopLossWasUpdated(SignalModel s) {
    final raw = s.rawFirestore;
    const keys = [
      'initialStopLoss',
      'initial_stop_loss',
      'originalStopLoss',
      'previousStopLoss',
      'previous_stop_loss',
    ];
    for (final key in keys) {
      final v = raw[key];
      if (v == null) continue;
      final prev = (v is num) ? v.toDouble() : double.tryParse('$v');
      if (prev != null && (prev - s.stopLoss).abs() > 1e-8) {
        return true;
      }
    }
    return false;
  }

  /// Recente → tempo relativo; altrimenti data/ora generazione.
  static String _timeLabel(DateTime signalTime, DateTime now) {
    final diff = now.difference(signalTime);
    if (diff.isNegative) {
      return _absoluteTimeFormat.format(signalTime.toLocal());
    }
    if (diff.inMinutes < 1) return 'Adesso';
    if (diff.inHours < 48) {
      if (diff.inHours < 1) return '${diff.inMinutes} min fa';
      return '${diff.inHours} h fa';
    }
    return _absoluteTimeFormat.format(signalTime.toLocal());
  }

  String? _durationLabel() {
    if (signal.isClosed && signal.exitTime == null) return null;
    final end = signal.isClosed ? signal.exitTime! : DateTime.now();
    final d = end.difference(signal.timestamp);
    if (d.isNegative) return null;
    return formatDurationHuman(d);
  }

  double? _floatingPips() {
    final q = liveQuote;
    if (q == null) return null;
    if (normalizedPairEpic(q.epic) != normalizedPairEpic(signal.pair)) {
      return null;
    }
    return floatingPipsFromQuote(
      pair: signal.pair,
      isBuy: signal.type == SignalType.buy,
      entryPrice: signal.entryPrice,
      bid: q.bid,
      ofr: q.ofr,
    );
  }

  @override
  Widget build(BuildContext context) {
    final dec = _priceDecimals();
    final now = DateTime.now();
    final typeColor = _typeColor;
    final durationText = _durationLabel();
    final slUpdated = _stopLossWasUpdated(signal);
    final floating = _floatingPips();

    final String plLabel;
    final double? plPips;
    final String? plSubtitle;
    if (_isOpen) {
      plLabel = 'LIVE P/L';
      if (floating != null) {
        plPips = floating;
        plSubtitle = null;
      } else {
        plPips = null;
        plSubtitle = 'Quotazione non disponibile';
      }
    } else {
      plLabel = 'FINAL P/L';
      plPips = signal.effectivePips;
      plSubtitle = null;
    }

    final plColor = plPips == null
        ? AppTheme.secondaryText
        : (plPips > 0
              ? AppTheme.accentGreen
              : plPips < 0
              ? AppTheme.accentRed
              : AppTheme.secondaryText);

    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: onTap,
        child: Container(
          margin: const EdgeInsets.only(bottom: AppSpacing.s3),
          child: Stack(
            clipBehavior: Clip.none,
            alignment: Alignment.center,
            children: [
              if (edgeBorderBlur)
                Positioned(
                  left: -8,
                  right: -8,
                  top: -8,
                  bottom: -8,
                  child: IgnorePointer(
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(18),
                      child: ImageFiltered(
                        imageFilter: ImageFilter.blur(sigmaX: 12, sigmaY: 12),
                        child: DecoratedBox(
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(18),
                            border: Border.all(
                              color: typeColor.withValues(alpha: 0.55),
                              width: 2.5,
                            ),
                          ),
                          child: const SizedBox.expand(),
                        ),
                      ),
                    ),
                  ),
                ),
              Container(
                decoration: BoxDecoration(
                  color: AppTheme.surfaceColor,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: typeColor, width: 1.5),
                  boxShadow: [
                    BoxShadow(
                      color: typeColor.withValues(alpha: 0.28),
                      blurRadius: 10,
                      offset: const Offset(0, 2),
                    ),
                  ],
                ),
                child: Padding(
                  padding: AppSpacing.card,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  _displayPair(signal.pair),
                                  style: const TextStyle(
                                    fontWeight: FontWeight.w800,
                                    fontSize: 20,
                                    color: AppTheme.primaryText,
                                    letterSpacing: 0.2,
                                  ),
                                ),
                                SizedBox(height: AppSpacing.s2),
                                Row(
                                  children: [
                                    StarRating(
                                      rating: starRating,
                                      size: 18,
                                      filledColor: typeColor,
                                    ),
                                    SizedBox(width: AppSpacing.s2),
                                    Text(
                                      'Score: ${signal.score.toStringAsFixed(0)}/100',
                                      style: TextStyle(
                                        fontSize: 12,
                                        fontWeight: FontWeight.w600,
                                        color: typeColor.withValues(
                                          alpha: 0.92,
                                        ),
                                        fontFamily: 'monospace',
                                      ),
                                    ),
                                  ],
                                ),
                              ],
                            ),
                          ),
                          Column(
                            crossAxisAlignment: CrossAxisAlignment.end,
                            children: [
                              Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: AppSpacing.s3,
                                  vertical: AppSpacing.s2,
                                ),
                                decoration: BoxDecoration(
                                  color: typeColor,
                                  borderRadius: BorderRadius.circular(8),
                                ),
                                child: Text(
                                  _typeText,
                                  style: const TextStyle(
                                    color: Colors.white,
                                    fontWeight: FontWeight.w900,
                                    fontSize: 12,
                                    letterSpacing: 0.6,
                                  ),
                                ),
                              ),
                              SizedBox(height: AppSpacing.s2),
                              Text(
                                _timeLabel(signal.timestamp.toLocal(), now),
                                style: TextStyle(
                                  fontSize: 11,
                                  color: AppTheme.secondaryText.withValues(
                                    alpha: 0.9,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                      if (durationText != null) ...[
                        SizedBox(height: AppSpacing.s2),
                        Text(
                          'Durata: $durationText',
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w600,
                            color: AppTheme.secondaryText.withValues(
                              alpha: 0.95,
                            ),
                            fontFamily: 'monospace',
                          ),
                        ),
                      ],
                      SizedBox(height: AppSpacing.section),
                      Container(
                        padding: const EdgeInsets.fromLTRB(
                          AppSpacing.s3,
                          AppSpacing.s3,
                          AppSpacing.s3,
                          AppSpacing.s3,
                        ),
                        decoration: BoxDecoration(
                          color: AppTheme.inputFillColor,
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(color: AppTheme.panelBorderMuted),
                        ),
                        child: Row(
                          children: [
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    plLabel,
                                    style: TextStyle(
                                      fontSize: 10,
                                      fontWeight: FontWeight.w700,
                                      letterSpacing: 1.2,
                                      color: AppTheme.secondaryText.withValues(
                                        alpha: 0.85,
                                      ),
                                    ),
                                  ),
                                  SizedBox(height: AppSpacing.s1),
                                  if (plPips != null)
                                    Row(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.baseline,
                                      textBaseline: TextBaseline.alphabetic,
                                      children: [
                                        Text(
                                          _formatPips(plPips),
                                          style: TextStyle(
                                            fontSize: 26,
                                            fontWeight: FontWeight.w800,
                                            color: plColor,
                                            height: 1.05,
                                            shadows: plPips != 0
                                                ? AppTheme.neonTextGlow(
                                                    color: plColor,
                                                    blurInner: 6,
                                                    blurOuter: 14,
                                                  )
                                                : null,
                                          ),
                                        ),
                                        SizedBox(width: AppSpacing.s2),
                                        Text(
                                          'PIPS',
                                          style: TextStyle(
                                            fontSize: 12,
                                            fontWeight: FontWeight.w700,
                                            color: plColor.withValues(
                                              alpha: 0.85,
                                            ),
                                          ),
                                        ),
                                      ],
                                    )
                                  else
                                    Text(
                                      '—',
                                      style: TextStyle(
                                        fontSize: 22,
                                        fontWeight: FontWeight.w800,
                                        color: AppTheme.secondaryText,
                                      ),
                                    ),
                                  if (plSubtitle != null) ...[
                                    SizedBox(height: AppSpacing.s1),
                                    Text(
                                      plSubtitle,
                                      style: const TextStyle(
                                        fontSize: 10,
                                        color: AppTheme.secondaryText,
                                      ),
                                    ),
                                  ],
                                  if (!_isOpen &&
                                      signal.realizedPnlEuro != null) ...[
                                    SizedBox(height: AppSpacing.s2),
                                    Text(
                                      _formatEuro(signal.realizedPnlEuro!),
                                      style: TextStyle(
                                        fontSize: 12,
                                        fontWeight: FontWeight.w600,
                                        color: plColor,
                                        fontFamily: 'monospace',
                                      ),
                                    ),
                                  ],
                                ],
                              ),
                            ),
                            _MiniPipBars(
                              pips: plPips ?? 0,
                              accent: typeColor,
                              isNeutral: plPips == null,
                            ),
                          ],
                        ),
                      ),
                      SizedBox(height: AppSpacing.section),
                      Divider(
                        height: 1,
                        color: AppTheme.panelBorderMuted.withValues(alpha: 0.7),
                      ),
                      SizedBox(height: AppSpacing.s3),
                      IntrinsicHeight(
                        child: Row(
                          children: [
                            Expanded(
                              child: _gridCell(
                                'ENTRY',
                                signal.entryPrice.toStringAsFixed(dec),
                                null,
                              ),
                            ),
                            Container(
                              width: 1,
                              color: AppTheme.panelBorderMuted.withValues(
                                alpha: 0.6,
                              ),
                            ),
                            Expanded(
                              child: _gridCell(
                                slUpdated ? 'SL (UPDATED)' : 'STOP LOSS',
                                signal.stopLoss.toStringAsFixed(dec),
                                slUpdated ? AppTheme.accentGreen : null,
                              ),
                            ),
                            Container(
                              width: 1,
                              color: AppTheme.panelBorderMuted.withValues(
                                alpha: 0.6,
                              ),
                            ),
                            Expanded(
                              child: _gridCell(
                                'TAKE PROFIT',
                                signal.takeProfit.toStringAsFixed(dec),
                                null,
                              ),
                            ),
                          ],
                        ),
                      ),
                      SizedBox(height: AppSpacing.section),
                      if (signal.executionConfirmed) ...[
                        Row(
                          children: [
                            Icon(
                              Icons.verified_outlined,
                              size: 16,
                              color: AppTheme.accentGreen.withValues(alpha: 0.95),
                            ),
                            SizedBox(width: AppSpacing.s2),
                            Expanded(
                              child: Text(
                                'Esecuzione ordine confermata',
                                style: TextStyle(
                                  fontSize: 11,
                                  fontWeight: FontWeight.w700,
                                  color: AppTheme.accentGreen.withValues(alpha: 0.9),
                                ),
                              ),
                            ),
                          ],
                        ),
                        SizedBox(height: AppSpacing.s3),
                      ],
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Row(
                            children: [
                              Container(
                                width: 8,
                                height: 8,
                                decoration: BoxDecoration(
                                  shape: BoxShape.circle,
                                  color: _isOpen
                                      ? typeColor
                                      : AppTheme.secondaryText,
                                  boxShadow: _isOpen
                                      ? [
                                          BoxShadow(
                                            color: typeColor.withValues(
                                              alpha: 0.55,
                                            ),
                                            blurRadius: 6,
                                          ),
                                        ]
                                      : null,
                                ),
                              ),
                              SizedBox(width: AppSpacing.s2),
                              Text(
                                _isOpen ? 'ATTIVO' : 'CHIUSO',
                                style: TextStyle(
                                  fontSize: 11,
                                  fontWeight: FontWeight.w800,
                                  letterSpacing: 1.1,
                                  color: _isOpen
                                      ? typeColor
                                      : AppTheme.secondaryText,
                                ),
                              ),
                            ],
                          ),
                          if (onEditRealSignal != null ||
                              onShowIndicators != null) ...[
                            SizedBox(height: AppSpacing.s3),
                            Row(
                              children: [
                                if (onEditRealSignal != null)
                                  Expanded(
                                    child: OutlinedButton(
                                      onPressed: onEditRealSignal,
                                      style: OutlinedButton.styleFrom(
                                        foregroundColor: typeColor,
                                        side: BorderSide(
                                          color: typeColor.withValues(
                                            alpha: 0.85,
                                          ),
                                        ),
                                        padding: const EdgeInsets.symmetric(
                                          horizontal: AppSpacing.s2,
                                          vertical: AppSpacing.s2,
                                        ),
                                      ),
                                      child: const Text(
                                        'MODIFICA',
                                        style: TextStyle(
                                          fontSize: 10,
                                          fontWeight: FontWeight.w800,
                                          letterSpacing: 0.3,
                                        ),
                                      ),
                                    ),
                                  ),
                                if (onEditRealSignal != null &&
                                    onShowIndicators != null)
                                  SizedBox(width: AppSpacing.s2),
                                if (onShowIndicators != null)
                                  Expanded(
                                    child: OutlinedButton(
                                      onPressed: onShowIndicators,
                                      style: OutlinedButton.styleFrom(
                                        foregroundColor: typeColor,
                                        side: BorderSide(
                                          color: typeColor.withValues(
                                            alpha: 0.85,
                                          ),
                                        ),
                                        padding: const EdgeInsets.symmetric(
                                          horizontal: AppSpacing.s2,
                                          vertical: AppSpacing.s2,
                                        ),
                                      ),
                                      child: const Text(
                                        'INDICATORI',
                                        style: TextStyle(
                                          fontSize: 10,
                                          fontWeight: FontWeight.w800,
                                          letterSpacing: 0.3,
                                        ),
                                      ),
                                    ),
                                  ),
                              ],
                            ),
                          ] else if (onTap != null) ...[
                            SizedBox(height: AppSpacing.s2),
                            Align(
                              alignment: Alignment.centerRight,
                              child: OutlinedButton(
                                onPressed: onTap,
                                style: OutlinedButton.styleFrom(
                                  foregroundColor: typeColor,
                                  side: BorderSide(
                                    color: typeColor.withValues(alpha: 0.85),
                                  ),
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: AppSpacing.s3,
                                    vertical: AppSpacing.s2,
                                  ),
                                  minimumSize: Size.zero,
                                  tapTargetSize:
                                      MaterialTapTargetSize.shrinkWrap,
                                ),
                                child: const Text(
                                  'GESTISCI POSIZIONE',
                                  style: TextStyle(
                                    fontSize: 11,
                                    fontWeight: FontWeight.w800,
                                    letterSpacing: 0.4,
                                  ),
                                ),
                              ),
                            ),
                          ],
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _gridCell(String label, String value, Color? iconColor) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.s2),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            mainAxisSize: MainAxisSize.min,
            children: [
              Flexible(
                child: Text(
                  label,
                  textAlign: TextAlign.center,
                  maxLines: 2,
                  style: TextStyle(
                    fontSize: 9,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 0.6,
                    color: AppTheme.secondaryText.withValues(alpha: 0.9),
                  ),
                ),
              ),
              if (iconColor != null) ...[
                SizedBox(width: AppSpacing.s1),
                Icon(
                  Icons.keyboard_double_arrow_up_rounded,
                  size: 14,
                  color: iconColor,
                ),
              ],
            ],
          ),
          SizedBox(height: AppSpacing.s2),
          Text(
            value,
            textAlign: TextAlign.center,
            style: const TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: AppTheme.primaryText,
              fontFamily: 'monospace',
            ),
          ),
        ],
      ),
    );
  }
}

/// Barre decorative proporzionali al segno/intensità dei pips.
class _MiniPipBars extends StatelessWidget {
  final double pips;
  final Color accent;
  final bool isNeutral;

  const _MiniPipBars({
    required this.pips,
    required this.accent,
    required this.isNeutral,
  });

  @override
  Widget build(BuildContext context) {
    final magn = isNeutral ? 0.0 : pips.abs().clamp(0.0, 50.0) / 50.0;
    final heights = List<double>.generate(5, (i) {
      final t = (i + 1) / 5.0;
      final base = 4.0 + 14.0 * t * (0.35 + 0.65 * magn);
      return base.clamp(4.0, 22.0);
    });

    return SizedBox(
      width: 44,
      height: 40,
      child: Row(
        mainAxisAlignment: MainAxisAlignment.end,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: List.generate(5, (i) {
          final h = heights[i];
          final opacity = 0.35 + (i + 1) * 0.13;
          return Padding(
            padding: const EdgeInsets.only(left: 3),
            child: Container(
              width: 5,
              height: h,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(2),
                gradient: LinearGradient(
                  begin: Alignment.bottomCenter,
                  end: Alignment.topCenter,
                  colors: [
                    accent.withValues(alpha: isNeutral ? 0.15 : opacity * 0.5),
                    accent.withValues(alpha: isNeutral ? 0.08 : opacity),
                  ],
                ),
              ),
            ),
          );
        }),
      ),
    );
  }
}
