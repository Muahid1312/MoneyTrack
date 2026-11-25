import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../../core/constants/currency.dart';
import '../../../core/utils/money.dart';
import '../domain/managed_fund.dart';

String normalizeFundDigits(String input) => input
    .replaceAllMapped(RegExp('[۰-۹٠-٩]'), (m) {
      final unit = m[0]!.codeUnitAt(0);
      return (unit - (unit >= 0x6f0 ? 0x6f0 : 0x660)).toString();
    })
    .replaceAll('٫', '.')
    .replaceAll('٬', ',');

int fundAmount(String input, AppCurrency currency, {bool zeroAllowed = false}) {
  final amount = Money.parseMinor(normalizeFundDigits(input), currency);
  requireManaged(
    amount != null && (zeroAllowed || amount > 0),
    'Enter a valid amount in ${currency.code}.',
  );
  return amount!;
}

class FundFields {
  final _values = <String, TextEditingController>{};

  TextEditingController field(String label, [String value = '']) =>
      _values.putIfAbsent(label, () => TextEditingController(text: value));
  String value(String key) => field(key).text.trim();

  void dispose() {
    for (final controller in _values.values) {
      controller.dispose();
    }
  }
}

class FundInput extends StatelessWidget {
  const FundInput(
    this.label,
    this.controller, {
    super.key,
    this.number = false,
    this.maxLength,
  });
  final String label;
  final TextEditingController controller;
  final bool number;
  final int? maxLength;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 12),
    child: TextField(
      controller: controller,
      maxLength: maxLength,
      keyboardType: number
          ? const TextInputType.numberWithOptions(decimal: true)
          : TextInputType.text,
      textCapitalization: number
          ? TextCapitalization.none
          : TextCapitalization.sentences,
      decoration: InputDecoration(labelText: label, counterText: ''),
    ),
  );
}

class FundDateField extends StatelessWidget {
  const FundDateField({
    super.key,
    this.label = 'Date and time',
    required this.value,
    required this.onChange,
    this.includeTime = true,
  });
  final String label;
  final DateTime? value;
  final ValueChanged<DateTime> onChange;
  final bool includeTime;

  @override
  Widget build(BuildContext context) => ListTile(
    contentPadding: EdgeInsets.zero,
    leading: const Icon(Icons.calendar_today_outlined),
    title: Text(label),
    subtitle: value == null
        ? null
        : Text(
            includeTime
                ? DateFormat.yMMMd().add_jm().format(value!)
                : DateFormat.yMMMd().format(value!),
          ),
    onTap: () async {
      final base = value ?? DateTime.now();
      final date = await showDatePicker(
        context: context,
        initialDate: base,
        firstDate: DateTime(1900),
        lastDate: DateTime(2200),
      );
      if (date == null || !context.mounted) return;
      if (!includeTime) {
        onChange(date);
        return;
      }
      final time = await showTimePicker(
        context: context,
        initialTime: TimeOfDay.fromDateTime(base),
      );
      if (time == null || !context.mounted) return;
      onChange(
        DateTime(date.year, date.month, date.day, time.hour, time.minute),
      );
    },
  );
}

class FundForm extends StatefulWidget {
  const FundForm({
    super.key,
    required this.title,
    required this.submit,
    required this.children,
    this.button = 'Save',
  });
  final String title, button;
  final Future<int> Function() submit;
  final List<Widget> children;

  @override
  State<FundForm> createState() => _FundFormState();
}

class _FundFormState extends State<FundForm> {
  bool _busy = false;
  String? _error;

  Future<void> _save() async {
    if (_busy) return;
    FocusManager.instance.primaryFocus?.unfocus();
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final id = await widget.submit();
      if (mounted) Navigator.pop(context, id);
    } on FundRule catch (error) {
      if (mounted) setState(() => _error = error.message);
    } on Object {
      if (mounted) {
        setState(
          () => _error = 'Could not save. Unlock MoneyTrack and try again.',
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => PopScope(
    canPop: !_busy,
    child: Scaffold(
      appBar: AppBar(title: Text(widget.title)),
      body: Column(
        children: [
          Expanded(
            child: ListView(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
              children: [
                IgnorePointer(
                  ignoring: _busy,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: widget.children,
                  ),
                ),
              ],
            ),
          ),
          SafeArea(
            top: false,
            minimum: const EdgeInsets.fromLTRB(16, 0, 16, 12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (_busy) const LinearProgressIndicator(),
                if (_error != null)
                  Semantics(
                    liveRegion: true,
                    child: Text(
                      _error!,
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.error,
                      ),
                    ),
                  ),
                FilledButton(
                  onPressed: _busy ? null : _save,
                  child: Text(widget.button),
                ),
              ],
            ),
          ),
        ],
      ),
    ),
  );
}
