// lib/services/iap_service.dart
import 'package:purchases_flutter/purchases_flutter.dart';
import 'package:shared_preferences/shared_preferences.dart';

class IAPService {
  static final IAPService _instance = IAPService._internal();
  factory IAPService() => _instance;
  IAPService._internal();

  static const String productId = 'ratedly_plus_1'; // your App Store product ID
  static const String _purchaseKey = 'reactly_plus_purchased';

  // ─── Call once at app startup (in main.dart) ────────────────────────────────
  static Future<void> init() async {
    await Purchases.setLogLevel(LogLevel.debug); // remove in production
    await Purchases.configure(
      PurchasesConfiguration(
          'test_LCYdlOePnZHXQokJfTjkJLzytyK'), // iOS key from RC dashboard
    );
  }

  // ─── Fetch the product from App Store via RevenueCat ────────────────────────
  Future<StoreProduct?> getProduct() async {
    try {
      final offerings = await Purchases.getOfferings();
      // Uses your "current" offering in RevenueCat dashboard
      final package = offerings.current?.availablePackages.firstWhere(
          (p) => p.storeProduct.identifier == productId,
          orElse: () => offerings.current!.availablePackages.first);
      return package?.storeProduct;
    } catch (e) {
      print('Failed to fetch product: $e');
      return null;
    }
  }

  // ─── Purchase ────────────────────────────────────────────────────────────────
  Future<bool> buyProduct(StoreProduct product) async {
    try {
      final customerInfo = await Purchases.purchaseStoreProduct(product);
      final purchased = _isEntitled(customerInfo);
      if (purchased) await setPurchased(true);
      return purchased;
    } on PurchasesErrorCode catch (e) {
      if (e == PurchasesErrorCode.purchaseCancelledError) {
        return false; // user cancelled — not an error
      }
      rethrow;
    }
  }

  // ─── Restore ─────────────────────────────────────────────────────────────────
  Future<bool> restorePurchases() async {
    try {
      final customerInfo = await Purchases.restorePurchases();
      final purchased = _isEntitled(customerInfo);
      if (purchased) await setPurchased(true);
      return purchased;
    } catch (e) {
      print('Restore failed: $e');
      return false;
    }
  }

  // ─── Check entitlement (use RC entitlement ID you set in dashboard) ──────────
  bool _isEntitled(CustomerInfo info) {
    return info.entitlements.active
        .containsKey('premium'); // your entitlement ID
  }

  // ─── Local cache (fast UI, no network on every open) ─────────────────────────
  Future<bool> isPurchased() async {
    // First check RC (source of truth), fall back to local cache
    try {
      final info = await Purchases.getCustomerInfo();
      final purchased = _isEntitled(info);
      await setPurchased(purchased); // keep cache in sync
      return purchased;
    } catch (_) {
      final prefs = await SharedPreferences.getInstance();
      return prefs.getBool(_purchaseKey) ?? false;
    }
  }

  Future<void> setPurchased(bool value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_purchaseKey, value);
  }
}
