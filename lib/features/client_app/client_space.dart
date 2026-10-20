import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../core/errors/app_exception.dart';
import '../../core/ui/dashboard_widgets.dart';
import '../../core/ui/room_navigation_bar.dart';
import '../../core/ui/ui_helpers.dart';
import '../welcome/entry_role.dart';
import 'client_actions.dart';
import 'client_activity.dart';
import 'client_directory.dart';
import 'client_salon_page.dart';
import 'client_salons_screen.dart';
import 'client_session.dart';

const _muted = Color(0xFF6B7280);

/// The client app: the list of salons in the middle, the client's line and
/// bookings, the latest cuts in Social, favorite salons, and the account in
/// Profile. Browsing works without an account.
class ClientSpace extends StatefulWidget {
  const ClientSpace({super.key});

  @override
  State<ClientSpace> createState() => _ClientSpaceState();
}

class _ClientSpaceState extends State<ClientSpace> {
  static const _salonsTab = 2;

  int _tab = _salonsTab;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: IndexedStack(
        index: _tab,
        children: const [
          _ProfileTab(),
          _BookingsTab(),
          ClientSalonsScreen(),
          _SocialTab(),
          _FavoritesTab(),
        ],
      ),
      bottomNavigationBar: RoomNavigationBar(
        items: const [
          RoomNavItem(Icons.person_outline, Icons.person, 'Profile'),
          RoomNavItem(Icons.event_note_outlined, Icons.event_note, 'Bookings'),
          RoomNavItem(Icons.storefront_outlined, Icons.storefront, 'Salons'),
          RoomNavItem(
            Icons.photo_library_outlined,
            Icons.photo_library,
            'Social',
          ),
          RoomNavItem(Icons.favorite_border, Icons.favorite, 'Favorites'),
        ],
        currentIndex: _tab,
        onTap: (i) => setState(() => _tab = i),
      ),
    );
  }
}

/// Shown on tabs that need an account.
class _SignInFirst extends StatelessWidget {
  const _SignInFirst(this.message);

  final String message;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.all(16),
    child: EmptyBox('$message\nCreate a free account in Profile.'),
  );
}

// -----------------------------------------------------------------------------
// Bookings: my place in a line, my booked times
// -----------------------------------------------------------------------------

class _BookingsTab extends ConsumerWidget {
  const _BookingsTab();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final user = ref.watch(clientSessionProvider.select((s) => s.user));
    final spot = ref.watch(myQueueSpotProvider);
    final bookings = ref.watch(myBookingsProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('My Bookings'),
        actions: [
          IconButton(
            tooltip: 'Refresh',
            icon: const Icon(Icons.refresh),
            onPressed: () => dataChanged(ref),
          ),
        ],
      ),
      body: user == null
          ? const _SignInFirst(
              'Join a line or book a barber from a salon page.',
            )
          : RefreshIndicator(
              onRefresh: () async => dataChanged(ref),
              child: ListView(
                physics: const AlwaysScrollableScrollPhysics(),
                padding: const EdgeInsets.all(16),
                children: [
                  const SectionHeading('In line'),
                  switch (spot) {
                    AsyncData(value: final s?) => Card(
                      child: ListTile(
                        leading: CircleAvatar(
                          backgroundColor: Colors.black,
                          child: Text(
                            '#${s.position}',
                            style: const TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.w900,
                            ),
                          ),
                        ),
                        title: Text(
                          s.shopName,
                          style: const TextStyle(fontWeight: FontWeight.w800),
                        ),
                        subtitle: Text(
                          s.position == 1
                              ? 'You are next!'
                              : '${s.position - 1} before you · since '
                                    '${DateFormat('HH:mm').format(s.joinedAt)}',
                        ),
                        trailing: TextButton(
                          onPressed: () async {
                            await runAction(
                              context,
                              () => ref
                                  .read(clientActivityProvider)
                                  .leaveQueue(user.id),
                              successMessage: 'You left the line.',
                            );
                            dataChanged(ref);
                          },
                          child: const Text('Leave'),
                        ),
                        onTap: () => openSalon(context, s.shopId),
                      ),
                    ),
                    AsyncData() => const EmptyBox(
                      'You are not in a line. Open a salon and tap '
                      '"Join the line".',
                    ),
                    AsyncError(:final error) => EmptyBox(describeError(error)),
                    _ => const EmptyBox('Loading…'),
                  },
                  const SectionHeading('Booked times'),
                  switch (bookings) {
                    AsyncData(:final value) when value.isEmpty =>
                      const EmptyBox(
                        'No bookings yet. Open a salon and tap "Book".',
                      ),
                    AsyncData(:final value) => Column(
                      children: [
                        for (final b in value.reversed)
                          _MyBookingCard(booking: b, clientId: user.id),
                      ],
                    ),
                    AsyncError(:final error) => EmptyBox(describeError(error)),
                    _ => const EmptyBox('Loading…'),
                  },
                ],
              ),
            ),
    );
  }
}

