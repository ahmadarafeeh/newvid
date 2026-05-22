import 'package:purchases_flutter/purchases_flutter.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class IAPService {
  static final IAPService _instance = IAPService._internal();
  factory IAPService() => _instance;
  IAPService._internal();

  static const String productId = 'ratedly_plus';
  static const String _purchaseKey = 'reactly_plus_purchased';

  // ─── Supabase logger ────────────────────────────────────────────────────────
  Future<void> _log({
    required String step,
    required String status,
    String? userId,
    String? productId,
    String? offeringId,
    String? errorMessage,
    String? errorCode,
    String? extraInfo,
  }) async {
    try {
      await Supabase.instance.client.from('purchase_logs').insert({
        'user_id': userId,
        'step': step,
        'status': status,
        'product_id': productId,
        'offering_id': offeringId,
        'error_message': errorMessage,
        'error_code': errorCode,
        'extra_info': extraInfo,
      });
    } catch (e) {
      print('[IAPLog] Failed to write log: $e');
    }
  }

  // ─── Init ────────────────────────────────────────────────────────────────────
  static Future<void> init() async {
    try {
      await Purchases.setLogLevel(LogLevel.debug);
      await Purchases.configure(
        PurchasesConfiguration('appl_wMFHqyzgWfgFlLiPkstIsAIQira'),
      );
      print('[IAP] RevenueCat configured successfully');
    } catch (e) {
      print('[IAP] Failed to configure RevenueCat: $e');
    }
  }

  // ─── Get Product ─────────────────────────────────────────────────────────────
  Future<StoreProduct?> getProduct() async {
    await _log(step: 'get_product', status: 'started');
    try {
      await _log(step: 'get_offerings', status: 'fetching');
      final offerings = await Purchases.getOfferings();

      if (offerings.current == null) {
        await _log(
          step: 'get_offerings',
          status: 'failed',
          errorMessage: 'offerings.current is null — no current offering set in RevenueCat dashboard',
          extraInfo: 'All offerings: ${offerings.all.keys.join(', ')}',
        );
        return null;
      }

      await _log(
        step: 'get_offerings',
        status: 'success',
        offeringId: offerings.current!.identifier,
        extraInfo: 'Packages: ${offerings.current!.availablePackages.map((p) => p.storeProduct.identifier).join(', ')}',
      );

      if (offerings.current!.availablePackages.isEmpty) {
        await _log(
          step: 'get_product',
          status: 'failed',
          offeringId: offerings.current!.identifier,
          errorMessage: 'No packages in current offering',
        );
        return null;
      }

      // Try to find exact product match
      Package? package;
      try {
        package = offerings.current!.availablePackages.firstWhere(
          (p) => p.storeProduct.identifier == productId,
        );
        await _log(
          step: 'get_product',
          status: 'found_exact_match',
          productId: package.storeProduct.identifier,
          extraInfo: 'Price: ${package.storeProduct.priceString}',
        );
      } catch (_) {
        // Fallback to first package
        package = offerings.current!.availablePackages.first;
        await _log(
          step: 'get_product',
          status: 'using_fallback_product',
          productId: package.storeProduct.identifier,
          extraInfo: 'Expected $productId but used fallback. Price: ${package.storeProduct.priceString}',
        );
      }

      return package.storeProduct;
    } catch (e) {
      await _log(
        step: 'get_product',
        status: 'exception',
        errorMessage: e.toString(),
        errorCode: e.runtimeType.toString(),
      );
      print('[IAP] Failed to fetch product: $e');
      return null;
    }
  }

  // ─── Purchase ────────────────────────────────────────────────────────────────
  Future<bool> buyProduct(StoreProduct product) async {
    String? userId;
    try {
      final info = await Purchases.getCustomerInfo();
      userId = info.originalAppUserId;
    } catch (_) {}

    await _log(
      step: 'buy_product',
      status: 'started',
      userId: userId,
      productId: product.identifier,
      extraInfo: 'Price: ${product.priceString}',
    );

    try {
      await _log(
        step: 'purchase_store_product',
        status: 'calling_apple',
        userId: userId,
        productId: product.identifier,
      );

      final customerInfo = await Purchases.purchaseStoreProduct(product);

      await _log(
        step: 'purchase_store_product',
        status: 'apple_returned',
        userId: userId,
        productId: product.identifier,
        extraInfo: 'Active entitlements: ${customerInfo.entitlements.active.keys.join(', ')}',
      );

      final purchased = _isEntitled(customerInfo);

      if (purchased) {
        await setPurchased(true);
        await _log(
          step: 'buy_product',
          status: 'success',
          userId: userId,
          productId: product.identifier,
        );
      } else {
        await _log(
          step: 'buy_product',
          status: 'entitlement_not_found',
          userId: userId,
          productId: product.identifier,
          errorMessage: 'Purchase went through but premium entitlement not found. Active: ${customerInfo.entitlements.active.keys.join(', ')}',
        );
      }

      return purchased;
    } on PurchasesErrorCode catch (e) {
      if (e == PurchasesErrorCode.purchaseCancelledError) {
        await _log(
          step: 'buy_product',
          status: 'cancelled_by_user',
          userId: userId,
          productId: product.identifier,
        );
        return false;
      }
      await _log(
        step: 'buy_product',
        status: 'purchases_error',
        userId: userId,
        productId: product.identifier,
        errorMessage: e.toString(),
        errorCode: e.index.toString(),
      );
      rethrow;
    } catch (e) {
      await _log(
        step: 'buy_product',
        status: 'exception',
        userId: userId,
        productId: product.identifier,
        errorMessage: e.toString(),
        errorCode: e.runtimeType.toString(),
      );
      rethrow;
    }
  }

  // ─── Restore ─────────────────────────────────────────────────────────────────
  Future<bool> restorePurchases() async {
    await _log(step: 'restore_purchases', status: 'started');
    try {
      final customerInfo = await Purchases.restorePurchases();
      final purchased = _isEntitled(customerInfo);

      await _log(
        step: 'restore_purchases',
        status: purchased ? 'success' : 'no_purchases_found',
        extraInfo: 'Active entitlements: ${customerInfo.entitlements.active.keys.join(', ')}',
      );

      if (purchased) await setPurchased(true);
      return purchased;
    } catch (e) {
      await _log(
        step: 'restore_purchases',
        status: 'exception',
        errorMessage: e.toString(),
        errorCode: e.runtimeType.toString(),
      );
      print('[IAP] Restore failed: $e');
      return false;
    }
  }

  // ─── Entitlement check ───────────────────────────────────────────────────────
  bool _isEntitled(CustomerInfo info) {
    return info.entitlements.active.containsKey('Reactly: Share & React Pro');
  }

  // ─── isPurchased ─────────────────────────────────────────────────────────────
  Future<bool> isPurchased() async {
    try {
      final info = await Purchases.getCustomerInfo();
      final purchased = _isEntitled(info);

      await _log(
        step: 'is_purchased_check',
        status: purchased ? 'premium_active' : 'not_premium',
        userId: info.originalAppUserId,
        extraInfo: 'Active entitlements: ${info.entitlements.active.keys.join(', ')}',
      );

      await setPurchased(purchased);
      return purchased;
    } catch (e) {
      await _log(
        step: 'is_purchased_check',
        status: 'exception_using_cache',
        errorMessage: e.toString(),
      );
      final prefs = await SharedPreferences.getInstance();
      return prefs.getBool(_purchaseKey) ?? false;
    }
  }

  Future<void> setPurchased(bool value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_purchaseKey, value);
  }
}
