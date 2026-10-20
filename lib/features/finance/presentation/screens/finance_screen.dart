import 'package:siz/core/ui/dashboard_widgets.dart';
import 'package:siz/core/ui/ui_helpers.dart';
import 'package:siz/features/finance/domain/finance_summary.dart';
import 'package:siz/features/finance/domain/service_ticket.dart';
import 'package:siz/features/finance/presentation/finance_providers.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

class FinanceScreen extends ConsumerWidget {
  const FinanceScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final financeAsync = ref.watch(financeProvider);
    final range = ref.watch(financeRangeProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Financial Dashboard'),
        actions: [
          IconButton(
            tooltip: 'Refresh',
            icon: const Icon(Icons.refresh),
            onPressed: () => ref.read(financeProvider.notifier).loadSummary(),
          ),
        ],
      ),
      body: Column(
        children: [
          _PeriodSelector(range: range),
          Expanded(
            child: financeAsync.when(
              skipLoadingOnRefresh: true,
              skipLoadingOnReload: false,
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (err, _) => Center(
                child: TextButton(
                  onPressed: () =>
                      ref.read(financeProvider.notifier).loadSummary(),
                  child: const Text('Could not load finances. Tap to retry.'),
                ),
              ),
              data: (summary) => RefreshIndicator(
                onRefresh: () =>
                    ref.read(financeProvider.notifier).loadSummary(),
                child: _FinanceBody(summary: summary, range: range),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _PeriodSelector extends ConsumerWidget {
  const _PeriodSelector({required this.range});

  final FinanceRange range;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final notifier = ref.read(financeRangeProvider.notifier);
    final dateFormat = DateFormat('d MMM');
    final customLabel = range.period == FinancePeriod.custom
        ? range.isSingleDay
              ? dateFormat.format(range.start)
              : '${dateFormat.format(range.start)} – '
                    '${dateFormat.format(range.end.subtract(const Duration(days: 1)))}'
        : 'Custom…';

    return PeriodChips<FinancePeriod>(
      options: const [
        ('Today', FinancePeriod.today),
        ('Last 7 days', FinancePeriod.last7Days),
        ('Last 30 days', FinancePeriod.last30Days),
      ],
      selected: range.period,
      onSelected: notifier.select,
      trailing: ChoiceChip(
        avatar: const Icon(Icons.date_range, size: 16),
        label: Text(customLabel),
        selected: range.period == FinancePeriod.custom,
        onSelected: (_) async {
          final now = DateTime.now();
          final picked = await showDateRangePicker(
            context: context,
            firstDate: DateTime(now.year - 5),
            lastDate: now,
            initialDateRange: DateTimeRange(
              start: range.start,
              end: range.end.subtract(const Duration(days: 1)),
            ),
          );
          if (picked != null) notifier.selectCustom(picked);
        },
      ),
    );
  }
}

class _FinanceBody extends StatelessWidget {
  const _FinanceBody({required this.summary, required this.range});

  final FinanceSummary summary;
  final FinanceRange range;

  @override
  Widget build(BuildContext context) {
    final periodLabel = switch (range.period) {
      FinancePeriod.today => "Today's",
      FinancePeriod.last7Days => 'Last 7 days',
      FinancePeriod.last30Days => 'Last 30 days',
      FinancePeriod.custom => 'Period',
    };

    return ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.all(16),
      children: [
        MoneyHeroCard(
          label: '$periodLabel service revenue',
          amount: formatMoney(summary.grossRevenue),
          stats: [
            HeroStat(
              'Shop Net Profit',
              formatMoney(summary.shopNetRevenue),
              MoneyHeroCard.green,
            ),
            HeroStat(
              'Barber Commissions',
              formatMoney(summary.barberPayouts),
              MoneyHeroCard.blue,
            ),
            HeroStat('Tips', formatMoney(summary.tipsTotal)),
            HeroStat('Clients Served', '${summary.totalClientsServed}'),
            HeroStat('Avg. Ticket', formatMoney(summary.averageTicket)),
          ],
        ),
        const SectionHeading('Collected (incl. tips)'),
        Row(
          children: [
            Expanded(
              child: AmountCard(
                title: 'Cash',
                amount: formatMoney(summary.cashTotal),
                icon: Icons.payments_outlined,
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: AmountCard(
                title: 'Card',
                amount: formatMoney(summary.cardTotal),
                icon: Icons.credit_card,
              ),
            ),
            // Transfers are no longer offered; shown only for old tickets.
            if (summary.transferTotal > 0) ...[
              const SizedBox(width: 8),
              Expanded(
                child: AmountCard(
                  title: 'Transfer',
                  amount: formatMoney(summary.transferTotal),
                  icon: Icons.account_balance_outlined,
                ),
              ),
            ],
          ],
        ),
        const SectionHeading('Barber Payouts'),
        if (summary.payoutsByBarber.isEmpty)
          const EmptyBox('No payouts for this period.')
        else
          Card(
            child: Column(
              children: summary.payoutsByBarber.map((p) {
                return ListTile(
                  title: Text(
                    p.barberName,
                    style: const TextStyle(fontWeight: FontWeight.bold),
                  ),
                  subtitle: Text(
                    '${p.clientsServed} client(s) • '
                    'Commission ${formatMoney(p.commission)} • '
                    'Tips ${formatMoney(p.tips)}',
                    style: const TextStyle(fontSize: 12),
                  ),
                  trailing: Text(
                    formatMoney(p.totalOwed),
                    style: const TextStyle(
                      fontWeight: FontWeight.w900,
                      fontSize: 15,
                    ),
                  ),
                );
              }).toList(),
            ),
          ),
        const SectionHeading('Service Ledger'),
        if (summary.tickets.isEmpty)
          const EmptyBox(
            'No completed services in this period.\n'
            'Check out clients on the floor plan to record income.',
          )
        else
          ...summary.tickets.map((t) => _TicketTile(ticket: t, range: range)),
      ],
    );
  }
}

class _TicketTile extends StatelessWidget {
  const _TicketTile({required this.ticket, required this.range});

  final ServiceTicket ticket;
  final FinanceRange range;

  @override
  Widget build(BuildContext context) {
    final time = DateFormat(range.isSingleDay ? 'h:mm a' : 'd MMM, h:mm a')
        .format(ticket.timestamp);
    final (bg, fg, icon) = paymentStyle(ticket.paymentMethod);

    return LedgerTile(
      icon: icon,
      iconBackground: bg,
      iconColor: fg,
      title: ticket.clientName,
      subtitle:
          '${ticket.serviceNames.join(", ")} • Chair #${ticket.chairNumber} • $time',
      amount: formatMoney(ticket.totalPrice + ticket.tip),
      note: ticket.tip > 0
          ? 'Tip ${formatMoney(ticket.tip)}'
          : 'Shop ${formatMoney(ticket.shopCut)}',
    );
  }
}

/// Badge colors and icon of a payment method in ledgers.
(Color, Color, IconData) paymentStyle(PaymentMethod method) => switch (method) {
  PaymentMethod.cash => (
    const Color(0xFFDCFCE7),
    const Color(0xFF166534),
    Icons.attach_money,
  ),
  PaymentMethod.card => (
    const Color(0xFFDBEAFE),
    const Color(0xFF1E40AF),
    Icons.credit_card,
  ),
  PaymentMethod.transfer => (
    const Color(0xFFF3E8FF),
    const Color(0xFF6B21A8),
    Icons.account_balance_outlined,
  ),
};
