import 'package:fluent_ui/fluent_ui.dart';

import '../../../../app/i18n/app_localization.dart';
import '../../../../app/theme/app_colors.dart';
import '../../data/defaults/news_fallback_data.dart';

class NewsEventsPanel extends StatelessWidget {
  final List<NewsEventData> events;
  final String title;

  const NewsEventsPanel({
    super.key,
    required this.events,
    this.title = 'Today',
  });

  @override
  Widget build(BuildContext context) {
    final strings = AppLocalization.of(context);
    return Container(
      padding: EdgeInsets.all(16),
      decoration: _panelDecoration(),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              _NavButton(FluentIcons.chevron_left),
              SizedBox(width: 6),
              _NavButton(FluentIcons.chevron_right),
              SizedBox(width: 12),
              Text(
                title,
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w800,
                  color: AppColors.textPrimary,
                ),
              ),
              Spacer(),
              _TodayPill(),
            ],
          ),
          SizedBox(height: 14),
          _EventHeader(),
          SizedBox(height: 8),
          if (events.isEmpty)
            _EmptyEventsMessage(
              strings.text('No economic events for this day.'),
            )
          else
            ...events.map((event) => _EventRow(event)),
        ],
      ),
    );
  }
}

class UpcomingEventsPanel extends StatelessWidget {
  final List<NewsEventData> events;

  const UpcomingEventsPanel({super.key, required this.events});

  @override
  Widget build(BuildContext context) {
    final strings = AppLocalization.of(context);
    return Container(
      padding: EdgeInsets.all(16),
      decoration: _panelDecoration(),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            strings.text("Today's Events"),
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.w800,
              color: AppColors.textPrimary,
            ),
          ),
          SizedBox(height: 14),
          _EventHeader(compact: true),
          SizedBox(height: 8),
          if (events.isEmpty)
            _EmptyEventsMessage(strings.text('No economic events for today.'))
          else
            ...events.map((event) => _EventRow(event, compact: true)),
        ],
      ),
    );
  }
}

class CurrencyWatchlistPanel extends StatelessWidget {
  final List<String> currencies;

  const CurrencyWatchlistPanel({super.key, required this.currencies});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: EdgeInsets.all(16),
      decoration: _panelDecoration(),
      child: Row(
        children: [
          Text(
            'Currencies',
            style: TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.w800,
              color: AppColors.textPrimary,
            ),
          ),
          SizedBox(width: 12),
          Text(
            '18 from watchlist',
            style: TextStyle(
              color: AppColors.textSecondary,
              fontSize: 12,
              fontWeight: FontWeight.w700,
            ),
          ),
          Spacer(),
          Text(
            'Clear',
            style: TextStyle(color: AppColors.textSecondary, fontSize: 12),
          ),
          SizedBox(width: 16),
          ...currencies.map((currency) => _CurrencyChip(currency)),
        ],
      ),
    );
  }
}

class _EventHeader extends StatelessWidget {
  final bool compact;

  const _EventHeader({this.compact = false});

  @override
  Widget build(BuildContext context) {
    final strings = AppLocalization.of(context);
    return Row(
      children: [
        SizedBox(
          width: compact ? 58 : 70,
          child: _HeaderText(strings.text('Time')),
        ),
        SizedBox(
          width: compact ? 68 : 74,
          child: _HeaderText(strings.text('Currency')),
        ),
        SizedBox(
          width: compact ? 44 : 54,
          child: _HeaderText(strings.text('Impact')),
        ),
        Expanded(
          flex: compact ? 4 : 5,
          child: _HeaderText(strings.text('Event')),
        ),
        if (!compact) ...[
          SizedBox(width: 70, child: _HeaderText(strings.text('Actual'))),
          SizedBox(width: 72, child: _HeaderText(strings.text('Forecast'))),
          SizedBox(width: 72, child: _HeaderText(strings.text('Previous'))),
        ],
      ],
    );
  }
}

