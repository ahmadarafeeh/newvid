import 'package:in_app_purchase/in_app_purchase.dart';
import 'package:shared_preferences/shared_preferences.dart';

class IAPService {
  static final IAPService _instance = IAPService._internal();
  factory IAPService() => _instance;
  IAPService._internal();

  static const String productId =
      'ratedly_plus_1'; // <-- Change to your real Product ID
  static const String purchaseStatusKey = 'reactly_plus_purchased';

  final InAppPurchase _inAppPurchase = InAppPurchase.instance;
  bool _isAvailable = false;

  // Stream of purchase updates
  Stream<List<PurchaseDetails>> get purchaseStream =>
      _inAppPurchase.purchaseStream;

  Future<void> init() async {
    final bool isAvailable = await _inAppPurchase.isAvailable();
    _isAvailable = isAvailable;
    if (!isAvailable) {
      print('In-App Purchases not available');
    }
  }

  // Load product details from App Store
  Future<ProductDetails?> getProduct() async {
    if (!_isAvailable) return null;
    final Set<String> ids = {productId};
    final ProductDetailsResponse response =
        await _inAppPurchase.queryProductDetails(ids);
    if (response.notFoundIDs.isNotEmpty) {
      print('Product not found: ${response.notFoundIDs}');
      return null;
    }
    return response.productDetails.firstWhere(
      (details) => details.id == productId,
      orElse: () => throw Exception('Product not found'),
    );
  }

  // Buy the product
  Future<void> buyProduct(ProductDetails productDetails) async {
    if (!_isAvailable) return;
    final PurchaseParam purchaseParam = PurchaseParam(
      productDetails: productDetails,
    );
    await _inAppPurchase.buyNonConsumable(
      purchaseParam: purchaseParam,
    );
  }

  // Restore previous purchases
  Future<void> restorePurchases() async {
    if (!_isAvailable) return;
    await _inAppPurchase.restorePurchases();
  }

  // Check if already purchased (from local storage)
  Future<bool> isPurchased() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(purchaseStatusKey) ?? false;
  }

  // Save purchase status (called after successful verification)
  Future<void> setPurchased(bool value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(purchaseStatusKey, value);
  }
}
