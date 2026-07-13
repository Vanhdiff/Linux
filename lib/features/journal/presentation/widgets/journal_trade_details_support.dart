String journalTradeDirectionLabel(String? direction) {
  if (direction == null || direction == '-') return '-';
  final lower = direction.toLowerCase();
  if (lower.contains('buy')) return 'Buy';
  if (lower.contains('sell')) return 'Sell';
  return direction.trim().isEmpty ? '-' : direction.trim();
}

String journalTradeMoney(double value) {
  final sign = value < 0 ? '-' : '';
  return '$sign\$${value.abs().toStringAsFixed(0)}';
}

String journalTradeNumber(double value) {
  final rounded = value.roundToDouble();
  return value == rounded ? value.toStringAsFixed(0) : value.toStringAsFixed(2);
}

String journalTradePrice(double? value) {
  if (value == null || value == 0) return '-';
  return value.toStringAsFixed(value.abs() >= 100 ? 2 : 5);
}

String journalTradeR(double value) {
  return '${value > 0 ? '+' : ''}${value.toStringAsFixed(2)}R';
}

String journalTradeRiskPercentLabel(
  double? riskAmount,
  double dayStartBalance,
) {
  if (riskAmount == null || riskAmount <= 0 || dayStartBalance <= 0) {
    return '-';
  }
  final percent = riskAmount / dayStartBalance * 100;
  return '${percent.toStringAsFixed(percent >= 10 ? 1 : 2)}%';
}

String journalTradeDuration(DateTime? openedAt, DateTime? closedAt) {
  if (openedAt == null || closedAt == null) return '-';
  final duration = closedAt.difference(openedAt).abs();
  final hours = duration.inHours;
  final minutes = duration.inMinutes.remainder(60);
  if (hours == 0) return '$minutes min';
  return '$hours hr ${minutes.toString().padLeft(2, '0')} min';
}
