# Siz

**Siz** (short for *Scissors*) is a barbershop app for Android with three spaces
in one app:

- **Salon owners** run the shop floor, team, clients, bookings and finances.
- **Barbers** see their salon live, their agenda, earnings and photo portfolio.
- **Clients** find a salon, join its waiting line, book a barber, and rate
  their cuts.

Everything runs **locally on the phone**: the data is in a SQLite database,
the accounts are on the device, and the photos are files in the app's private
folder. The app needs no server and no internet connection, and it does not
ask for the internet permission.

## Try it

On the first screen, tap **Try the demo**. The app creates three salons
on the phone, with accounts for each role. Tap an account to sign in.

| Role | Email | Password | What to look at |
|---|---|---|---|
| Owner | demo@barbershop.app | Demo2026! | Blade & Crown: live floor, finances, bookings to accept |
| Barber | sami@siz.app | Barber2026! | Agenda with a booking, earnings, portfolio, 5.0 rating |
| Barber | karim@siz.app | Barber2026! | A second barber of the same salon |
| Client | lina@siz.app | Client2026! | Visits to rate, bookings, favorites |
| Client | adam@siz.app | Client2026! | Waiting in line at Blade & Crown |
| Owner | mehdi@siz.app | Owner2026! | Fade Factory, a second salon |

These are demo accounts created on the phone only; they are not real
credentials.

## Features

| Space | What it does |
|---|---|
| **Accounts** | One account store for the three roles. Each account has a role, and each space refuses accounts of another role. Passwords are hashed with PBKDF2-HMAC-SHA256 (100,000 iterations, random salt), never stored in clear. The signed-in account is kept in the Android Keystore (`flutter_secure_storage`). |
| **Owner: floor** | Live chair map. Assign on-duty barbers, seat clients from the line or as walk-ins, check out (cash or card, tips, commission split), cancel a service. |
| **Owner: team** | Add, edit and archive barbers, and set them on or off duty. **Invite to the app** gives a one-time 8-character code (valid 7 days). The owner accepts or declines name changes that barbers ask for. |
| **Owner: clients** | Waiting line, **booking requests** (accept, decline, check in), and client history. |
| **Owner: finance** | Revenue, shop net, commissions, tips and payouts by period. |
| **Owner: settings** | Shop details, services and prices, number of chairs, "Show my salon to clients", "Open now". |
| **Barber** | Join with the code first: the code shows the salon and the name the owner registered, then the barber creates the account. Barbers see the live floor and their agenda (bookings and the line), and can go on/off duty and add walk-ins. They see their own earnings only, and post photos of their cuts with captions. Leaving the salon keeps the account. |
| **Client** | Browse without an account. The list of salons has search and an "Open now" filter, and shows open salons with the shortest line first. Each salon page shows the live floor (barbers only, never who is seated), barbers with ratings, prices and photos. With an account a client can join the line (one line at a time), book a service, barber, day and time, keep favorites, rate their visits, and rate and comment on photos. |

### Rules the app enforces

- **No double booking:** a barber, and a client, can have only one active booking at a time slot.
- **Ratings are honest:** a barber's rating comes only from clients' ratings of their **real visits**. A client can rate only their own visits. Photo ratings are shown separately.
- **Money is never computed by the screen:** prices and commission are read from the database at checkout, and a service can be charged only once.
- A barber cannot go off duty, be archived or leave while serving a client.
- Clients never see who is sitting in a chair.

## How it is built

- **Flutter 3.47** (Dart 3.13), **Riverpod 3** for state, **sqflite** for SQLite.
- One database (`siz.db`, schema version 7). All SQL and business rules live
  in repositories and run inside transactions, and failures are reported as
  `AppException` with a user-facing message.

```
lib/
  core/
    auth/          LocalAccountAuth: sign-up, sign-in, session (all roles)
    database/      DatabaseService: one connection, schema and migrations
    repositories/  Shops, barbers, floor, queue, finance (SQL + rules)
    media/         Photo compression and storage, drawn demo photos
    security/      PasswordHasher (PBKDF2), SessionStorage (Keystore)
    demo/          DemoSeeder: the "Try the demo" data
  features/
    auth_onboarding/  Owner sign-in and the salon setup wizard
    floor_plan/ barbers/ clients/ finance/ settings/   Owner space
    barber_app/       Barber space: code join, agenda, earnings, portfolio
    client_app/       Client space: salons, line, bookings, ratings, favorites
    bookings/         Booking lists shared by owners and barbers
    welcome/          "Who are you?" and the demo accounts
```

### Main tables

`owners` (every account, with `role`), `shops`, `barbers`, `chairs`,
`services`, `queue`, `tickets` (sales), `barber_invites`, `bookings`,
`visit_ratings`, `portfolio_posts`, `post_comments`, `photo_ratings`,
`favorites`.

A client account follows its visit from start to end:
`queue.client_id`, then `chairs.active_client_id`, then `tickets.client_id`.
This link is what lets a client rate their own cut.

## Development

```bash
flutter pub get
flutter run          # on an Android phone or emulator
flutter test         # unit, widget and SQLite integration tests
flutter analyze --fatal-infos
```

The tests run on a real SQLite database (`sqflite_common_ffi`) and need no
phone.

## Getting the APK

The APK is built by GitHub Actions; no Android SDK is needed on the PC.

- `.github/workflows/ci.yml` checks format, runs the analyzer and the tests on every push.
- `.github/workflows/build_release.yml` builds the release APK when a tag such
  as `v1.0.0` is pushed, and publishes it on the repository's **Releases**
  page as `Siz-v1.0.0.apk`.

To install it on a phone, open the release page in the phone's browser,
download the APK and allow installing from this source.
