import 'package:intl/intl.dart';

String formatLastPlayed(DateTime? dateTime) {
  if (dateTime == null) {
    return '未挑戦';
  }
  return DateFormat('yyyy/MM/dd HH:mm').format(dateTime);
}

String formatPercent(double value) {
  return '${(value * 100).round()}%';
}
