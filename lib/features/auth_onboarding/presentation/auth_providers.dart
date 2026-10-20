import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/auth/account_auth.dart';
import '../../../core/demo/demo_seeder.dart';
import '../../../core/errors/app_exception.dart';
import '../../../core/providers/core_providers.dart';
import '../../../core/providers/data_revision.dart';
import '../../../core/repositories/floor_plan_repository.dart';
import '../../../core/repositories/queue_repository.dart';
import '../../../core/repositories/shop_repository.dart';
import '../domain/owner_account.dart';
import '../domain/shop_profile.dart';
import '../../barbers/domain/barber.dart';

final shopRepositoryProvider = Provider<ShopRepository>((ref) {
  return ShopRepository(
    dbService: ref.watch(databaseServiceProvider),
    passwordHasher: ref.watch(passwordHasherProvider),
    sessionStorage: ref.watch(sessionStorageProvider),
  );
});

final demoSeederProvider = Provider<DemoSeeder>((ref) {
  final db = ref.watch(databaseServiceProvider);
  return DemoSeeder(
    dbService: db,
    shops: ref.watch(shopRepositoryProvider),
    floor: FloorPlanRepository(dbService: db),
    queue: QueueRepository(dbService: db),
  );
});

/// The id of the signed-in owner's shop, or null. Feature providers watch
/// this instead of the whole [AuthState] so they only reload when the shop
/// itself changes.
final currentShopIdProvider = Provider<String?>((ref) {
  return ref.watch(authProvider.select((s) => s.shop?.id));
});

class AuthState {
  const AuthState({
    this.owner,
    this.shop,
    this.isLoading = false,
    this.errorMessage,
    this.infoMessage,
  });

  final OwnerAccount? owner;
  final ShopProfile? shop;
  final bool isLoading;
  final String? errorMessage;

  /// A notice that is not an error, e.g. "confirm your email".
  final String? infoMessage;

  bool get isAuthenticated => owner != null;
  bool get hasCompletedOnboarding => shop != null;

  AuthState copyWith({
    OwnerAccount? owner,
    ShopProfile? shop,
    bool? isLoading,
    String? errorMessage,
    bool clearError = false,
    bool clearShop = false,
  }) {
    return AuthState(
      owner: owner ?? this.owner,
      shop: clearShop ? null : (shop ?? this.shop),
      isLoading: isLoading ?? this.isLoading,
      errorMessage: clearError ? null : (errorMessage ?? this.errorMessage),
      infoMessage: clearError ? null : infoMessage,
    );
  }
}

class AuthNotifier extends Notifier<AuthState> {
  @override
  AuthState build() {
    Future.microtask(checkInitialSession);
    return const AuthState(isLoading: true);
  }

  ShopRepository get _repository => ref.read(shopRepositoryProvider);
  AccountAuth get _auth => ref.read(accountAuthProvider);

  /// Restores the owner signed in on this device, with their salon.
  Future<void> checkInitialSession() async {
    state = state.copyWith(isLoading: true, clearError: true);
    final user = _auth.currentUser;
    if (user == null || user.role != AccountRole.owner) {
      state = const AuthState();
      return;
    }
    await _open(user);
  }

  /// Creates an owner account on this device and signs it in.
  Future<bool> register({
    required String email,
    required String password,
    required String fullName,
  }) async {
    state = state.copyWith(isLoading: true, clearError: true);
    try {
      final user = await _auth.signUp(
        email: email,
        password: password,
        fullName: fullName,
        role: AccountRole.owner,
      );
      await _open(user);
      return true;
    } catch (e) {
      state = state.copyWith(isLoading: false, errorMessage: describeError(e));
      return false;
    }
  }

  Future<bool> login({required String email, required String password}) async {
    state = state.copyWith(isLoading: true, clearError: true);
    try {
      final user = await _auth.signIn(email: email, password: password);
      if (user.role != AccountRole.owner) {
        await _auth.signOut();
        throw const AppException(
          'This is not a salon owner account. Go back and choose your space.',
        );
      }
      await _open(user);
      return true;
    } catch (e) {
      state = state.copyWith(isLoading: false, errorMessage: describeError(e));
      return false;
    }
  }

