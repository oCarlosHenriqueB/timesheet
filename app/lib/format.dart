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

/// Normaliza o que a pessoa digita para "HH:MM": "8" → 08:00, "830" → 08:30, "8h30" → 08:30.
/// Devolve null se não for um horário válido.
String? parseTime(String text) {
  final t = text.trim().toLowerCase().replaceAll('h', ':');
  final m = RegExp(r'^(\d{1,2})(?::?(\d{2}))?:?$').firstMatch(t);
  if (m == null) return null;
  final h = int.parse(m.group(1)!);
  final min = int.parse(m.group(2) ?? '0');
  if (h > 23 || min > 59) return null;
  return '${h.toString().padLeft(2, '0')}:${min.toString().padLeft(2, '0')}';
}

int timeToMinutes(String hhmm) => int.parse(hhmm.substring(0, 2)) * 60 + int.parse(hhmm.substring(3, 5));

String minutesToTime(int minutes) =>
    '${(minutes ~/ 60).toString().padLeft(2, '0')}:${(minutes % 60).toString().padLeft(2, '0')}';

/// Horas trabalhadas entre início e fim, descontando o intervalo; null se não fizer sentido.
double? workedHours(String? start, String? end, int breakMinutes) {
  if (start == null || end == null) return null;
  final worked = timeToMinutes(end) - timeToMinutes(start) - breakMinutes;
  if (timeToMinutes(end) <= timeToMinutes(start) || worked <= 0) return null;
  return worked / 60;
}

/// "HH:MM" da hora local.
String clockTime(DateTime t) => minutesToTime(t.hour * 60 + t.minute);
