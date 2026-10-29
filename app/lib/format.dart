import 'package:intl/intl.dart';

final _date = DateFormat('dd/MM/yyyy');
final _hours = NumberFormat('#,##0.##', 'pt_BR');

String formatDate(DateTime d) => _date.format(d);

String formatNumber(double h) => _hours.format(h);

String formatHours(double h) => '${formatNumber(h)} h';

/// Cronômetro: "0:05:09", "12:00:00".
String formatDuration(Duration d) {
  String two(int n) => n.toString().padLeft(2, '0');
  return '${d.inHours}:${two(d.inMinutes % 60)}:${two(d.inSeconds % 60)}';
}

/// Aceita "1,5" ou "1.5".
double? parseHours(String text) => double.tryParse(text.trim().replaceAll(',', '.'));
