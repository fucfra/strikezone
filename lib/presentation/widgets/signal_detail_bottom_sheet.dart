import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

import '../../core/theme/app_theme.dart';
import '../../data/models/signal_model.dart';

const _indicatorLabels = <String, String>{
  'emaLong': 'EMA lunga',
  'emaShort': 'EMA corta',
  'smaSignal': 'SMA segnale',
  'rsi': 'RSI',
  'macd_hist': 'MACD (istogramma)',
  'pivot': 'Pivot',
  'adrScore': 'ADR score',
};

String _indicatorTitle(String key) =>
    _indicatorLabels[key] ?? key.replaceAllMapped(RegExp(r'([A-Z])'), (m) => ' ${m[1]}').trim();

String _formatNum(num? n) {
  if (n == null || !n.isFinite) return '—';
  if (n == n.roundToDouble()) return n.round().toString();
  var s = n.toStringAsFixed(5);
  s = s.replaceFirst(RegExp(r'0+$'), '');
  s = s.replaceFirst(RegExp(r'\.$'), '');
  return s;
}

String _formatDynamic(dynamic v) {
  if (v == null) return '—';
  if (v is num) return _formatNum(v.toDouble());
  if (v is bool) return v ? 'Sì' : 'No';
  if (v is Timestamp) {
    final d = v.toDate().toUtc();
    return '${d.day.toString().padLeft(2, '0')}/${d.month.toString().padLeft(2, '0')}/${d.year} '
        '${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')} UTC';
  }
  if (v is String) return v;
  return v.toString();
}

bool _mapEnabled(dynamic m) {
  if (m is! Map) return true;
  final e = m['enabled'];
  if (e is bool) return e;
  return true;
}

/// Righe leggibili per la mappa `indicators` dello snapshot (numeri o `{ enabled, value, … }`).
List<(String, String)> _indicatorRowsFromSnapshot(Map<String, dynamic> snap) {
  final ind = snap['indicators'];
  if (ind is! Map) return const [];
  final keys = ind.keys.map((k) => k.toString()).toList()..sort();
  final out = <(String, String)>[];
  for (final k in keys) {
    if (k.startsWith('filter_')) continue;
    final raw = ind[k];
    if (raw is Map) {
      if (!_mapEnabled(raw)) continue;
      final v = raw['value'];
      if (v == null && raw['reason'] != null) {
        out.add((_indicatorTitle(k), '${raw['reason']}'));
        continue;
      }
      out.add((_indicatorTitle(k), _formatDynamic(v)));
    } else {
      out.add((_indicatorTitle(k), _formatDynamic(raw)));
    }
  }
  return out;
}

List<(String, String)> _activeStrategyFilterRows(Map<String, dynamic>? filt) {
  if (filt == null) return const [];
  final out = <(String, String)>[];

  final adx = filt['adx'];
  if (adx is Map && adx['enabled'] == true) {
    final di = adx['filterDi'] == true ? ' · +DI/−DI' : '';
    out.add((
      'ADX',
      '${adx['timeframe'] ?? '—'} · periodo ${adx['period'] ?? '—'} · soglia ${adx['threshold'] ?? '—'}$di',
    ));
  }

  final bb = filt['bollinger'];
  if (bb is Map && bb['enabled'] == true) {
    out.add((
      'Bollinger',
      '${bb['timeframe'] ?? '—'} · L${bb['length'] ?? '—'} · σ${bb['std'] ?? '—'}',
    ));
  }

  final st = filt['superTrend'];
  if (st is Map && st['enabled'] == true) {
    out.add((
      'SuperTrend',
      '${st['timeframe'] ?? '—'} · periodo ${st['period'] ?? '—'} · moltiplicatore ${st['multiplier'] ?? '—'}',
    ));
  }

  final sess = filt['tradingSession'];
  if (sess is Map && sess['enabled'] == true) {
    out.add((
      'Sessione',
      '${sess['start'] ?? '—'} – ${sess['end'] ?? '—'}',
    ));
  }

  final parts = <String>[];
  final ms = filt['maxSpreadAllowed'];
  if (ms is num) {
    parts.add('spread max ${_formatNum(ms.toDouble())} pips');
  }
  final minA = filt['minAtrLevel'];
  if (minA is num) {
    parts.add('ATR min ${_formatNum(minA.toDouble())}');
  }
  final maxAdr = filt['maxAdrExtension'];
  if (maxAdr is num) {
    parts.add('ADR max ${_formatNum(maxAdr.toDouble())}');
  }
  if (parts.isNotEmpty) {
    out.add(('Soglie di ingresso', parts.join(' · ')));
  }

  return out;
}

/// Valori contestuali salvati sulla barra di decisione (`indicatorsSnapshot.filters`).
List<(String, String)> _decisionContextRows(Map<String, dynamic> snap) {
  final f = snap['filters'];
  if (f is! Map) return const [];
  final m = Map<String, dynamic>.from(f);
  final out = <(String, String)>[];

  if (m.containsKey('atrOperativo')) {
    out.add(('ATR operativo (barra)', _formatDynamic(m['atrOperativo'])));
  }
  if (m.containsKey('spreadPips')) {
    out.add(('Spread (barra)', '${_formatDynamic(m['spreadPips'])} pips'));
  }
  if (m.containsKey('adx')) {
    out.add(('Lettura ADX (barra)', _formatDynamic(m['adx'])));
  }
  if (m.containsKey('diPlus') || m.containsKey('diMinus')) {
    out.add((
      '+DI / −DI',
      '${_formatDynamic(m['diPlus'])} / ${_formatDynamic(m['diMinus'])}',
    ));
  }
  if (m.containsKey('superTrendDir')) {
    final d = m['superTrendDir'];
    final t = d is num
        ? (d > 0 ? 'rialzista' : d < 0 ? 'ribassista' : 'neutro')
        : _formatDynamic(d);
    out.add(('SuperTrend (direzione)', t));
  }
  if (m.containsKey('bbUpper') || m.containsKey('bbLower')) {
    out.add((
      'Bollinger (barra)',
      'Upper ${_formatDynamic(m['bbUpper'])} · Lower ${_formatDynamic(m['bbLower'])}',
    ));
  }
  if (m.containsKey('decisionTimestamp')) {
    out.add(('Timestamp barra', _formatDynamic(m['decisionTimestamp'])));
  }

  return out;
}