  /// Creates the demo salon and its accounts if needed, then signs in as
  /// its owner.
  Future<bool> loginDemo() async {
    state = state.copyWith(isLoading: true, clearError: true);
    try {
      await ref.read(demoSeederProvider).ensureDemoAccount();
      return await login(
        email: DemoSeeder.email,
        password: DemoSeeder.password,
      );
    } catch (e) {
      state = state.copyWith(isLoading: false, errorMessage: describeError(e));
      return false;
    }
  }

  Future<void> _open(AppUser user) async {
    try {
      final owner = await _repository.getOwner(user.id);
      if (owner == null) {
        await _auth.signOut();
        state = const AuthState();
        return;
      }
      final shop = await _repository.getShopProfileByOwnerId(owner.id);
      // Barbers and clients may have changed the salon meanwhile.
      ref.read(dataRevisionProvider.notifier).bump();
      state = AuthState(owner: owner, shop: shop);
    } catch (e) {
      state = AuthState(errorMessage: describeError(e));
    }
  }

  void clearError() {
    if (state.errorMessage != null) {
      state = state.copyWith(clearError: true);
    }
  }

  Future<bool> completeOnboarding({
    required String name,
    required String address,
    required String phone,
    required int totalChairs,
    required List<Barber> initialBarbers,
    required List<ServiceItem> services,
  }) async {
    final owner = state.owner;
    if (owner == null) return false;

    state = state.copyWith(isLoading: true, clearError: true);
    try {
      final shop = await _repository.setupShopProfile(
        ownerId: owner.id,
        name: name,
        address: address,
        phone: phone,
        totalChairs: totalChairs,
        initialBarbers: initialBarbers,
        services: services,
      );
      state = state.copyWith(shop: shop, isLoading: false);
      return true;
    } catch (e) {
      state = state.copyWith(isLoading: false, errorMessage: describeError(e));
      return false;
    }
  }

  /// Reloads the shop profile (details and services) from the database.
  Future<void> reloadShop() async {
    final owner = state.owner;
    if (owner == null) return;
    final shop = await _repository.getShopProfileByOwnerId(owner.id);
    state = state.copyWith(shop: shop, clearShop: shop == null);
  }

  Future<void> updateShopDetails({
    required String name,
    required String address,
    required String phone,
  }) async {
    final shop = state.shop;
    if (shop == null) return;
    await _repository.updateShopDetails(
      shopId: shop.id,
      name: name,
      address: address,
      phone: phone,
    );
    await reloadShop();
  }

  Future<void> setShopOpen(bool isOpen) async {
    final shop = state.shop;
    if (shop == null) return;
    await _repository.setShopOpen(shopId: shop.id, isOpen: isOpen);
    await reloadShop();
  }

  Future<void> setShopListed(bool isListed) async {
    final shop = state.shop;
    if (shop == null) return;
    await _repository.setShopListed(shopId: shop.id, isListed: isListed);
    await reloadShop();
  }

  Future<void> saveService({
    String? serviceId,
    required String name,
    required double price,
    required int durationMinutes,
  }) async {
    final shop = state.shop;
    if (shop == null) return;
    await _repository.saveService(
      shopId: shop.id,
      serviceId: serviceId,
      name: name,
      price: price,
      durationMinutes: durationMinutes,
    );
    await reloadShop();
  }

  Future<void> deleteService(String serviceId) async {
    final shop = state.shop;
    if (shop == null) return;
    await _repository.deleteService(shopId: shop.id, serviceId: serviceId);
    await reloadShop();
  }

  /// Throws [AppException] when chairs being removed are in use.
  Future<void> updateChairCount(int newCount) async {
    final shop = state.shop;
    if (shop == null) return;
    await _repository.updateChairCapacity(
      shopId: shop.id,
      newCapacity: newCount,
    );
    state = state.copyWith(shop: shop.copyWith(totalChairs: newCount));
  }

  Future<void> logout() async {
    await _auth.signOut();
    state = const AuthState();
  }
}

final authProvider = NotifierProvider<AuthNotifier, AuthState>(
  AuthNotifier.new,
);