class _MyBookingCard extends ConsumerWidget {
  const _MyBookingCard({required this.booking, required this.clientId});

  final Booking booking;
  final String clientId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final b = booking;
    final upcoming = b.isActive && b.startsAt.isAfter(DateTime.now());
    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      child: ListTile(
        leading: BookingStatusIcon(b.status),
        title: Text(
          '${b.serviceName} · ${b.shopName}',
          style: const TextStyle(fontWeight: FontWeight.w800),
        ),
        subtitle: Text(
          '${DateFormat('EEE d MMM, HH:mm').format(b.startsAt)}'
          '${b.barberName == null ? '' : ' with ${b.barberName}'}\n'
          '${b.status.label}',
        ),
        isThreeLine: true,
        trailing: upcoming
            ? TextButton(
                onPressed: () async {
                  await runAction(
                    context,
                    () => ref
                        .read(clientActivityProvider)
                        .cancelBooking(b.id, clientId),
                    successMessage: 'Booking cancelled.',
                  );
                  dataChanged(ref);
                },
                child: const Text('Cancel'),
              )
            : null,
        onTap: () => openSalon(context, b.shopId),
      ),
    );
  }
}

/// Colored icon for a booking's status.
class BookingStatusIcon extends StatelessWidget {
  const BookingStatusIcon(this.status, {super.key});

  final BookingStatus status;

  @override
  Widget build(BuildContext context) {
    final (icon, color) = switch (status) {
      BookingStatus.pending => (Icons.hourglass_top, const Color(0xFFF59E0B)),
      BookingStatus.accepted => (Icons.check_circle, const Color(0xFF10B981)),
      BookingStatus.done => (Icons.how_to_reg, const Color(0xFF2563EB)),
      _ => (Icons.cancel, const Color(0xFF9CA3AF)),
    };
    return Icon(icon, color: color, size: 30);
  }
}

// -----------------------------------------------------------------------------
// Favorites
// -----------------------------------------------------------------------------

class _FavoritesTab extends ConsumerWidget {
  const _FavoritesTab();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final user = ref.watch(clientSessionProvider.select((s) => s.user));
    final favorites = ref.watch(favoriteSalonsProvider);
    return Scaffold(
      appBar: AppBar(title: const Text('Favorites')),
      body: user == null
          ? const _SignInFirst('Keep your favorite salons one tap away.')
          : switch (favorites) {
              AsyncData(:final value) when value.isEmpty => const Padding(
                padding: EdgeInsets.all(16),
                child: EmptyBox(
                  'No favorites yet. Tap the heart on a salon page.',
                ),
              ),
              AsyncData(:final value) => ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  for (final s in value) SalonCard(salon: s, isFavorite: true),
                ],
              ),
              AsyncError(:final error) => Center(
                child: Text(describeError(error)),
              ),
              _ => const Center(child: CircularProgressIndicator()),
            },
    );
  }
}

// -----------------------------------------------------------------------------
// Social: the latest cuts from listed salons
// -----------------------------------------------------------------------------

class _SocialTab extends ConsumerWidget {
  const _SocialTab();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final posts = ref.watch(latestPostsProvider);
    return Scaffold(
      appBar: AppBar(
        title: const Text('Fresh Cuts'),
        actions: [
          IconButton(
            tooltip: 'Refresh',
            icon: const Icon(Icons.refresh),
            onPressed: () => ref.invalidate(latestPostsProvider),
          ),
        ],
      ),
      body: switch (posts) {
        AsyncData(:final value) when value.isEmpty => const Padding(
          padding: EdgeInsets.all(16),
          child: EmptyBox('No photos yet. Barbers post their cuts here.'),
        ),
        AsyncData(:final value) => RefreshIndicator(
          onRefresh: () => ref.refresh(latestPostsProvider.future),
          child: PostGrid(posts: value, columns: 2, showSalon: true),
        ),
        AsyncError(:final error) => Center(
          child: TextButton(
            onPressed: () => ref.invalidate(latestPostsProvider),
            child: Text('${describeError(error)}\nTap to retry.'),
          ),
        ),
        _ => const Center(child: CircularProgressIndicator()),
      },
    );
  }
}

