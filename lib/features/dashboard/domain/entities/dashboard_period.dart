enum DashboardPeriod {
  day('D', 'day', 3),
  week('W', 'week', 14),
  month('M', 'month', 45);

  final String label;
  final String apiValue;
  final int historyDays;

  const DashboardPeriod(this.label, this.apiValue, this.historyDays);
}
