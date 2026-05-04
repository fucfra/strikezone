import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/theme/app_theme.dart';
import '../../core/trading/fx_pair_utils.dart';
import '../../data/models/signal_model.dart';

typedef RealSignalEditSubmit = Future<String?> Function({
  required double entryPrice,
  required double stopLoss,
  required bool executionConfirmed,
  required bool clearExit,
  double? exitPrice,
  DateTime? exitTime,
});

double? _parsePrice(String raw) {
  final t = raw.trim().replaceAll(',', '.');
  if (t.isEmpty) return null;
  return double.tryParse(t);
}

int _decimalsForPair(String pair) {
  final p = normalizedPairEpic(pair);
  if (p.length == 6 && p.substring(3, 6) == 'JPY') return 3;
  return 5;
}

/// Modifica manuale prezzo ingresso, SL, chiusura e conferma esecuzione (solo segnali live).
Future<void> showRealSignalEditBottomSheet(
  BuildContext context,
  SignalModel signal, {
  required RealSignalEditSubmit onSubmit,
}) async {
  if (signal.documentSource != SignalFirestoreCollection.live) {
    return;
  }

  await showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    backgroundColor: AppTheme.inputFillColor,
    builder: (ctx) {
      return Padding(
        padding: EdgeInsets.only(
          bottom: MediaQuery.viewInsetsOf(ctx).bottom,
        ),
        child: _RealSignalEditBody(signal: signal, onSubmit: onSubmit),
      );
    },
  );
}

class _RealSignalEditBody extends StatefulWidget {
  const _RealSignalEditBody({
    required this.signal,
    required this.onSubmit,
  });

  final SignalModel signal;
  final RealSignalEditSubmit onSubmit;

  @override
  State<_RealSignalEditBody> createState() => _RealSignalEditBodyState();
}

class _RealSignalEditBodyState extends State<_RealSignalEditBody> {
  late final TextEditingController _entryCtrl;
  late final TextEditingController _slCtrl;
  late final TextEditingController _exitCtrl;
  late bool _executionConfirmed;
  bool _saving = false;
  String? _error;

  SignalModel get s => widget.signal;

  @override
  void initState() {
    super.initState();
    final dec = _decimalsForPair(s.pair);
    String fmt(double v) => v.toStringAsFixed(dec);
    _entryCtrl = TextEditingController(text: fmt(s.entryPrice));
    _slCtrl = TextEditingController(text: fmt(s.stopLoss));
    _exitCtrl = TextEditingController(
      text: s.exitPrice != null ? fmt(s.exitPrice!) : '',
    );
    _executionConfirmed = s.executionConfirmed;
  }

