import 'package:purchases_flutter/purchases_flutter.dart';
import 'package:shared_preferences/shared_preferences.dart';

class IAPService {
  static final IAPService _instance = IAPService._internal();
  factory IAPService() => _instance;
  IAPService._internal();

  static const String productId = 'ratedly_plus_1';
  static const String _purchaseKey = 'reactly_plus_purchased';

  static Future<void> init() async {
    await Purchases.setLogLevel(LogLevel.debug);
    await Purchases.configure(
      PurchasesConfiguration('appl_wMFHqyzgWfgFlLiPkstIsAIQira'),
    );
  }

  Future<StoreProduct?> getProduct() async {
    try {
      final offerings = await Purchases.getOfferings();
      print('Current offering: ${offerings.current?.identifier}');
      print('Available packages: ${offerings.current?.availablePackages.map((p) => p.storeProduct.identifier).toList()}');

      if (offerings.current == null || offerings.current!.availablePackages.isEmpty) {
        print('No offerings available');
        return null;
      }

      final package = offerings.current?.availablePackages.firstWhere(
        (p) => p.storeProduct.identifier == productId,
        orElse: () => offerings.current!.availablePackages.first,
      );
      return package?.storeProduct;
    } catch (e) {
      print('Failed to fetch product: $e');
      return null;
    }
  }

  Future<bool> buyProduct(StoreProduct product) async {
    try {
      final customerInfo = await Purchases.purchaseStoreProduct(product);
      final purchased = _isEntitled(customerInfo);
      if (purchased) await setPurchased(true);
      return purchased;
    } on PurchasesErrorCode catch (e) {
      if (e == PurchasesErrorCode.purchaseCancelledError) {
        return false;
      }
      rethrow;
    }
  }

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

  bool _isEntitled(CustomerInfo info) {
    return info.entitlements.active.containsKey('premium');
  }

  Future<bool> isPurchased() async {
    try {
      final info = await Purchases.getCustomerInfo();
      final purchased = _isEntitled(info);
      await setPurchased(purchased);
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