double? _activationScore(Map<String, dynamic> snap) {
  final a = snap['activationScore'];
  if (a is num) return a.toDouble();
  return null;
}

class _SectionTitle extends StatelessWidget {
  const _SectionTitle(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: AppSpacing.s4, bottom: AppSpacing.s2),
      child: Text(
        text,
        style: TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w800,
          letterSpacing: 1.0,
          color: AppTheme.accentGreen.withValues(alpha: 0.95),
        ),
      ),
    );
  }
}

class _InfoRow extends StatelessWidget {
  const _InfoRow({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.s2),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            flex: 2,
            child: Text(
              label,
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                height: 1.3,
                color: AppTheme.secondaryText.withValues(alpha: 0.95),
              ),
            ),
          ),
          SizedBox(width: AppSpacing.s2),
          Expanded(
            flex: 3,
            child: Text(
              value,
              textAlign: TextAlign.end,
              style: const TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                height: 1.35,
                color: AppTheme.primaryText,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _EmptyHint extends StatelessWidget {
  const _EmptyHint(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.s2),
      child: Text(
        text,
        style: TextStyle(
          fontSize: 12,
          height: 1.35,
          color: AppTheme.secondaryText.withValues(alpha: 0.88),
        ),
      ),
    );
  }
}

void showSignalDetailBottomSheet(BuildContext context, SignalModel signal) {
  final snap = signal.indicatorsSnapshot;
  final strategy = signal.rawFirestore['strategy'];
  Map<String, dynamic>? filt;
  if (strategy is Map && strategy['filters'] is Map) {
    filt = Map<String, dynamic>.from(strategy['filters'] as Map);
  }

  final indicatorRows = _indicatorRowsFromSnapshot(snap);
  final filterRows = _activeStrategyFilterRows(filt);
  final decisionRows = _decisionContextRows(snap);
  final actScore = _activationScore(snap);

  showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    backgroundColor: AppTheme.inputFillColor,
    builder: (ctx) {
      return DraggableScrollableSheet(
        expand: false,
        initialChildSize: 0.72,
        minChildSize: 0.35,
        maxChildSize: 0.96,
        builder: (context, scrollController) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(
                  AppSpacing.pageH,
                  AppSpacing.s2,
                  AppSpacing.pageH,
                  AppSpacing.s1,
                ),
                child: Text(
                  '${signal.pair} · ${signal.type == SignalType.buy ? 'BUY' : 'SELL'}',
                  style: Theme.of(context).textTheme.titleLarge?.copyWith(
                        fontWeight: FontWeight.bold,
                        color: AppTheme.primaryText,
                      ),
                ),
              ),
              Padding(
                padding: AppSpacing.pageHorizontalOnly,
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        'Score: ${_formatNum(signal.score)}',
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w700,
                          color: AppTheme.accentGreen.withValues(alpha: 0.92),
                        ),
                      ),
                    ),
                    if (actScore != null)
                      Text(
                        'Soglia attivazione: ${_formatNum(actScore)}',
                        style: TextStyle(
                          fontSize: 12,
                          color: AppTheme.secondaryText.withValues(alpha: 0.9),
                        ),
                      ),
                  ],
                ),
              ),
              Padding(
                padding: AppSpacing.pageHorizontalOnly,
                child: Text(
                  'ID: ${signal.id}',
                  style: TextStyle(
                    fontSize: 11,
                    color: AppTheme.secondaryText.withValues(alpha: 0.85),
                  ),
                ),
              ),
              AppSpacing.gapS2,
              Expanded(
                child: Scrollbar(
                  controller: scrollController,
                  thumbVisibility: true,
                  child: ListView(
                    controller: scrollController,
                    padding: const EdgeInsets.fromLTRB(
                      AppSpacing.pageH,
                      0,
                      AppSpacing.pageH,
                      AppSpacing.s6,
                    ),
                    children: [
                      const _SectionTitle('INDICATORI (ATTIVI)'),
                      if (indicatorRows.isEmpty)
                        const _EmptyHint(
                          'Nessun valore indicatore nello snapshot di questo segnale.',
                        )
                      else
                        ...indicatorRows.map(
                          (e) => _InfoRow(label: e.$1, value: e.$2),
                        ),
                      const _SectionTitle('FILTRI ATTIVI (STRATEGIA)'),
                      if (filt == null)
                        const _EmptyHint(
                          'Strategia non salvata su questo documento: impossibile elencare i filtri abilitati.',
                        )
                      else if (filterRows.isEmpty)
                        const _EmptyHint(
                          'Nessun filtro né soglia salvata nella strategia di questo segnale.',
                        )
                      else
                        ...filterRows.map(
                          (e) => _InfoRow(label: e.$1, value: e.$2),
                        ),
                      if (decisionRows.isNotEmpty) ...[
                        const _SectionTitle('CONTESTO BARRE DI DECISIONE'),
                        ...decisionRows.map(
                          (e) => _InfoRow(label: e.$1, value: e.$2),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
            ],
          );
        },
      );
    },
  );
}
