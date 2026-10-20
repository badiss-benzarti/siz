import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../../../core/ui/ui_helpers.dart';
import '../../data/barber_invites.dart';
import '../../domain/barber.dart';
import '../barber_providers.dart';

/// On a roster card: "Linked to the app" (with any name change the barber
/// asked for), or a button to invite the barber.
class BarberAppLink extends ConsumerWidget {
  const BarberAppLink({super.key, required this.barber});

  final Barber barber;

  static const _green = Color(0xFF166534);

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final status = _status(ref);
    if (barber.requestedName == null) return status;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        status,
        const SizedBox(height: 6),
        _NameRequest(barber: barber),
      ],
    );
  }

  Widget _status(WidgetRef ref) {
    if (barber.isLinkedToApp) {
      return const Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.phone_iphone, size: 14, color: _green),
          SizedBox(width: 4),
          Text(
            'Linked to the app',
            style: TextStyle(
              color: _green,
              fontSize: 12,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      );
    }
    return TextButton.icon(
      style: TextButton.styleFrom(
        foregroundColor: Colors.black,
        padding: EdgeInsets.zero,
        minimumSize: const Size(0, 30),
        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
        visualDensity: VisualDensity.compact,
      ),
      onPressed: () => _invite(ref.context, ref),
      icon: const Icon(Icons.send_to_mobile_outlined, size: 16),
      label: const Text(
        'Invite to the app',
        style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700),
      ),
    );
  }

  Future<void> _invite(BuildContext context, WidgetRef ref) async {
    BarberInvite? invite;
    final ok = await runAction(context, () async {
      invite = await ref.read(barberInvitesProvider).create(barber.id);
    });
    if (!ok || invite == null || !context.mounted) return;
    await showDialog<void>(
      context: context,
      builder: (_) => _InviteDialog(barberName: barber.name, invite: invite!),
    );
  }
}

/// "Sami asks to be called Samy": the owner accepts or declines.
class _NameRequest extends ConsumerWidget {
  const _NameRequest({required this.barber});

  final Barber barber;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final wanted = barber.requestedName!;

    Future<void> answer({required bool accept}) => runAction(
      context,
      () async {
        await ref
            .read(barberRepositoryProvider)
            .applyNameAnswer(barber.id, acceptedName: accept ? wanted : null);
        ref.invalidate(barberListProvider);
      },
      successMessage: accept
          ? '${barber.name} is now called $wanted.'
          : 'Name change declined.',
    );

    return Container(
      padding: const EdgeInsets.fromLTRB(10, 8, 6, 4),
      decoration: BoxDecoration(
        color: const Color(0xFFFEF3C7),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Asks to be called "$wanted"',
            style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700),
          ),
          Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              TextButton(
                style: TextButton.styleFrom(
                  foregroundColor: Colors.black,
                  visualDensity: VisualDensity.compact,
                ),
                onPressed: () => answer(accept: false),
                child: const Text('Decline'),
              ),
              FilledButton(
                style: FilledButton.styleFrom(
                  backgroundColor: Colors.black,
                  visualDensity: VisualDensity.compact,
                ),
                onPressed: () => answer(accept: true),
                child: const Text('Accept'),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _InviteDialog extends StatelessWidget {
  const _InviteDialog({required this.barberName, required this.invite});

  final String barberName;
  final BarberInvite invite;

  @override
  Widget build(BuildContext context) {
    final code = invite.code;
    final readable = '${code.substring(0, 4)} ${code.substring(4)}';
    return AlertDialog(
      title: Text('Invite $barberName'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            'Give this code to $barberName. In the app: Who are you? → '
            'Barber → create an account → enter the code.',
            style: const TextStyle(fontSize: 13),
          ),
          const SizedBox(height: 16),
          Container(
            padding: const EdgeInsets.symmetric(vertical: 14),
            decoration: BoxDecoration(
              color: const Color(0xFFF3F4F6),
              borderRadius: BorderRadius.circular(12),
            ),
            child: SelectableText(
              readable,
              textAlign: TextAlign.center,
              style: const TextStyle(
                fontSize: 28,
                fontWeight: FontWeight.w900,
                letterSpacing: 4,
              ),
            ),
          ),
          const SizedBox(height: 10),
          Text(
            'Works once, until '
            '${DateFormat('d MMM, HH:mm').format(invite.expiresAt)}. '
            'A new code replaces this one.',
            textAlign: TextAlign.center,
            style: const TextStyle(fontSize: 12, color: Colors.grey),
          ),
        ],
      ),
      actions: [
        TextButton.icon(
          onPressed: () async {
            await Clipboard.setData(ClipboardData(text: code));
            if (context.mounted) showSnack(context, 'Code copied.');
          },
          icon: const Icon(Icons.copy, size: 18),
          label: const Text('Copy'),
        ),
        FilledButton(
          style: FilledButton.styleFrom(backgroundColor: Colors.black),
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Done'),
        ),
      ],
    );
  }
}