  @override
  void dispose() {
    _entryCtrl.dispose();
    _slCtrl.dispose();
    _exitCtrl.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final entry = _parsePrice(_entryCtrl.text);
    final sl = _parsePrice(_slCtrl.text);
    if (entry == null || !entry.isFinite) {
      setState(() => _error = 'Prezzo di apertura non valido.');
      return;
    }
    if (sl == null || !sl.isFinite) {
      setState(() => _error = 'Stop loss non valido.');
      return;
    }

    final exitRaw = _exitCtrl.text.trim();
    final parsedExit = exitRaw.isEmpty ? null : _parsePrice(exitRaw);
    if (parsedExit != null && !parsedExit.isFinite) {
      setState(() => _error = 'Prezzo di chiusura non valido.');
      return;
    }

    final hadExit = s.exitPrice != null || s.exitTime != null;
    final clearExit = parsedExit == null && hadExit;

    double? exitPriceArg;
    DateTime? exitTimeArg;
    if (!clearExit && parsedExit != null) {
      exitPriceArg = parsedExit;
      final orig = s.exitPrice;
      final closingChanged =
          orig == null || (orig - parsedExit).abs() > 1e-8;
      exitTimeArg =
          closingChanged ? DateTime.now() : (s.exitTime ?? DateTime.now());
    }

    setState(() {
      _error = null;
      _saving = true;
    });

    final dec = _decimalsForPair(s.pair);
    final err = await widget.onSubmit(
      entryPrice: double.parse(entry.toStringAsFixed(dec)),
      stopLoss: double.parse(sl.toStringAsFixed(dec)),
      executionConfirmed: _executionConfirmed,
      clearExit: clearExit,
      exitPrice: exitPriceArg,
      exitTime: exitTimeArg,
    );

    if (!mounted) return;
    setState(() => _saving = false);

    if (err != null) {
      setState(() => _error = err);
      return;
    }
    if (mounted) Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(
          AppSpacing.pageH,
          AppSpacing.s2,
          AppSpacing.pageH,
          AppSpacing.s4,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              '${s.pair} · ${s.type == SignalType.buy ? 'BUY' : 'SELL'}',
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w800,
                    color: AppTheme.primaryText,
                  ),
            ),
            const SizedBox(height: AppSpacing.s1),
            Text(
              'Modifica dati esecuzione reale',
              style: TextStyle(
                fontSize: 12,
                color: AppTheme.secondaryText.withValues(alpha: 0.9),
              ),
            ),
            const SizedBox(height: AppSpacing.s4),
            TextField(
              controller: _entryCtrl,
              keyboardType: const TextInputType.numberWithOptions(
                decimal: true,
                signed: false,
              ),
              inputFormatters: [
                FilteringTextInputFormatter.allow(RegExp(r'[0-9.,]')),
              ],
              style: const TextStyle(
                color: AppTheme.primaryText,
                fontFamily: 'monospace',
              ),
              decoration: const InputDecoration(
                labelText: 'Prezzo di apertura',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: AppSpacing.s3),
            TextField(
              controller: _slCtrl,
              keyboardType: const TextInputType.numberWithOptions(
                decimal: true,
                signed: false,
              ),
              inputFormatters: [
                FilteringTextInputFormatter.allow(RegExp(r'[0-9.,]')),
              ],
              style: const TextStyle(
                color: AppTheme.primaryText,
                fontFamily: 'monospace',
              ),
              decoration: const InputDecoration(
                labelText: 'Stop loss',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: AppSpacing.s3),
            TextField(
              controller: _exitCtrl,
              keyboardType: const TextInputType.numberWithOptions(
                decimal: true,
                signed: false,
              ),
              inputFormatters: [
                FilteringTextInputFormatter.allow(RegExp(r'[0-9.,]')),
              ],
              style: const TextStyle(
                color: AppTheme.primaryText,
                fontFamily: 'monospace',
              ),
              decoration: InputDecoration(
                labelText: 'Prezzo di chiusura',
                hintText: s.isClosed ? null : 'Vuoto se posizione ancora aperta',
                border: const OutlineInputBorder(),
                helperText:
                    'Se modifichi la chiusura, la data/ora di chiusura viene aggiornata adesso.',
                helperMaxLines: 2,
              ),
            ),
            const SizedBox(height: AppSpacing.s3),
            SwitchListTile(
              value: _executionConfirmed,
              onChanged: _saving
                  ? null
                  : (v) => setState(() => _executionConfirmed = v),
              title: const Text(
                'Conferma esecuzione ordine reale',
                style: TextStyle(
                  fontWeight: FontWeight.w600,
                  color: AppTheme.primaryText,
                ),
              ),
              subtitle: Text(
                'Indica che l’ordine è stato effettivamente eseguito sul broker.',
                style: TextStyle(
                  fontSize: 11,
                  color: AppTheme.secondaryText.withValues(alpha: 0.9),
                ),
              ),
              activeThumbColor: Colors.white,
              activeTrackColor: AppTheme.accentGreen,
            ),
            if (_error != null) ...[
              const SizedBox(height: AppSpacing.s2),
              Text(
                _error!,
                style: const TextStyle(
                  color: AppTheme.accentRed,
                  fontWeight: FontWeight.w600,
                  fontSize: 12,
                ),
              ),
            ],
            const SizedBox(height: AppSpacing.s4),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: _saving ? null : () => Navigator.pop(context),
                    child: const Text('Annulla'),
                  ),
                ),
                const SizedBox(width: AppSpacing.s3),
                Expanded(
                  child: ElevatedButton(
                    onPressed: _saving ? null : _save,
                    child: _saving
                        ? const SizedBox(
                            width: 22,
                            height: 22,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Text('Salva'),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