// -----------------------------------------------------------------------------
// Profile: the account and visits to rate, or signing in / up
// -----------------------------------------------------------------------------

class _ProfileTab extends ConsumerWidget {
  const _ProfileTab();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final session = ref.watch(clientSessionProvider);
    final user = session.user;

    return Scaffold(
      appBar: AppBar(title: const Text('My Profile')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          if (user == null)
            const _AccountForm()
          else ...[
            Card(
              child: ListTile(
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 8,
                ),
                leading: CircleAvatar(
                  radius: 26,
                  backgroundColor: Colors.black,
                  child: Text(
                    user.fullName.isEmpty
                        ? '?'
                        : user.fullName[0].toUpperCase(),
                    style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.w900,
                      fontSize: 20,
                    ),
                  ),
                ),
                title: Text(
                  user.fullName.isEmpty ? 'Client' : user.fullName,
                  style: const TextStyle(
                    fontWeight: FontWeight.w900,
                    fontSize: 17,
                  ),
                ),
                subtitle: Text(user.email),
              ),
            ),
            const SectionHeading('My visits'),
            const _VisitsList(),
            const SizedBox(height: 12),
            Card(
              child: ListTile(
                leading: const Icon(Icons.logout, color: Colors.red),
                title: const Text(
                  'Sign out',
                  style: TextStyle(color: Colors.red),
                ),
                onTap: () => ref.read(clientSessionProvider.notifier).logout(),
              ),
            ),
          ],
          if (user == null) ...[
            const SizedBox(height: 12),
            Card(
              child: ListTile(
                leading: const Icon(Icons.swap_horiz),
                title: const Text('Change space'),
                subtitle: const Text('Owner or barber? Go back.'),
                onTap: () => ref.read(entryRoleProvider.notifier).reset(),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

/// The client's finished cuts; rating one is what makes a barber's rating.
class _VisitsList extends ConsumerWidget {
  const _VisitsList();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final visits = ref.watch(myVisitsProvider);
    final user = ref.watch(clientSessionProvider.select((s) => s.user));
    return switch (visits) {
      AsyncData(:final value) when value.isEmpty => const EmptyBox(
        'Your cuts appear here after a visit, so you can rate them.',
      ),
      AsyncData(:final value) => Column(
        children: [
          for (final v in value)
            Card(
              margin: const EdgeInsets.only(bottom: 10),
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 12, 12, 10),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '${v.barberName} · ${v.shopName}',
                      style: const TextStyle(fontWeight: FontWeight.w800),
                    ),
                    Text(
                      '${v.services} · ${formatMoney(v.total)} · '
                      '${DateFormat('d MMM').format(v.time)}',
                      style: const TextStyle(color: _muted, fontSize: 12),
                    ),
                    const SizedBox(height: 6),
                    Row(
                      children: [
                        Text(
                          v.stars == null ? 'Rate your cut' : 'Your rating',
                          style: const TextStyle(fontSize: 13),
                        ),
                        const Spacer(),
                        StarPicker(
                          value: v.stars,
                          size: 26,
                          onChanged: (stars) async {
                            if (user == null) return;
                            await runAction(
                              context,
                              () => ref
                                  .read(clientActivityProvider)
                                  .rateVisit(
                                    clientId: user.id,
                                    ticketId: v.ticketId,
                                    stars: stars,
                                  ),
                              successMessage:
                                  'Thanks! ${v.barberName} sees '
                                  'your rating.',
                            );
                            dataChanged(ref);
                          },
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
        ],
      ),
      AsyncError(:final error) => EmptyBox(describeError(error)),
      _ => const EmptyBox('Loading…'),
    };
  }
}

class _AccountForm extends ConsumerStatefulWidget {
  const _AccountForm();

  @override
  ConsumerState<_AccountForm> createState() => _AccountFormState();
}

class _AccountFormState extends ConsumerState<_AccountForm> {
  static final _emailPattern = RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$');

  final _formKey = GlobalKey<FormState>();
  final _name = TextEditingController();
  final _email = TextEditingController();
  final _password = TextEditingController();
  bool _registering = true;

  @override
  void dispose() {
    _name.dispose();
    _email.dispose();
    _password.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (ref.read(clientSessionProvider).isLoading) return;
    if (!_formKey.currentState!.validate()) return;
    final session = ref.read(clientSessionProvider.notifier);
    if (_registering) {
      await session.register(
        fullName: _name.text,
        email: _email.text,
        password: _password.text,
      );
    } else {
      await session.login(email: _email.text, password: _password.text);
    }
  }

  @override
  Widget build(BuildContext context) {
    final session = ref.watch(clientSessionProvider);
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                _registering ? 'Create your account' : 'Sign in',
                style: const TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.w900,
                ),
              ),
              const SizedBox(height: 4),
              const Text(
                'Browse salons freely. An account lets you join a line, book '
                'and rate your cuts.',
                style: TextStyle(color: Color(0xFF6B7280), fontSize: 13),
              ),
              const SizedBox(height: 16),
              if (session.errorMessage != null)
                _Notice(session.errorMessage!, error: true),
              if (session.infoMessage != null) _Notice(session.infoMessage!),
              if (_registering) ...[
                TextFormField(
                  controller: _name,
                  textCapitalization: TextCapitalization.words,
                  decoration: const InputDecoration(
                    labelText: 'Your name',
                    prefixIcon: Icon(Icons.person_outline),
                  ),
                  validator: (v) => (v?.trim().isEmpty ?? true)
                      ? 'Please enter your name'
                      : null,
                ),
                const SizedBox(height: 12),
              ],
              TextFormField(
                controller: _email,
                keyboardType: TextInputType.emailAddress,
                decoration: const InputDecoration(
                  labelText: 'Email Address',
                  prefixIcon: Icon(Icons.email_outlined),
                ),
                validator: (v) {
                  final value = v?.trim() ?? '';
                  if (value.isEmpty) return 'Please enter an email';
                  return _emailPattern.hasMatch(value)
                      ? null
                      : 'Enter a valid email address';
                },
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _password,
                obscureText: true,
                onFieldSubmitted: (_) => _submit(),
                decoration: const InputDecoration(
                  labelText: 'Password',
                  prefixIcon: Icon(Icons.lock_outline),
                ),
                validator: (v) {
                  if (v == null || v.isEmpty) {
                    return 'Please enter your password';
                  }
                  if (_registering && v.length < 8) {
                    return 'Password must be at least 8 characters';
                  }
                  return null;
                },
              ),
              const SizedBox(height: 16),
              ElevatedButton(
                onPressed: session.isLoading ? null : _submit,
                child: session.isLoading
                    ? const SizedBox.square(
                        dimension: 20,
                        child: CircularProgressIndicator(
                          color: Colors.white,
                          strokeWidth: 2,
                        ),
                      )
                    : Text(_registering ? 'Create account' : 'Sign in'),
              ),
              TextButton(
                onPressed: () {
                  ref.read(clientSessionProvider.notifier).clearMessages();
                  setState(() => _registering = !_registering);
                },
                child: Text(
                  _registering
                      ? 'Already have an account? Sign in'
                      : 'New here? Create an account',
                  style: const TextStyle(
                    color: Colors.black,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Notice extends StatelessWidget {
  const _Notice(this.message, {this.error = false});

  final String message;
  final bool error;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: error ? const Color(0xFFFEE2E2) : const Color(0xFFD1FAE5),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: error ? const Color(0xFFF87171) : const Color(0xFF34D399),
        ),
      ),
      child: Text(
        message,
        style: TextStyle(
          color: error ? const Color(0xFFB91C1C) : const Color(0xFF065F46),
          fontSize: 13,
        ),
      ),
    );
  }
}

/// Opens a salon's page from anywhere in the client app.
void openSalon(BuildContext context, String shopId) => Navigator.of(context)
    .push(
      MaterialPageRoute<void>(builder: (_) => ClientSalonPage(shopId: shopId)),
    );