class _EventRow extends StatelessWidget {
  final NewsEventData event;
  final bool compact;

  const _EventRow(this.event, {this.compact = false});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: EdgeInsets.symmetric(vertical: 8),
      decoration: BoxDecoration(
        border: Border(bottom: BorderSide(color: AppColors.border)),
      ),
      child: Row(
        children: [
          SizedBox(width: compact ? 58 : 70, child: _TimeText(event.time)),
          SizedBox(
            width: compact ? 68 : 74,
            child: _CurrencyBadge(event.currency),
          ),
          SizedBox(
            width: compact ? 44 : 54,
            child: Align(
              alignment: Alignment.centerLeft,
              child: _ImpactDot(event.impactColor),
            ),
          ),
          Expanded(
            flex: compact ? 4 : 5,
            child: Row(
              children: [
                Icon(
                  _eventIcon(event.event),
                  size: 11,
                  color: AppColors.textSecondary.withValues(alpha: 0.45),
                ),
                SizedBox(width: 7),
                Expanded(child: _CellText(event.event, strong: true)),
              ],
            ),
          ),
          if (!compact) ...[
            SizedBox(
              width: 70,
              child: _CellText(
                event.actual,
                strong: true,
                color: _actualColor(event.actual, event.forecast),
              ),
            ),
            SizedBox(width: 72, child: _CellText(event.forecast)),
            SizedBox(width: 72, child: _CellText(event.previous)),
          ],
        ],
      ),
    );
  }

  IconData _eventIcon(String event) {
    final normalized = event.toLowerCase();
    if (normalized.contains('auction') || normalized.contains('bond')) {
      return FluentIcons.bank;
    }
    if (normalized.contains('oil') || normalized.contains('inventor')) {
      return FluentIcons.line_chart;
    }
    return FluentIcons.bank;
  }

  Color? _actualColor(String actual, String forecast) {
    if (actual == '-') return null;
    final actualValue = _numericValue(actual);
    final forecastValue = _numericValue(forecast);
    if (actualValue != null && forecastValue != null) {
      if (actualValue > forecastValue) return AppColors.success;
      if (actualValue < forecastValue) return AppColors.danger;
    }
    if (actual.startsWith('-')) return AppColors.danger;
    return AppColors.success;
  }

  double? _numericValue(String value) {
    final match = RegExp(r'-?\d+(?:\.\d+)?').firstMatch(value);
    if (match == null) return null;
    final number = double.tryParse(match.group(0)!);
    if (number == null) return null;
    final normalized = value.toUpperCase();
    if (normalized.contains('B')) return number * 1000000000;
    if (normalized.contains('M')) return number * 1000000;
    if (normalized.contains('K')) return number * 1000;
    return number;
  }
}

class _TimeText extends StatelessWidget {
  final String text;

  const _TimeText(this.text);

  @override
  Widget build(BuildContext context) {
    return Text(
      '+ $text',
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      style: TextStyle(
        fontSize: 11,
        fontWeight: FontWeight.w700,
        color: AppColors.textPrimary,
      ),
    );
  }
}

class _CurrencyBadge extends StatelessWidget {
  final String currency;

  const _CurrencyBadge(this.currency);

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Container(
          width: 13,
          height: 13,
          decoration: BoxDecoration(
            color: _currencyColor(currency),
            shape: BoxShape.circle,
            border: Border.all(color: AppColors.surface, width: 1.5),
          ),
        ),
        SizedBox(width: 6),
        Expanded(child: _CellText(currency, strong: true)),
      ],
    );
  }

  Color _currencyColor(String value) {
    return switch (value) {
      'USD' => AppColors.danger,
      'EUR' => AppColors.primary,
      'GBP' => AppColors.accent,
      'JPY' => AppColors.warning,
      'AUD' => AppColors.success,
      'CAD' => Color(0xFFE45858),
      'CHF' => Color(0xFFD94040),
      'NZD' => Color(0xFF2AA876),
      _ => AppColors.textSecondary,
    };
  }
}

