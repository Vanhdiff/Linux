import '../../data/defaults/journal_defaults.dart';

bool isBuyDirection(String direction) {
  return direction.toLowerCase().contains('buy');
}

String tradeDirectionText(String direction) {
  final lower = direction.toLowerCase();
  if (lower.contains('buy')) return 'Buy';
  if (lower.contains('sell')) return 'Sell';
  return direction.trim().isEmpty ? '-' : direction.trim();
}

String tradeMetaLine(JournalOverviewTrade trade) {
  final parts = <String>[
    trade.time.trim(),
    if (trade.setup.trim().isNotEmpty) trade.setup.trim(),
    '${trade.lots.toStringAsFixed(2)} lot',
  ];
  return parts.join(' - ');
}

String moneyValue(double value) {
  final sign = value > 0
      ? '+'
      : value < 0
      ? '-'
      : '';
  return '$sign\$${value.abs().toStringAsFixed(0)}';
}

String rValue(double value) {
  return '${value > 0 ? '+' : ''}${value.toStringAsFixed(2)}R';
}

String monthTitle(DateTime value) {
  const months = [
    'January',
    'February',
    'March',
    'April',
    'May',
    'June',
    'July',
    'August',
    'September',
    'October',
    'November',
    'December',
  ];
  return '${months[value.month - 1]} ${value.year}';
}

String dayTitle(String dateKey) {
  const weekdays = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
  const months = [
    'January',
    'February',
    'March',
    'April',
    'May',
    'June',
    'July',
    'August',
    'September',
    'October',
    'November',
    'December',
  ];
  final date = DateTime.parse(dateKey);
  return '${weekdays[date.weekday - 1]}, ${months[date.month - 1]} ${date.day}';
}
