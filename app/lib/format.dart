import 'package:intl/intl.dart';

final _date = DateFormat('dd/MM/yyyy');
final _hours = NumberFormat('#,##0.##', 'pt_BR');

String formatDate(DateTime d) => _date.format(d);

String formatNumber(double h) => _hours.format(h);

String formatHours(double h) => '${formatNumber(h)} h';

/// Aceita "1,5" ou "1.5".
double? parseHours(String text) => double.tryParse(text.trim().replaceAll(',', '.'));