class _ImpactDot extends StatelessWidget {
  final Color color;

  const _ImpactDot(this.color);

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 8,
      height: 8,
      decoration: BoxDecoration(
        color: color,
        shape: BoxShape.circle,
        boxShadow: [
          BoxShadow(
            color: color.withValues(alpha: 0.22),
            blurRadius: 8,
            spreadRadius: 1,
          ),
        ],
      ),
    );
  }
}

class _EmptyEventsMessage extends StatelessWidget {
  final String message;

  const _EmptyEventsMessage(this.message);

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: EdgeInsets.symmetric(vertical: 18),
      alignment: Alignment.centerLeft,
      decoration: BoxDecoration(
        border: Border(bottom: BorderSide(color: AppColors.border)),
      ),
      child: Text(
        message,
        style: TextStyle(
          color: AppColors.textSecondary,
          fontSize: 12,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}

class _CurrencyChip extends StatelessWidget {
  final String currency;

  const _CurrencyChip(this.currency);

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: EdgeInsets.only(left: 10),
      padding: EdgeInsets.symmetric(horizontal: 16, vertical: 9),
      decoration: BoxDecoration(
        color: currency == 'USD' ? AppColors.primarySoft : AppColors.surface,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
          color: currency == 'USD' ? AppColors.primary : AppColors.border,
        ),
      ),
      child: Row(
        children: [
          Text(
            currency,
            style: TextStyle(
              fontWeight: FontWeight.w800,
              color: currency == 'USD'
                  ? AppColors.primary
                  : AppColors.textPrimary,
            ),
          ),
          SizedBox(width: 8),
          Icon(FluentIcons.cancel, size: 10, color: AppColors.textSecondary),
        ],
      ),
    );
  }
}

class _HeaderText extends StatelessWidget {
  final String text;

  const _HeaderText(this.text);

  @override
  Widget build(BuildContext context) {
    return Text(
      text,
      style: TextStyle(
        color: AppColors.textSecondary,
        fontSize: 10,
        fontWeight: FontWeight.w800,
      ),
    );
  }
}

class _CellText extends StatelessWidget {
  final String text;
  final bool strong;
  final Color? color;

  const _CellText(this.text, {this.strong = false, this.color});

  @override
  Widget build(BuildContext context) {
    return Text(
      text,
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      style: TextStyle(
        fontSize: 11,
        fontWeight: strong ? FontWeight.w800 : FontWeight.w600,
        color: color ?? AppColors.textPrimary,
      ),
    );
  }
}

class _TodayPill extends StatelessWidget {
  const _TodayPill();

  @override
  Widget build(BuildContext context) {
    final strings = AppLocalization.of(context);
    return Container(
      padding: EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: AppColors.shellBg,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: AppColors.border),
      ),
      child: Text(
        strings.text('Today'),
        style: TextStyle(
          color: AppColors.textSecondary,
          fontSize: 10,
          fontWeight: FontWeight.w800,
        ),
      ),
    );
  }
}

class _NavButton extends StatelessWidget {
  final IconData icon;

  const _NavButton(this.icon);

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 26,
      height: 26,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: AppColors.shellBg,
        borderRadius: BorderRadius.circular(7),
        border: Border.all(color: AppColors.border),
      ),
      child: Icon(icon, size: 12, color: AppColors.textSecondary),
    );
  }
}

BoxDecoration _panelDecoration() {
  return BoxDecoration(
    color: AppColors.surface.withValues(alpha: 0.96),
    borderRadius: BorderRadius.circular(12),
    border: Border.all(color: AppColors.border),
    boxShadow: [
      BoxShadow(
        color: AppColors.primary.withValues(alpha: 0.04),
        blurRadius: 18,
        offset: Offset(0, 10),
      ),
    ],
  );
}
